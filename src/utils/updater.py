"""GitHub 릴리스 기반 업데이트.

1. find_update(): 지금 버전보다 새 릴리스가 있는지 확인
2. can_install(): 이 위치에서 설치할 수 있는지 다운로드 전에 확인 (macOS 앱 위치·권한)
3. download(): 설치 파일을 임시 폴더에 받고 SHA256SUMS.txt 로 검증 (cancel 이벤트로 취소)
4. install(): 설치를 시작한다. 호출한 뒤 앱은 바로 종료해야 한다.
   - Windows: 새 설치 파일을 /SILENT 로 실행(진행 창만 보임) → 설치가 끝나면 앱이 다시 켜진다
   - macOS:   앱이 종료되면 .app 을 새것으로 바꾸고 다시 여는 스크립트(APPLY_SH)를 실행
5. take_last_result(): 다음 실행 때 지난 업데이트가 됐는지 확인하고 임시 폴더를 지운다

릴리스에 올라가야 하는 파일 (GitHub Actions가 만든다):
    LyricsSlideCreator-<버전>-Setup.exe, LyricsSlideCreator-<버전>-macOS.zip, SHA256SUMS.txt
"""
import errno
import glob
import hashlib
import html
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import threading

import requests

from src.utils.version import is_newer, parse_version

REPO = 'seungheony/LyricsSlideCreator'
# LSC_UPDATE_API: 업데이트 기능을 실제 릴리스 없이 시험할 때 다른 주소(로컬 서버 등)를 쓰기 위한 환경변수
RELEASES_API = os.environ.get('LSC_UPDATE_API') or f'https://api.github.com/repos/{REPO}/releases?per_page=20'
RELEASES_PAGE = f'https://github.com/{REPO}/releases'
# 다운로드 임시 폴더. 다음 실행 때 지우고, Windows 제거 프로그램도 지운다 (installer/windows.iss)
UPDATE_DIR = os.path.join(tempfile.gettempdir(), 'LyricsSlideCreator-update')
SUMS_NAME = 'SHA256SUMS.txt'
# 설치를 시작할 때 남기는 기록 {from, to}. 다음 실행 때 버전을 비교해 업데이트가 됐는지 안다
PENDING_NAME = 'pending.json'
# macOS 교체 스크립트가 실패 사유를 남기는 파일
RESULT_NAME = 'result.txt'
# Windows 설치 기록 (/LOG). 업데이트가 안 됐을 때 '자세히'에 끝부분을 보여 준다
LOG_NAME = 'install.log'
# Windows: 실행 중인 앱 표시. installer/windows.iss 의 AppMutex 와 같아야 한다
APP_MUTEX = 'LyricsSlideCreator.AppMutex'
# macOS: 영문 이름 시절의 앱. 업데이트할 때 새 이름(가사 슬라이드 생성기.app)으로 옮긴다
LEGACY_APP_NAMES = ('Lyrics Slide Creator.app',)
# macOS: 앱이 종료되기를 기다리는 최대 시간(초). 넘으면 교체하지 않는다
APP_EXIT_WAIT = 60


class UpdateError(Exception):
    """사용자에게 보여줄 업데이트 실패 사유. detail은 '자세히'에 접어 두는 기술 원문"""

    def __init__(self, message, detail=''):
        super().__init__(message)
        self.detail = detail


class UpdateCancelled(Exception):
    """사용자가 취소했거나 앱이 닫히는 중"""


def _asset_suffix():
    system = platform.system()
    if system == 'Windows':
        return '-Setup.exe'
    if system == 'Darwin':
        return '-macOS.zip'
    return None


def find_update(current_version):
    """새 버전 정보를 돌려준다. 없거나 개발 모드(TEST)면 None.

    정식 버전 사용자에게는 정식 릴리스만, 베타 사용자에게는 베타 릴리스도 알린다.
    """
    current = parse_version(current_version)
    suffix = _asset_suffix()
    if current is None or suffix is None:
        return None
    include_prerelease = current[3] == 0

    resp = requests.get(RELEASES_API, timeout=8, headers={'Accept': 'application/vnd.github+json'})
    resp.raise_for_status()

    best = None
    for rel in resp.json():
        if rel.get('draft') or (rel.get('prerelease') and not include_prerelease):
            continue
        tag = rel.get('tag_name', '')
        if parse_version(tag) is None or not is_newer(tag, current_version):
            continue
        assets = {a['name']: a for a in rel.get('assets', [])}
        package = next((a for name, a in assets.items() if name.endswith(suffix)), None)
        if not package or SUMS_NAME not in assets:
            continue
        if best is None or parse_version(tag) > parse_version(best['version']):
            best = {
                'version': tag.lstrip('v'),
                'notes': rel.get('body') or '',
                'page': rel.get('html_url') or RELEASES_PAGE,
                'name': package['name'],
                'url': package['browser_download_url'],
                'size': package.get('size', 0),
                'sums_url': assets[SUMS_NAME]['browser_download_url'],
            }
    return best


# ── 릴리스 노트 ──
_CONVENTIONAL = r'(?:feat|fix|docs|chore|refactor|test|perf|style|build|ci|revert)(?:\([^)]*\))?!?:\s*'


def release_notes(body):
    """릴리스 노트에서 사용자에게 보여 줄 부분(마크다운).

    '## 바뀐 점' 섹션이 있으면 그것만. 없으면 GitHub 자동 노트에서 코드 서명 정책 링크, 기여자·PR 주소('by @… in URL'),
    'Full Changelog', 새 기여자 섹션, 커밋 접두어(feat:, fix: …)를 걷어 낸다.
    """
    text = (body or '').replace('\r\n', '\n')
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    # 릴리스 페이지에 붙이는 코드 서명 정책 링크(release.yml)는 앱에 보여 주지 않는다
    text = re.sub(r'^\[Code signing policy\]\([^)]*\)[ \t]*$', '', text, flags=re.M)
    m = re.search(r'^#{1,3}\s*바뀐\s*점\s*$', text, re.M)
    if m:
        rest = text[m.end():]
        end = re.search(r'^#{1,3}\s', rest, re.M)
        return (rest[:end.start()] if end else rest).strip()

    out = []
    skipping = False
    for line in text.split('\n'):
        heading = re.match(r'^#{1,6}\s*(.*?)\s*$', line)
        if heading:
            skipping = heading.group(1).lower() == 'new contributors'
            if skipping or heading.group(1).lower() == "what's changed":
                continue
        if skipping or 'Full Changelog' in line:
            continue
        line = re.sub(r'\s+by @[\w.-]+(?:\[bot\])?(?:\s+in\s+https?://\S+)?\s*$', '', line)
        line = re.sub(r'\s+in\s+https?://github\.com/\S+/pull/\d+\s*$', '', line)
        line = re.sub(r'^(\s*[*-]\s+)' + _CONVENTIONAL, r'\1', line)
        line = re.sub(r'^' + _CONVENTIONAL, '', line)
        out.append(line)
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(out)).strip()


def _inline_html(text):
    """한 줄의 마크다운 강조·링크를 Qt StyledText HTML로"""
    links = []

    def link(url, label):
        links.append(f'<a href="{html.escape(url, quote=True)}">{html.escape(label)}</a>')
        return f'\x00{len(links) - 1}\x00'
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)\s]+)\)', lambda m: link(m.group(2), m.group(1)), text)
    text = re.sub(r'(?<![\w/])https?://[^\s<>()]+', lambda m: link(m.group(0), m.group(0)), text)
    text = html.escape(text, quote=False)
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'`([^`]+)`', r'\1', text)
    return re.sub(r'\x00(\d+)\x00', lambda m: links[int(m.group(1))], text)


def notes_html(markdown):
    """release_notes() 결과를 Qt StyledText HTML로 바꾼다.

    QML Text의 MarkdownText는 linkColor를 무시해 다크 모드에서 링크가 진한 파랑으로 보이므로,
    linkColor가 적용되는 StyledText로 보여 준다. 제목·목록·굵게·링크만 다룬다.
    """
    parts = []
    in_list = False
    for raw in markdown.split('\n'):
        line = raw.strip()
        item = re.match(r'^[*-]\s+(.*)$', line)
        if in_list and not item:
            parts.append('</ul>')
            in_list = False
        if not line:
            continue
        heading = re.match(r'^#{1,6}\s*(.*)$', line)
        if item:
            if not in_list:
                parts.append('<ul>')
                in_list = True
            parts.append(f'<li>{_inline_html(item.group(1))}</li>')
        elif heading:
            parts.append(f'<p><b>{_inline_html(heading.group(1))}</b></p>')
        else:
            parts.append(f'<p>{_inline_html(line)}</p>')
    if in_list:
        parts.append('</ul>')
    return ''.join(parts)


# ── 다운로드 ──
def _check_cancel(cancel):
    if cancel is not None and cancel.is_set():
        raise UpdateCancelled()


def _disk_error(e, path):
    """임시 폴더에 쓰지 못한 원인별 안내"""
    detail = f'경로: {path}\n{type(e).__name__}: {e}'
    if getattr(e, 'errno', None) in (errno.ENOSPC, getattr(errno, 'EDQUOT', errno.ENOSPC)):
        return UpdateError('저장 공간이 부족해서 업데이트 파일을 받지 못했어요.\n디스크 공간을 확보한 뒤 다시 시도해 주세요.', detail)
    return UpdateError('업데이트 파일을 임시 폴더에 저장하지 못했어요.\n잠시 뒤에 다시 시도해 주세요.', detail)


def download(info, progress=None, cancel=None):
    """설치 파일을 받아 체크섬을 확인하고 경로를 돌려준다. progress(받은 바이트, 전체 바이트)

    cancel(threading.Event)이 설정되면 받던 파일을 지우고 UpdateCancelled를 낸다.
    """
    shutil.rmtree(UPDATE_DIR, ignore_errors=True)
    try:
        return _download(info, progress, cancel)
    except BaseException:
        # 취소·실패 모두 받던 파일을 남기지 않는다
        shutil.rmtree(UPDATE_DIR, ignore_errors=True)
        raise


def _download(info, progress, cancel):
    try:
        os.makedirs(UPDATE_DIR, exist_ok=True)
    except OSError as e:
        raise _disk_error(e, UPDATE_DIR)

    try:
        sums = requests.get(info['sums_url'], timeout=15)
        sums.raise_for_status()
    except requests.RequestException as e:
        raise UpdateError('업데이트 정보를 받지 못했어요.\n인터넷 연결을 확인하고 다시 시도해 주세요.',
                          f'{info["sums_url"]}\n{e}')
    expected = None
    for line in sums.text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip('*') == info['name']:
            expected = parts[0].lower()
    if not expected:
        raise UpdateError('릴리스에 설치 파일 확인 정보가 없어요.\n릴리스 페이지에서 직접 받아 설치해 주세요.',
                          f'{SUMS_NAME}에 {info["name"]} 항목이 없음')
    _check_cancel(cancel)

    path = os.path.join(UPDATE_DIR, info['name'])
    digest = hashlib.sha256()
    try:
        with requests.get(info['url'], stream=True, timeout=30) as resp:
            resp.raise_for_status()
            total = int(resp.headers.get('Content-Length') or info.get('size') or 0)
            done = 0
            with open(path, 'wb') as f:
                for chunk in resp.iter_content(chunk_size=256 * 1024):
                    _check_cancel(cancel)
                    f.write(chunk)
                    digest.update(chunk)
                    done += len(chunk)
                    if progress:
                        progress(done, total)
    except requests.RequestException as e:   # OSError의 하위 클래스라 먼저 잡는다
        raise UpdateError('다운로드 중 연결이 끊겼어요.\n인터넷 연결을 확인하고 다시 시도해 주세요.', f'{info["url"]}\n{e}')
    except OSError as e:
        raise _disk_error(e, path)
    _check_cancel(cancel)

    if digest.hexdigest() != expected:
        raise UpdateError('받은 파일이 손상되었거나 릴리스 파일과 달라요.\n다시 시도해 주세요.',
                          f'기대한 SHA256: {expected}\n받은 파일 SHA256: {digest.hexdigest()}')
    return path


# ── 설치 ──
def current_app_bundle():
    """macOS에서 실행 중인 .app 경로. 빌드된 앱이 아니면 None."""
    path = os.path.abspath(sys.argv[0])
    while path != os.path.dirname(path):
        if path.endswith('.app'):
            return path
        path = os.path.dirname(path)
    return None


def _macos_app():
    """교체할 수 있는 지금 앱(.app) 경로. 안 되면 UpdateError"""
    app = current_app_bundle()
    if not app:
        raise UpdateError('빌드된 앱에서만 업데이트할 수 있어요.')
    if '/AppTranslocation/' in app:
        # 다운로드한 앱을 옮기지 않고 바로 실행하면 macOS가 읽기 전용 임시 위치에서 실행한다
        raise UpdateError('앱을 "응용 프로그램" 폴더로 옮긴 뒤 다시 실행하면 업데이트할 수 있어요.', f'실행 위치: {app}')
    folder = os.path.dirname(app)
    if not os.access(folder, os.W_OK) or not os.access(app, os.W_OK):
        raise UpdateError('앱이 있는 폴더에 쓸 권한이 없어서 업데이트할 수 없어요.\n'
                          '릴리스 페이지에서 새 버전을 받아 직접 설치해 주세요.', f'앱 위치: {app}')
    return app


def can_install():
    """이 컴퓨터·위치에서 자동 업데이트를 할 수 있는지 다운로드 전에 확인한다. 안 되면 UpdateError"""
    system = platform.system()
    if system == 'Darwin':
        _macos_app()
    elif system != 'Windows':
        raise UpdateError('이 OS에서는 자동 업데이트를 지원하지 않아요.')


# 설치 시작과 취소가 엇갈리지 않게 한다: 취소가 먼저면 설치하지 않고, 설치가 먼저면 취소는 아무것도 지우지 않는다
_launch_lock = threading.Lock()
_launched = False


def cancel(event):
    """진행 중인 다운로드·설치 준비를 멈추게 한다. 이미 설치를 시작했으면 False (임시 폴더를 지우면 안 됨)"""
    with _launch_lock:
        event.set()
        return not _launched


def _launch(cancel_event, start):
    global _launched
    with _launch_lock:
        _check_cancel(cancel_event)
        start()
        _launched = True


def _write_pending(from_version, to_version):
    try:
        with open(os.path.join(UPDATE_DIR, PENDING_NAME), 'w', encoding='utf-8') as f:
            json.dump({'from': from_version, 'to': to_version}, f)
    except OSError as e:
        raise _disk_error(e, UPDATE_DIR)


def install(package_path, from_version, to_version, cancel=None):
    """설치를 시작한다. 성공적으로 시작되면 호출한 쪽은 앱을 즉시 종료해야 한다.

    cancel이 설정돼 있으면(앱이 닫히는 중 등) 시작하지 않고 UpdateCancelled를 낸다.
    """
    system = platform.system()
    if system == 'Windows':
        _install_windows(package_path, from_version, to_version, cancel)
    elif system == 'Darwin':
        _install_macos(package_path, from_version, to_version, cancel)
    else:
        raise UpdateError('이 OS에서는 자동 업데이트를 지원하지 않아요.')


def _install_windows(setup_path, from_version, to_version, cancel_event):
    # /SILENT: 묻는 화면 없이 진행 창만 보인다 (설치가 멈추거나 실패해도 사용자가 알 수 있게).
    # /SUPPRESSMSGBOXES: 확인 창은 기본 답으로 넘어간다. /LOG: 실패 원인을 다음 실행 때 '자세히'로 보여 준다
    args = [setup_path, '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS',
            f'/LOG={os.path.join(UPDATE_DIR, LOG_NAME)}']

    def start():
        _write_pending(from_version, to_version)
        # 설치 프로그램은 이 뮤텍스가 있으면 앱이 실행 중이라고 보고 멈춘다(AppMutex). 앱은 곧 종료되므로 먼저 놓는다
        release_app_mutex()
        try:
            flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
            subprocess.Popen(args, creationflags=flags, close_fds=True)
        except OSError as e:
            hold_app_mutex()
            raise UpdateError('설치 프로그램을 실행하지 못했어요.\n백신 프로그램이 막았는지 확인하거나, 릴리스 페이지에서 직접 받아 설치해 주세요.',
                              f'{setup_path}\n{type(e).__name__}: {e}')
    _launch(cancel_event, start)


# 앱이 완전히 종료된 뒤 .app 을 새것으로 바꾸고 다시 연다.
# 경로는 스크립트에 끼워 넣지 않고 인자로 넘긴다 (경로에 따옴표·$ 등이 있어도 안전).
# 지금 앱을 숨긴 백업 이름으로 옮기고 → 새 앱을 옮긴 뒤 → 실행 파일·서명을 확인해 성공하면 백업을 지우고,
# 실패하면 되돌린다. 실패 사유는 결과 파일에 남겨 다음 실행 때 알린다.
APPLY_SH = r'''#!/bin/bash
# 인자: 1 앱 PID, 2 새 앱, 3 지금 앱, 4 새 앱을 둘 경로(보통 3과 같고, 예전 이름이면 새 이름), 5 결과 파일, 6 종료를 기다릴 최대 초
pid=$1; new=$2; old=$3; dest=$4; result=$5; wait=${6:-60}
backup="$(dirname "$old")/.$(basename "$old").update-backup"

# 실패: 사유를 남기고, 지금 자리에 있는 앱을 다시 연다
give_up() {
    printf '%s\n' "$1" > "$result"
    [ -n "$2" ] && [ -d "$old" ] && open "$old"
    exit 1
}
# 새 앱을 치우고 백업을 제자리로
roll_back() {
    rm -rf "$dest"
    if ! mv "$backup" "$old"; then
        give_up "$1
이전 앱을 되돌리지 못했어요. 백업 위치: $backup"
    fi
    give_up "$1" reopen
}

tries=$((wait * 5))
while kill -0 "$pid" 2>/dev/null; do
    tries=$((tries - 1))
    [ "$tries" -le 0 ] && give_up "앱이 ${wait}초 안에 종료되지 않아 업데이트하지 않았어요."
    sleep 0.2
done

[ -d "$new" ] || give_up "받은 새 앱을 찾지 못했어요: $new" reopen
[ -d "$old" ] || give_up "지금 앱을 찾지 못했어요: $old"
if [ -e "$backup" ]; then
    rm -rf "$backup" || give_up "지난 업데이트의 백업을 지우지 못했어요: $backup" reopen
fi
mv "$old" "$backup" || give_up "지금 앱을 옮기지 못했어요." reopen
if [ -e "$dest" ]; then
    mv "$backup" "$old"
    give_up "같은 이름의 앱이 이미 있어요: $dest" reopen
fi
mv "$new" "$dest" || roll_back "새 앱을 옮기지 못했어요."

exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$dest/Contents/Info.plist" 2>/dev/null)
if [ -z "$exe" ] || [ ! -x "$dest/Contents/MacOS/$exe" ]; then
    roll_back "새 앱의 실행 파일이 없어요."
fi
if ! out=$(codesign --verify --deep --strict "$dest" 2>&1); then
    roll_back "새 앱의 서명을 확인하지 못했어요.
$out"
fi

open "$dest"
rm -rf "$backup"
'''


def _install_macos(zip_path, from_version, to_version, cancel_event):
    app = _macos_app()

    extract_dir = os.path.join(UPDATE_DIR, 'extracted')
    shutil.rmtree(extract_dir, ignore_errors=True)
    try:
        subprocess.run(['ditto', '-x', '-k', zip_path, extract_dir], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        raise UpdateError('받은 파일을 풀지 못했어요.\n디스크 공간을 확인하고 다시 시도해 주세요.',
                          (e.stderr or b'').decode('utf-8', 'replace') or str(e))
    except OSError as e:
        raise _disk_error(e, extract_dir)
    apps = glob.glob(os.path.join(extract_dir, '*.app'))
    if not apps:
        raise UpdateError('받은 파일에 앱이 들어 있지 않아요.', zip_path)
    new_app = apps[0]

    # 영문 이름 시절의 앱은 새 이름으로 옮긴다 (그 이름의 앱이 따로 있으면 그대로 둔다)
    dest = app
    if os.path.basename(app) in LEGACY_APP_NAMES:
        renamed = os.path.join(os.path.dirname(app), os.path.basename(new_app))
        if not os.path.exists(renamed):
            dest = renamed

    script = os.path.join(UPDATE_DIR, 'apply.sh')
    try:
        with open(script, 'w', encoding='utf-8') as f:
            f.write(APPLY_SH)
    except OSError as e:
        raise _disk_error(e, script)

    def start():
        _write_pending(from_version, to_version)
        subprocess.Popen(['/bin/bash', script, str(os.getpid()), new_app, app, dest,
                          os.path.join(UPDATE_DIR, RESULT_NAME), str(APP_EXIT_WAIT)],
                         cwd='/', start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _launch(cancel_event, start)


# ── Windows: 실행 중 표시 ──
_mutex = None


def hold_app_mutex():
    """Windows: 이름 있는 뮤텍스를 만들어 설치·제거 프로그램이 앱 실행 중임을 알게 한다 (windows.iss AppMutex)"""
    global _mutex
    if platform.system() != 'Windows' or _mutex:
        return
    try:
        import ctypes
        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.CreateMutexW.restype = ctypes.c_void_p
        kernel32.CreateMutexW.argtypes = (ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p)
        _mutex = kernel32.CreateMutexW(None, False, APP_MUTEX) or None
    except Exception:
        _mutex = None


def release_app_mutex():
    global _mutex
    if not _mutex:
        return
    try:
        import ctypes
        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.CloseHandle.argtypes = (ctypes.c_void_p,)
        kernel32.CloseHandle(_mutex)
    except Exception:
        pass
    _mutex = None


# ── 다음 실행 때 ──
def _tail(path, lines=40):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return ''.join(f.readlines()[-lines:]).strip()
    except OSError:
        return ''


def take_last_result(current_version):
    """지난 업데이트 결과를 읽고 임시 폴더를 지운다 (앱 시작 시 호출).

    업데이트를 시작한 적이 없으면 None. 있으면 {'ok': bool, 'version': 목표 버전, 'detail': 실패 원인}
    지금 버전이 목표 버전과 같으면 성공이다 (Windows 설치 실패·macOS 되돌리기 모두 이전 버전으로 다시 켜진다).
    """
    result = None
    try:
        with open(os.path.join(UPDATE_DIR, PENDING_NAME), encoding='utf-8') as f:
            pending = json.load(f)
        target = str(pending.get('to', ''))
        ok = parse_version(target) is not None and parse_version(target) == parse_version(current_version)
        detail = ''
        if not ok:
            detail = (_tail(os.path.join(UPDATE_DIR, RESULT_NAME))
                      or _tail(os.path.join(UPDATE_DIR, LOG_NAME))
                      or f'지금 버전 {current_version}, 업데이트할 버전 {target}')
        result = {'ok': ok, 'version': target, 'detail': detail}
    except (OSError, ValueError, AttributeError):
        pass
    shutil.rmtree(UPDATE_DIR, ignore_errors=True)
    return result
