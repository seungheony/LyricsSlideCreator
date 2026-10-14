import sys
import traceback

# --- 전역 예외 처리기 ---
# Qt의 치명적 오류(SIGABRT)가 발생하기 전, 파이썬 예외를 포착하여 콘솔에 출력합니다.
def global_exception_hook(exctype, value, tb):
    error_msg = "".join(traceback.format_exception(exctype, value, tb))
    print(f"--- UNCAUGHT EXCEPTION ---\n{error_msg}")
    # 종료하지 않는다: 슬롯 예외로 sys.exit를 부르면 QML 핸들러 실행 중 abort로 죽는다

sys.excepthook = global_exception_hook
# --- 전역 예외 처리기 끝 ---

# 운영체제 인증서 저장소를 쓴다: 회사·학교 보안 프로그램이 끼워 넣은 인증서도 믿어서 멜론 연결이 되게 한다.
# 실패하면 requests가 기본으로 쓰는 certifi 인증서로 그대로 동작한다
try:
    import truststore
    truststore.inject_into_ssl()
except Exception:
    pass

from src.qml_ui.app import main  # noqa: E402

if __name__ == "__main__":
    main()
