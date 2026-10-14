import os


def resource_path(relative_path):
    """프로젝트 루트(개발 모드·Nuitka 빌드) 기준 경로"""
    # 이 파일(src/utils/helpers.py) 기준으로 프로젝트 루트를 찾는다
    base_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(base_path, relative_path)
