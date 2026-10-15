"""앱 데이터 폴더: 앱 상태(튜토리얼을 봤는지, 창 크기·위치)와 저장한 프리셋(src/utils/presets.py).

앱 폴더 안에 두면 업데이트할 때 앱 폴더를 새로 깔면서 지워지므로(Windows) 사용자 데이터 폴더에 둔다.
- Windows: %APPDATA%\\LyricsSlideCreator (제거하면 installer/windows.iss가 지운다)
- macOS: ~/Library/Application Support/LyricsSlideCreator
- 개발 모드: 프로젝트 안 user_data/ (실제 앱의 기록과 섞이지 않게). LSC_DATA_DIR 환경변수로 바꿀 수 있다(시험)
- 쓸 수 없으면 조용히 넘어간다 (Backend가 시작할 때 한 번 읽어 메모리에 두므로 그 실행 동안은 유지된다)

v1.3.0까지 macOS 앱은 튜토리얼 기록을 환경설정 plist(~/Library/Preferences/<번들 ID>.plist)에 썼다.
처음 실행할 때 데이터 폴더로 옮기고 plist의 키는 지운다(migrate_plist).
"""
import json
import os
import plistlib
import subprocess
import sys

from src.utils.helpers import resource_path

APP_DIR_NAME = 'LyricsSlideCreator'
BUNDLE_ID = 'io.github.seungheony.lyricsslidecreator'   # scripts/build.py의 BUNDLE_ID와 같아야 한다
PLIST_KEYS = ('tutorials_seen',)                          # 예전에 plist에 저장하던 값 (문자열 목록)


def is_built():
    """Nuitka로 빌드한 앱인지 (개발 모드는 프로젝트 안 user_data/를 쓴다)"""
    return '__compiled__' in globals()


def data_dir():
    override = os.environ.get('LSC_DATA_DIR')
    if override:
        return override
    if not is_built():
        return resource_path('user_data')
    home = os.path.expanduser('~')
    if sys.platform == 'win32':
        base = os.environ.get('APPDATA') or os.path.join(home, 'AppData', 'Roaming')
    elif sys.platform == 'darwin':
        base = os.path.join(home, 'Library', 'Application Support')
    else:
        base = os.environ.get('XDG_DATA_HOME') or os.path.join(home, '.local', 'share')
    return os.path.join(base, APP_DIR_NAME)


def data_path(name):
    return os.path.join(data_dir(), name)


def read_json(path):
    """JSON 객체를 읽는다. 없거나 깨졌으면 빈 객체"""
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, data):
    """임시 파일에 쓰고 바꿔 넣는다 (쓰다가 꺼져도 이전 파일이 깨지지 않게). 반환: 성공 여부"""
    tmp = path + '.tmp'
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
        return True
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return False


def load():
    path = data_path('state.json')
    if not os.path.exists(path) and sys.platform == 'darwin' and is_built():
        migrated = migrate_plist(BUNDLE_ID)
        if migrated:
            return migrated
    return read_json(path)


def save(data):
    write_json(data_path('state.json'), data)


def migrate_plist(domain):
    """예전 macOS 앱이 plist에 남긴 튜토리얼 기록을 데이터 폴더로 옮긴다. 반환: 옮긴 상태 (없으면 빈 객체)"""
    try:
        out = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, timeout=5, check=True).stdout
        info = plistlib.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}
    data = {k: v for k, v in info.items() if k in PLIST_KEYS and isinstance(v, list)}
    if data and write_json(data_path('state.json'), data):
        # 도메인 전체를 지우면 파일 대화상자 기록 등 다른 값도 지워지므로 키별로 지운다
        for key in data:
            subprocess.run(['defaults', 'delete', domain, key], capture_output=True, timeout=5)
    return data
