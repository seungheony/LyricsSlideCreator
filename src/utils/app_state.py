"""앱 상태 기록 (첫 실행 튜토리얼을 봤는지 등).

앱 폴더 밖에 새 파일을 남기지 않는다는 원칙에 따라 저장 위치를 둘로 나눈다.
- 개발 모드·Windows: 앱 폴더 안의 app_state.json
  - 업데이트하면 앱 폴더가 새로 깔리므로 기록도 처음으로 돌아간다
  - Windows는 제거할 때 설치 폴더를 통째로 지우므로(installer/windows.iss) 남지 않는다
- macOS 빌드(.app): 앱 번들 ID의 환경설정 plist(~/Library/Preferences/<번들 ID>.plist).
  OS 파일 대화상자가 마지막 폴더를 적어 두는 것과 같은 파일이다. 번들 안에 쓰면 코드 서명이
  깨지고(다음 실행에서 "손상됨"), 앱을 다운로드 폴더 등 읽기 전용 위치에서 실행하면 저장되지도 않는다.
  쓰기는 환경설정 캐시(cfprefsd)를 거치도록 `defaults` 명령을 쓴다(파일을 직접 쓰면 덮어써질 수 있다)
- 쓸 수 없으면 조용히 넘어간다 (Backend가 시작할 때 한 번 읽어 메모리에 두므로 그 실행 동안은 유지된다)
"""
import json
import plistlib
import subprocess
import sys

from src.utils.helpers import resource_path

STATE_FILE = resource_path('app_state.json')
BUNDLE_ID = 'io.github.seungheony.lyricsslidecreator'   # scripts/build.py의 BUNDLE_ID와 같아야 한다
LIST_KEYS = ('tutorials_seen',)                          # plist에 저장하는 값 (문자열 목록)


def use_plist():
    """Nuitka로 빌드한 macOS 앱에서만 환경설정 plist를 쓴다 (개발 모드는 앱 폴더 안 파일)"""
    return sys.platform == 'darwin' and '__compiled__' in globals()


def load(domain=None):
    if domain or use_plist():
        return _load_plist(domain or BUNDLE_ID)
    try:
        with open(STATE_FILE, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data, domain=None):
    if domain or use_plist():
        _save_plist(data, domain or BUNDLE_ID)
        return
    try:
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
    except OSError:
        pass


def _load_plist(domain):
    try:
        out = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True, timeout=5, check=True).stdout
        info = plistlib.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}
    return {k: v for k, v in info.items() if k in LIST_KEYS and isinstance(v, list)}


def _save_plist(data, domain):
    # 도메인 전체를 바꾸는 `defaults import`는 대화상자 기록 등 다른 값을 지우므로 키별로 쓴다
    for key in LIST_KEYS:
        values = data.get(key)
        if not isinstance(values, list):
            continue
        try:
            subprocess.run(['defaults', 'write', domain, key, '-array', *map(str, values)],
                           capture_output=True, timeout=5, check=True)
        except (OSError, subprocess.SubprocessError):
            pass
