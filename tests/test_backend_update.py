import json
import os
import threading
import time
import unittest
from unittest import mock

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from src.qml_ui.backend import AlbumArtProvider, Backend  # noqa: E402
from src.utils import updater  # noqa: E402

INFO = {'version': '1.2.1', 'notes': '## 바뀐 점\n- 취소 버튼', 'page': 'https://example/r', 'name': 'x-macOS.zip',
        'url': 'u', 'size': 1, 'sums_url': 's'}


class UpdateFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtCore import QCoreApplication
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        with mock.patch('src.qml_ui.backend.updater.take_last_result', return_value=None):
            self.backend = Backend(AlbumArtProvider())
        self.addCleanup(setattr, updater, '_launched', False)
        self.events = []
        for name in ('updateFailed', 'updateCancelled', 'updateReady', 'updateChecked', 'updateAvailable'):
            getattr(self.backend, name).connect(lambda *a, n=name: self.events.append((n, *a)))
        self.backend._update = dict(INFO)
        # 실제 임시 폴더를 지우지 않게 한다
        p = mock.patch('src.qml_ui.backend.shutil.rmtree')
        self.rmtree = p.start()
        self.addCleanup(p.stop)

    def finish(self):
        self.backend._update_thread.join(5)
        self.assertFalse(self.backend._update_thread.is_alive())
        self.app.processEvents()

    def names(self):
        return [e[0] for e in self.events]

    def test_cannot_install_stops_before_download(self):
        with mock.patch.object(updater, 'can_install', side_effect=updater.UpdateError('권한 없음', '앱 위치: /x')), \
                mock.patch.object(updater, 'download') as download:
            self.backend.startUpdate()
            self.finish()
        download.assert_not_called()
        self.assertEqual(self.events, [('updateFailed', json.dumps({'message': '권한 없음', 'detail': '앱 위치: /x'},
                                                                    ensure_ascii=False))])

    def test_unexpected_error_has_detail(self):
        with mock.patch.object(updater, 'can_install'), \
                mock.patch.object(updater, 'download', side_effect=RuntimeError('boom')):
            self.backend.startUpdate()
            self.finish()
        payload = json.loads(self.events[0][1])
        self.assertIn('릴리스 페이지', payload['message'])
        self.assertIn('RuntimeError: boom', payload['detail'])

    def test_cancel_button(self):
        started = threading.Event()

        def download(info, progress, cancel):
            started.set()
            cancel.wait(5)
            raise updater.UpdateCancelled()
        with mock.patch.object(updater, 'can_install'), \
                mock.patch.object(updater, 'download', side_effect=download), \
                mock.patch.object(updater, 'install') as install:
            self.backend.startUpdate()
            started.wait(5)
            self.backend.cancelUpdate()
            self.finish()
        install.assert_not_called()
        self.assertEqual(self.names(), ['updateCancelled'])

    def test_success_and_retry_gets_fresh_cancel(self):
        with mock.patch.object(updater, 'can_install'), \
                mock.patch.object(updater, 'download', return_value='/tmp/x.zip'), \
                mock.patch.object(updater, 'install') as install:
            self.backend.cancelUpdate()          # 이전에 취소했어도 다시 시도하면 새로 시작한다
            self.backend.startUpdate()
            self.finish()
        path, from_v, to_v, cancel = install.call_args[0]
        self.assertEqual((path, to_v), ('/tmp/x.zip', '1.2.1'))
        self.assertFalse(cancel.is_set())
        self.assertEqual(self.names(), ['updateReady'])

    def test_quit_during_download_cancels_and_cleans(self):
        started = threading.Event()

        def download(info, progress, cancel):
            started.set()
            cancel.wait(5)
            raise updater.UpdateCancelled()
        with mock.patch.object(updater, 'can_install'), \
                mock.patch.object(updater, 'download', side_effect=download), \
                mock.patch.object(updater, 'install') as install:
            self.backend.startUpdate()
            started.wait(5)
            t0 = time.monotonic()
            self.backend.shutdown()
            self.assertLess(time.monotonic() - t0, 2)
        install.assert_not_called()
        self.assertFalse(self.backend._update_thread.is_alive())

    def test_quit_with_stuck_download_removes_folder(self):
        release = threading.Event()

        def stuck(*args):
            release.wait(10)                      # 응답 없는 연결: 취소 확인까지 가지 못한다
            raise updater.UpdateCancelled()
        with mock.patch.object(updater, 'can_install'), \
                mock.patch.object(updater, 'download', side_effect=stuck):
            self.backend.startUpdate()
            time.sleep(0.05)
            self.backend.shutdown()               # 연결이 멈춰 있어도 2초만 기다리고 직접 지운다
            self.rmtree.assert_called_once_with(updater.UPDATE_DIR, ignore_errors=True)
            release.set()
            self.finish()

    def test_quit_after_install_started_keeps_files(self):
        updater._launched = True
        with mock.patch.object(threading.Thread, 'is_alive', return_value=True):
            self.backend._update_thread = threading.Thread(target=lambda: None)
            self.backend.shutdown()
        self.rmtree.assert_not_called()

    def test_shutdown_waits_for_ppt_only(self):
        net_release = threading.Event()
        self.addCleanup(net_release.set)
        saved = []
        self.backend._pool.submit(lambda: net_release.wait(10))
        self.backend._ppt_pool.submit(lambda: (time.sleep(0.3), saved.append(True)))
        t0 = time.monotonic()
        self.backend.shutdown()
        self.assertEqual(saved, [True])
        self.assertLess(time.monotonic() - t0, 3)


class ManualCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtCore import QCoreApplication
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        with mock.patch('src.qml_ui.backend.updater.take_last_result', return_value=None):
            self.backend = Backend(AlbumArtProvider())
        self.backend._pool.shutdown(wait=False)
        self.backend._pool = type('SyncPool', (), {'submit': lambda self, fn: fn()})()
        self.events = []
        self.backend.updateChecked.connect(lambda j: self.events.append(('checked', json.loads(j))))
        self.backend.updateAvailable.connect(lambda j: self.events.append(('available', json.loads(j))))

    def check(self, manual, version='1.2.0', **find):
        with mock.patch('src.qml_ui.backend.get_version', return_value=version), \
                mock.patch.object(updater, 'find_update', **find):
            self.backend.checkForUpdate(manual)

    def test_dev_mode(self):
        self.check(True, version='TEST', return_value=None)
        self.check(False, version='TEST', return_value=None)
        self.assertEqual([e[1]['status'] for e in self.events], ['dev'])

    def test_latest_and_error_only_when_manual(self):
        self.check(False, return_value=None)
        self.check(False, side_effect=OSError('offline'))
        self.assertEqual(self.events, [])
        self.check(True, return_value=None)
        self.check(True, side_effect=OSError('offline'))
        self.assertEqual([e[1]['status'] for e in self.events], ['latest', 'error'])

    def test_available_has_clean_notes(self):
        self.check(True, return_value=dict(INFO))
        kind, payload = self.events[0]
        self.assertEqual(kind, 'available')
        self.assertEqual(payload, {'version': '1.2.1', 'notes': '<ul><li>취소 버튼</li></ul>',
                                   'page': 'https://example/r', 'manual': True})


if __name__ == '__main__':
    unittest.main()
