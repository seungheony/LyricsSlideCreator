import os
import sys

from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QFont, QFontDatabase, QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine

from src.qml_ui.backend import AlbumArtProvider, Backend
from src.utils.helpers import resource_path


def load_fonts():
    """앱에 포함된 Pretendard를 등록한다. PC에 폰트가 설치돼 있지 않아도 같은 서체로 보인다."""
    font_dir = resource_path(os.path.join('assets', 'fonts'))
    for name in ('Pretendard-Regular.otf', 'Pretendard-SemiBold.otf', 'Pretendard-Bold.otf'):
        QFontDatabase.addApplicationFont(os.path.join(font_dir, name))
    font = QFont('Pretendard')
    font.setPixelSize(14)
    QGuiApplication.setFont(font)


def main():
    # 모든 OS에서 같은 모양이 되도록, 직접 꾸미기 쉬운 Basic 스타일 사용
    os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Basic')
    app = QGuiApplication(sys.argv)
    app.setApplicationName('Lyrics Slide Creator')
    load_fonts()

    art_provider = AlbumArtProvider()
    backend = Backend(art_provider)

    engine = QQmlApplicationEngine()
    engine.addImageProvider('art', art_provider)
    ctx = engine.rootContext()
    ctx.setContextProperty('backend', backend)
    ctx.setContextProperty('assetsUrl', QUrl.fromLocalFile(resource_path('assets')).toString())
    engine.load(QUrl.fromLocalFile(resource_path(os.path.join('src', 'qml_ui', 'qml', 'Main.qml'))))
    if not engine.rootObjects():
        sys.exit(1)

    code = app.exec()
    backend.shutdown()
    sys.exit(code)
