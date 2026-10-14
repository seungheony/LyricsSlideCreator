"""GitHub 릴리스 기반 업데이트.

1. find_update(): 지금 버전보다 새 릴리스가 있는지 확인
2. download(): 설치 파일을 임시 폴더에 받고 SHA256SUMS.txt 로 검증
3. install(): 설치를 시작한다. 호출한 뒤 앱은 바로 종료해야 한다.
   - Windows: 새 설치 파일을 조용히(/VERYSILENT) 실행 → 설치가 끝나면 앱이 다시 켜진다
   - macOS:   앱이 종료되면 .app 을 새것으로 바꾸고 다시 여는 스크립트를 실행

릴리스에 올라가야 하는 파일 (GitHub Actions가 만든다):
    LyricsSlideCreator-<버전>-Setup.exe, LyricsSlideCreator-<버전>-macOS.zip, SHA256SUMS.txt
"""
import glob
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tempfile

import requests

from src.utils.version import is_newer, parse_version

REPO = 'seungheony/lyricsSlide_Creator'
# LSC_UPDATE_API: 업데이트 기능을 실제 릴리스 없이 시험할 때 다른 주소(로컬 서버 등)를 쓰기 위한 환경변수
RELEASES_API = os.environ.get('LSC_UPDATE_API') or f'https://api.github.com/repos/{REPO}/releases?per_page=20'
RELEASES_PAGE = f'https://github.com/{REPO}/releases'
# 다운로드 임시 폴더. 다음 실행 때 지우고, Windows 제거 프로그램도 지운다 (installer/windows.iss)
UPDATE_DIR = os.path.join(tempfile.gettempdir(), 'LyricsSlideCreator-update')
SUMS_NAME = 'SHA256SUMS.txt'


class UpdateError(Exception):
    """사용자에게 그대로 보여줄 수 있는 업데이트 실패 사유"""


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


def download(info, progress=None):
    """설치 파일을 받아 체크섬을 확인하고 경로를 돌려준다. progress(받은 바이트, 전체 바이트)"""
    shutil.rmtree(UPDATE_DIR, ignore_errors=True)
    os.makedirs(UPDATE_DIR, exist_ok=True)

    try:
        sums = requests.get(info['sums_url'], timeout=15)
        sums.raise_for_status()
    except requests.RequestException as e:
        raise UpdateError(f'체크섬 파일을 받지 못했어요.\n{e}')
    expected = None
    for line in sums.text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip('*') == info['name']:
            expected = parts[0].lower()
    if not expected:
        raise UpdateError('체크섬 파일에 설치 파일 정보가 없어요.')

    path = os.path.join(UPDATE_DIR, info['name'])
    digest = hashlib.sha256()
    try:
        with requests.get(info['url'], stream=True, timeout=30) as resp:
            resp.raise_for_status()
            total = int(resp.headers.get('Content-Length') or info.get('size') or 0)
            done = 0
            with open(path, 'wb') as f:
                for chunk in resp.iter_content(chunk_size=256 * 1024):
                    f.write(chunk)
                    digest.update(chunk)
                    done += len(chunk)
                    if progress:
                        progress(done, total)
    except requests.RequestException as e:
        raise UpdateError(f'다운로드 중 연결이 끊겼어요.\n{e}')

    if digest.hexdigest() != expected:
        shutil.rmtree(UPDATE_DIR, ignore_errors=True)
        raise UpdateError('받은 파일이 손상되었거나 릴리스 파일과 다릅니다. 다시 시도해주세요.')
    return path


def current_app_bundle():
    """macOS에서 실행 중인 .app 경로. 빌드된 앱이 아니면 None."""
    path = os.path.abspath(sys.argv[0])
    while path != os.path.dirname(path):
        if path.endswith('.app'):
            return path
        path = os.path.dirname(path)
    return None


def install(package_path):
    """설치를 시작한다. 성공적으로 시작되면 호출한 쪽은 앱을 즉시 종료해야 한다."""
    system = platform.system()
    if system == 'Windows':
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
        subprocess.Popen([package_path, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
                         creationflags=flags, close_fds=True)
    elif system == 'Darwin':
        _install_macos(package_path)
    else:
        raise UpdateError('이 OS에서는 자동 업데이트를 지원하지 않아요.')


def _install_macos(zip_path):
    app = current_app_bundle()
    if not app:
        raise UpdateError('빌드된 앱에서만 업데이트할 수 있어요.')
    if '/AppTranslocation/' in app:
        # 다운로드한 앱을 옮기지 않고 바로 실행하면 macOS가 읽기 전용 임시 위치에서 실행한다
        raise UpdateError('앱을 "응용 프로그램" 폴더로 옮긴 뒤 다시 실행하면 업데이트할 수 있어요.')
    if not os.access(os.path.dirname(app), os.W_OK):
        raise UpdateError(f'앱이 있는 폴더에 쓸 권한이 없어요.\n{os.path.dirname(app)}')

    extract_dir = os.path.join(UPDATE_DIR, 'extracted')
    shutil.rmtree(extract_dir, ignore_errors=True)
    subprocess.run(['ditto', '-x', '-k', zip_path, extract_dir], check=True)
    apps = glob.glob(os.path.join(extract_dir, '*.app'))
    if not apps:
        raise UpdateError('받은 파일에 앱이 들어 있지 않아요.')

    # 앱이 완전히 종료된 뒤 교체하고 다시 연다. 끝나면 임시 폴더도 지운다.
    script = os.path.join(UPDATE_DIR, 'apply.sh')
    with open(script, 'w') as f:
        f.write(f'''#!/bin/bash
while kill -0 {os.getpid()} 2>/dev/null; do sleep 0.2; done
rm -rf "{app}" && mv "{apps[0]}" "{app}"
open "{app}"
rm -rf "{UPDATE_DIR}"
''')
    subprocess.Popen(['/bin/bash', script], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cleanup():
    """지난 업데이트에서 남은 임시 파일을 지운다 (앱 시작 시 호출)."""
    shutil.rmtree(UPDATE_DIR, ignore_errors=True)
