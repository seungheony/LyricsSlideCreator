import errno
import functools
import hashlib
import http.server
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

from src.utils import updater

NOTES_GENERATED = """<!-- Release notes generated using configuration in .github/release.yml -->
## What's Changed
* feat: 줄바꿈 경고 표시 by @seungheony in https://github.com/seungheony/lyricsSlide_Creator/pull/12
* fix(updater): 다운로드 취소 by @seungheony in https://github.com/seungheony/lyricsSlide_Creator/pull/13
* 검색 속도 개선 by @dependabot[bot] in https://github.com/seungheony/lyricsSlide_Creator/pull/14

## New Contributors
* @someone made their first contribution in https://github.com/seungheony/lyricsSlide_Creator/pull/9

**Full Changelog**: https://github.com/seungheony/lyricsSlide_Creator/compare/v1.2.0...v1.2.1
"""


class ReleaseNotes(unittest.TestCase):
    def test_section_only(self):
        body = '## 바뀐 점\r\n- 업데이트를 취소할 수 있어요\r\n- 링크 [안내](https://x.y/a)\r\n\r\n## 기타\r\n* chore: 내부\r\n'
        self.assertEqual(updater.release_notes(body), '- 업데이트를 취소할 수 있어요\n- 링크 [안내](https://x.y/a)')

    def test_generated_notes_cleaned(self):
        self.assertEqual(updater.release_notes(NOTES_GENERATED),
                         '* 줄바꿈 경고 표시\n* 다운로드 취소\n* 검색 속도 개선')

    def test_signing_policy_link_removed(self):
        link = '[Code signing policy](https://github.com/seungheony/lyricsSlide_Creator#code-signing-policy)'
        self.assertEqual(updater.release_notes(link + '\n\n' + NOTES_GENERATED),
                         '* 줄바꿈 경고 표시\n* 다운로드 취소\n* 검색 속도 개선')
        self.assertEqual(updater.release_notes(link), '')

    def test_empty(self):
        for body in ('', None, '**Full Changelog**: https://github.com/a/b/compare/v1...v2'):
            self.assertEqual(updater.release_notes(body), '')
        self.assertEqual(updater.notes_html(''), '')

    def test_html(self):
        out = updater.notes_html('### 새 기능\n* **굵게** <태그> `코드`\n* [안내](https://x.y/a?b=1&c=2)\n\n끝 https://x.y/z')
        self.assertEqual(out, '<p><b>새 기능</b></p><ul><li><b>굵게</b> &lt;태그&gt; 코드</li>'
                              '<li><a href="https://x.y/a?b=1&amp;c=2">안내</a></li></ul>'
                              '<p>끝 <a href="https://x.y/z">https://x.y/z</a></p>')


class _Handler(http.server.SimpleHTTPRequestHandler):
    """천천히 보내는 파일(slow.bin)로 취소를 시험한다"""

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.endswith('slow.bin'):
            self.send_response(200)
            self.send_header('Content-Length', str(64 * 1024 * 1024))
            self.end_headers()
            try:
                for _ in range(256):
                    self.wfile.write(b'x' * 256 * 1024)
                    time.sleep(0.02)
            except OSError:
                pass
            return
        super().do_GET()


class UpdaterTmp(unittest.TestCase):
    """UPDATE_DIR을 시험용 임시 폴더로 바꾼다"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.update_dir = os.path.join(self.tmp, 'LyricsSlideCreator-update')
        patcher = mock.patch.object(updater, 'UPDATE_DIR', self.update_dir)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(setattr, updater, '_launched', False)


class Download(UpdaterTmp):
    @classmethod
    def setUpClass(cls):
        cls.www = tempfile.mkdtemp()
        cls.payload = os.urandom(600 * 1024)
        with open(os.path.join(cls.www, 'App-macOS.zip'), 'wb') as f:
            f.write(cls.payload)
        digest = hashlib.sha256(cls.payload).hexdigest()
        with open(os.path.join(cls.www, 'SHA256SUMS.txt'), 'w') as f:
            f.write(f'{digest}  App-macOS.zip\n{"0" * 64}  Bad-macOS.zip\n{"0" * 64}  slow.bin\n')
        shutil.copy(os.path.join(cls.www, 'App-macOS.zip'), os.path.join(cls.www, 'Bad-macOS.zip'))
        handler = functools.partial(_Handler, directory=cls.www)
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f'http://127.0.0.1:{cls.server.server_address[1]}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        shutil.rmtree(cls.www, ignore_errors=True)

    def info(self, name):
        return {'name': name, 'url': f'{self.base}/{name}', 'sums_url': f'{self.base}/SHA256SUMS.txt', 'size': 0}

    def test_ok_with_progress(self):
        seen = []
        path = updater.download(self.info('App-macOS.zip'), lambda d, t: seen.append((d, t)))
        with open(path, 'rb') as f:
            self.assertEqual(f.read(), self.payload)
        self.assertEqual(seen[-1], (len(self.payload), len(self.payload)))

    def test_checksum_mismatch_removes_file(self):
        with self.assertRaises(updater.UpdateError) as cm:
            updater.download(self.info('Bad-macOS.zip'))
        self.assertIn('손상', str(cm.exception))
        self.assertIn('SHA256', cm.exception.detail)
        self.assertFalse(os.path.exists(self.update_dir))

    def test_cancel_removes_partial_file(self):
        cancel = threading.Event()
        started = threading.Event()

        def progress(done, total):
            started.set()
        threading.Timer(0.3, cancel.set).start()
        t0 = time.monotonic()
        with self.assertRaises(updater.UpdateCancelled):
            updater.download(self.info('slow.bin'), progress, cancel)
        self.assertTrue(started.is_set())
        self.assertLess(time.monotonic() - t0, 3)
        self.assertFalse(os.path.exists(self.update_dir))

    def test_disk_full_is_update_error(self):
        real_open = open

        def fake_open(path, *a, **kw):
            # 같은 프로세스의 시험 서버가 여는 원본 파일은 건드리지 않는다
            if str(path).startswith(self.update_dir):
                raise OSError(errno.ENOSPC, 'No space left on device')
            return real_open(path, *a, **kw)
        with mock.patch('builtins.open', fake_open):
            with self.assertRaises(updater.UpdateError) as cm:
                updater.download(self.info('App-macOS.zip'))
        self.assertIn('저장 공간', str(cm.exception))
        self.assertIn('No space', cm.exception.detail)

    def test_network_error_is_update_error(self):
        info = self.info('App-macOS.zip')
        info['sums_url'] = 'http://127.0.0.1:9/none'
        with self.assertRaises(updater.UpdateError) as cm:
            updater.download(info)
        self.assertIn('인터넷 연결', str(cm.exception))
        self.assertTrue(cm.exception.detail)


class InstallWindows(UpdaterTmp):
    def setUp(self):
        super().setUp()
        os.makedirs(self.update_dir)
        self.order = []
        for name in ('release_app_mutex', 'hold_app_mutex'):
            p = mock.patch.object(updater, name, side_effect=lambda n=name: self.order.append(n))
            p.start()
            self.addCleanup(p.stop)
        p = mock.patch.object(updater.platform, 'system', return_value='Windows')
        p.start()
        self.addCleanup(p.stop)
        for flag in ('DETACHED_PROCESS', 'CREATE_NEW_PROCESS_GROUP'):
            if not hasattr(subprocess, flag):
                p = mock.patch.object(subprocess, flag, 0, create=True)
                p.start()
                self.addCleanup(p.stop)

    def test_silent_with_log_and_mutex_released_first(self):
        with mock.patch.object(updater.subprocess, 'Popen', side_effect=lambda *a, **k: self.order.append('popen')) as popen:
            updater.install('C:\\x\\Setup.exe', '1.2.0', '1.2.1')
        args = popen.call_args[0][0]
        self.assertIn('/SILENT', args)
        self.assertIn('/SUPPRESSMSGBOXES', args)
        self.assertNotIn('/VERYSILENT', args)
        self.assertIn('/LOG=' + os.path.join(self.update_dir, 'install.log'), args)
        self.assertEqual(self.order, ['release_app_mutex', 'popen'])
        with open(os.path.join(self.update_dir, 'pending.json')) as f:
            self.assertEqual(json.load(f), {'from': '1.2.0', 'to': '1.2.1'})
        self.assertFalse(updater.cancel(threading.Event()))   # 이미 시작했으면 취소할 수 없다

    def test_cancelled_before_launch(self):
        cancel = threading.Event()
        self.assertTrue(updater.cancel(cancel))
        with mock.patch.object(updater.subprocess, 'Popen') as popen:
            with self.assertRaises(updater.UpdateCancelled):
                updater.install('C:\\x\\Setup.exe', '1.2.0', '1.2.1', cancel)
        popen.assert_not_called()
        self.assertEqual(self.order, [])
        self.assertFalse(os.path.exists(os.path.join(self.update_dir, 'pending.json')))

    def test_launch_failure_keeps_mutex(self):
        with mock.patch.object(updater.subprocess, 'Popen', side_effect=OSError('blocked')):
            with self.assertRaises(updater.UpdateError) as cm:
                updater.install('C:\\x\\Setup.exe', '1.2.0', '1.2.1')
        self.assertIn('blocked', cm.exception.detail)
        self.assertEqual(self.order, ['release_app_mutex', 'hold_app_mutex'])


class LastResult(UpdaterTmp):
    def write(self, name, text):
        os.makedirs(self.update_dir, exist_ok=True)
        with open(os.path.join(self.update_dir, name), 'w', encoding='utf-8') as f:
            f.write(text)

    def test_none_without_pending(self):
        self.write('leftover.zip', 'x')
        self.assertIsNone(updater.take_last_result('1.2.0'))
        self.assertFalse(os.path.exists(self.update_dir))

    def test_ok(self):
        self.write('pending.json', '{"from": "1.2.0", "to": "1.2.1"}')
        self.assertEqual(updater.take_last_result('1.2.1'), {'ok': True, 'version': '1.2.1', 'detail': ''})
        self.assertFalse(os.path.exists(self.update_dir))

    def test_failed_with_reason(self):
        self.write('pending.json', '{"from": "1.2.0", "to": "1.2.1"}')
        self.write('result.txt', '새 앱의 서명을 확인하지 못했어요.\n')
        r = updater.take_last_result('1.2.0')
        self.assertFalse(r['ok'])
        self.assertEqual(r['detail'], '새 앱의 서명을 확인하지 못했어요.')

    def test_failed_windows_log_tail(self):
        self.write('pending.json', '{"from": "1.2.0", "to": "1.2.1"}')
        self.write('install.log', ''.join(f'줄 {i}\n' for i in range(100)))
        r = updater.take_last_result('1.2.0')
        self.assertFalse(r['ok'])
        self.assertTrue(r['detail'].startswith('줄 60') and r['detail'].endswith('줄 99'))


class CanInstallMac(UpdaterTmp):
    def setUp(self):
        super().setUp()
        p = mock.patch.object(updater.platform, 'system', return_value='Darwin')
        p.start()
        self.addCleanup(p.stop)
        self.apps = os.path.join(self.tmp, 'Applications')
        self.app = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        os.makedirs(self.app)

    def check(self, app):
        with mock.patch.object(updater, 'current_app_bundle', return_value=app):
            updater.can_install()

    def test_ok(self):
        self.check(self.app)

    def test_not_bundle(self):
        with self.assertRaises(updater.UpdateError):
            self.check(None)

    def test_translocated(self):
        with self.assertRaises(updater.UpdateError) as cm:
            self.check('/private/var/folders/x/AppTranslocation/ABC/d/가사 슬라이드 생성기.app')
        self.assertIn('응용 프로그램', str(cm.exception))

    @unittest.skipIf(os.name == 'nt' or (hasattr(os, 'geteuid') and os.geteuid() == 0), '권한 시험은 일반 사용자 유닉스에서만')
    def test_read_only_folder(self):
        os.chmod(self.apps, 0o555)
        self.addCleanup(os.chmod, self.apps, 0o755)
        with self.assertRaises(updater.UpdateError) as cm:
            self.check(self.app)
        self.assertIn('권한', str(cm.exception))
        self.assertIn(self.app, cm.exception.detail)

    def test_unsupported_os(self):
        with mock.patch.object(updater.platform, 'system', return_value='Linux'):
            with self.assertRaises(updater.UpdateError):
                updater.can_install()


def make_app(path, marker, exe='run', sign=True):
    os.makedirs(os.path.join(path, 'Contents', 'MacOS'))
    with open(os.path.join(path, 'Contents', 'Info.plist'), 'wb') as f:
        plistlib.dump({'CFBundleExecutable': exe, 'CFBundleIdentifier': 'test.fake.lyricsslidecreator',
                       'CFBundlePackageType': 'APPL'}, f)
    run = os.path.join(path, 'Contents', 'MacOS', 'run')
    with open(run, 'w') as f:
        f.write(f'#!/bin/sh\n# {marker}\nexit 0\n')
    os.chmod(run, 0o755)
    if sign:
        subprocess.run(['codesign', '--force', '--deep', '--sign', '-', path], check=True, capture_output=True)


@unittest.skipUnless(sys.platform == 'darwin', 'macOS 교체 스크립트')
class ApplyScript(unittest.TestCase):
    """APPLY_SH를 가짜 앱 번들로 실행한다. 'open'은 기록만 하는 가짜로 바꾼다 (실제 앱을 열지 않음)"""

    def setUp(self):
        # 경로에 따옴표·$·공백이 있어도 안전한지 함께 본다
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.apps = os.path.join(self.tmp, 'it\'s "q" $HOME', 'Applications')
        os.makedirs(self.apps)
        self.work = os.path.join(self.tmp, 'update')
        os.makedirs(os.path.join(self.work, 'extracted'))
        self.script = os.path.join(self.work, 'apply.sh')
        with open(self.script, 'w') as f:
            f.write(updater.APPLY_SH)
        bin_dir = os.path.join(self.tmp, 'bin')
        os.makedirs(bin_dir)
        self.opened = os.path.join(self.tmp, 'opened.txt')
        with open(os.path.join(bin_dir, 'open'), 'w') as f:
            f.write(f'#!/bin/sh\nprintf "%s\\n" "$1" >> {json.dumps(self.opened)}\n')
        os.chmod(os.path.join(bin_dir, 'open'), 0o755)
        self.env = dict(os.environ, PATH=bin_dir + os.pathsep + os.environ['PATH'])
        self.result = os.path.join(self.work, 'result.txt')
        self.new = os.path.join(self.work, 'extracted', '가사 슬라이드 생성기.app')

    def apply(self, old, dest, pid=None, wait=5):
        if pid is None:
            p = subprocess.Popen(['true'])
            p.wait()
            pid = p.pid          # 이미 끝난 프로세스
        return subprocess.run(['/bin/bash', self.script, str(pid), self.new, old, dest, self.result, str(wait)],
                              env=self.env, capture_output=True, timeout=30)

    def read_result(self):
        with open(self.result, encoding='utf-8') as f:
            return f.read()

    def marker(self, app):
        with open(os.path.join(app, 'Contents', 'MacOS', 'run')) as f:
            return f.read().split('# ')[1].split('\n')[0]

    def opened_paths(self):
        try:
            with open(self.opened) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def leftovers(self):
        return sorted(os.listdir(self.apps))

    def test_replace_in_place(self):
        old = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        make_app(old, 'old')
        make_app(self.new, 'new')
        r = self.apply(old, old)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.marker(old), 'new')
        self.assertEqual(self.leftovers(), ['가사 슬라이드 생성기.app'])    # 백업도 지웠다
        self.assertEqual(self.opened_paths(), [old])
        self.assertFalse(os.path.exists(self.result))

    def test_legacy_name_moved_to_new_name(self):
        old = os.path.join(self.apps, 'Lyrics Slide Creator.app')
        dest = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        make_app(old, 'old')
        make_app(self.new, 'new')
        r = self.apply(old, dest)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.leftovers(), ['가사 슬라이드 생성기.app'])
        self.assertEqual(self.marker(dest), 'new')
        self.assertEqual(self.opened_paths(), [dest])

    def test_missing_executable_rolls_back(self):
        old = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        make_app(old, 'old')
        make_app(self.new, 'new', exe='missing', sign=False)
        r = self.apply(old, old)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.marker(old), 'old')
        self.assertEqual(self.leftovers(), ['가사 슬라이드 생성기.app'])
        self.assertIn('실행 파일', self.read_result())
        self.assertEqual(self.opened_paths(), [old])    # 이전 앱을 다시 연다

    def test_bad_signature_rolls_back(self):
        old = os.path.join(self.apps, 'Lyrics Slide Creator.app')
        dest = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        make_app(old, 'old')
        make_app(self.new, 'new')
        with open(os.path.join(self.new, 'Contents', 'MacOS', 'run'), 'a') as f:
            f.write('# 서명 뒤에 바뀜\n')
        r = self.apply(old, dest)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.leftovers(), ['Lyrics Slide Creator.app'])
        self.assertEqual(self.marker(old), 'old')
        self.assertIn('서명', self.read_result())
        self.assertEqual(self.opened_paths(), [old])

    def test_wait_timeout_leaves_app_alone(self):
        old = os.path.join(self.apps, '가사 슬라이드 생성기.app')
        make_app(old, 'old')
        make_app(self.new, 'new')
        still_running = subprocess.Popen(['sleep', '30'])
        self.addCleanup(still_running.wait)
        self.addCleanup(still_running.terminate)
        t0 = time.monotonic()
        r = self.apply(old, old, pid=still_running.pid, wait=1)
        self.assertLess(time.monotonic() - t0, 10)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.marker(old), 'old')
        self.assertIn('종료되지 않아', self.read_result())
        self.assertEqual(self.opened_paths(), [])     # 앱이 아직 켜져 있으니 열지 않는다


if __name__ == '__main__':
    unittest.main()
