import sys
import os
import traceback

# --- 전역 예외 처리기 ---
# Qt의 치명적 오류(SIGABRT)가 발생하기 전, 파이썬 예외를 포착하여 로그로 남깁니다.
def global_exception_hook(exctype, value, tb):
    """
    모든 처리되지 않은 예외를 잡아 파일에 기록하거나 콘솔에 출력합니다.
    """
    error_msg = "".join(traceback.format_exception(exctype, value, tb))
    print(f"--- UNCAUGHT EXCEPTION ---\n{error_msg}")
    # 여기에 파일로 저장하는 로직을 추가할 수도 있습니다.
    # with open("crash_log.txt", "a") as f:
    #     f.write(f"{error_msg}\n")
    sys.exit(1)

sys.excepthook = global_exception_hook
# --- 전역 예외 처리기 끝 ---


# src 폴더를 모듈 검색 경로에 추가합니다.
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

from src.qml_ui.app import main

if __name__ == "__main__":
    main()