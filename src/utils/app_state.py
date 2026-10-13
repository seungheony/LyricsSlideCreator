"""앱 상태 기록 (첫 실행 튜토리얼을 봤는지 등).

앱 폴더 밖에 파일을 남기지 않는다는 원칙에 따라 앱 폴더 안의 app_state.json에 저장한다.
- 업데이트하면 앱 폴더가 새로 깔리므로 기록도 처음으로 돌아간다
- 쓸 수 없는 위치(macOS에서 다운로드 폴더에 둔 채 실행해 읽기 전용으로 옮겨진 경우 등)면 조용히 넘어간다
- Windows는 제거할 때 설치 폴더를 통째로 지우므로(installer/windows.iss) 남지 않는다
"""
import json

from src.utils.helpers import resource_path

STATE_FILE = resource_path('app_state.json')


def load():
    try:
        with open(STATE_FILE, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data):
    try:
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
    except OSError:
        pass
