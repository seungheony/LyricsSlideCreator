import sys
import os

def resource_path(relative_path):
    """ Get absolute path to resource, works for dev, PyInstaller and Nuitka """
    if hasattr(sys, '_MEIPASS'):
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    else:
        # 개발 환경과 Nuitka 빌드: 이 파일(src/utils/helpers.py) 기준으로 프로젝트 루트를 찾는다
        base_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    return os.path.join(base_path, relative_path)
