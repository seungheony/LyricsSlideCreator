import sys
import os
import traceback


def global_exception_hook(exctype, value, tb):
    error_msg = "".join(traceback.format_exception(exctype, value, tb))
    print(f"--- UNCAUGHT EXCEPTION ---\n{error_msg}")
    sys.exit(1)

sys.excepthook = global_exception_hook

# src 폴더를 모듈 검색 경로에 추가합니다.
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

from src.qml_ui.app import main

if __name__ == "__main__":
    main()
