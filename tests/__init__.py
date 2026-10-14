"""테스트 공통 준비: 화면 없이(offscreen) 돌리고, Qt 글꼴·JS 엔진을 쓰려고 앱 객체를 하나 만든다."""
import os

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from PySide6.QtGui import QGuiApplication  # noqa: E402

app = QGuiApplication.instance() or QGuiApplication([])
