import os
import sys

from PySide6.QtCore import QSize, QTimer, QUrl
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

from src.qml_ui.backend import AlbumArtProvider, Backend
from src.utils.helpers import resource_path
from src.utils.line_fit import LineFit


def load_fonts():
    """앱에 포함된 Pretendard를 등록한다. PC에 폰트가 설치돼 있지 않아도 같은 서체로 보인다."""
    font_dir = resource_path(os.path.join('assets', 'fonts'))
    for name in ('Pretendard-Regular.otf', 'Pretendard-SemiBold.otf', 'Pretendard-Bold.otf'):
        QFontDatabase.addApplicationFont(os.path.join(font_dir, name))
    font = QFont('Pretendard')
    font.setPixelSize(14)
    QGuiApplication.setFont(font)


def window_icon():
    """창·작업 표시줄 아이콘 (macOS는 .icns, 그 외는 SVG).
    실행 파일 자체의 아이콘(탐색기·바로가기)은 빌드 때 AppIcon.ico로 넣는다(scripts/build.py)"""
    icon_dir = resource_path(os.path.join('assets', 'app-icon'))
    if sys.platform == 'darwin':
        return QIcon(os.path.join(icon_dir, 'AppIcon.icns'))
    icon = QIcon()
    for size in (16, 24, 32):   # 작은 크기는 간소화 버전
        icon.addFile(os.path.join(icon_dir, 'icon-small.svg'), QSize(size, size))
    for size in (48, 64, 128, 256):
        icon.addFile(os.path.join(icon_dir, 'icon.svg'), QSize(size, size))
    return icon


def create_app(argv):
    """앱과 QML 엔진을 만든다. 실행(exec)은 하지 않는다. 반환: (app, engine, backend)"""
    # 모든 OS에서 같은 모양이 되도록, 직접 꾸미기 쉬운 Basic 스타일 사용
    os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Basic')
    # 앱 폴더 밖에 파일을 남기지 않는다: Qt는 기본적으로 QML 변환 캐시와
    # GPU 파이프라인 캐시를 사용자 캐시 폴더(~/Library/Caches, %LOCALAPPDATA%)에 쓰므로 끈다
    os.environ['QML_DISABLE_DISK_CACHE'] = '1'
    os.environ['QSG_RHI_DISABLE_DISK_CACHE'] = '1'
    app = QGuiApplication(argv)
    app.setApplicationName('Lyrics Slide Creator')   # 내부 이름 (바꾸지 않는다)
    app.setApplicationDisplayName('가사 슬라이드 생성기')
    # 창·작업 표시줄 아이콘 (개발 모드에서도 Python 기본 아이콘 대신 앱 아이콘이 보이도록)
    if sys.platform == 'darwin':
        # macOS: 개발 모드에서 Dock 아이콘도 앱 아이콘으로
        app.setWindowIcon(window_icon())
    load_fonts()

    art_provider = AlbumArtProvider()
    backend = Backend(art_provider)

    engine = QQmlApplicationEngine()
    # QML 로드 중 경고를 모아둔다 (--self-test 에서 확인)
    engine.qml_warnings = []
    engine.warnings.connect(lambda ws: engine.qml_warnings.extend(w.toString() for w in ws))
    engine.addImageProvider('art', art_provider)
    ctx = engine.rootContext()
    ctx.setContextProperty('backend', backend)
    ctx.setContextProperty('assetsUrl', QUrl.fromLocalFile(resource_path('assets')).toString())
    engine.load(QUrl.fromLocalFile(resource_path(os.path.join('src', 'qml_ui', 'qml', 'Main.qml'))))
    if sys.platform != 'darwin':
        # Windows: 창마다 아이콘을 지정한다 (작업 표시줄·창 제목줄)
        icon = window_icon()
        for window in engine.rootObjects():
            window.setIcon(icon)
    return app, engine, backend


def self_test(app, engine):
    """빌드 결과 점검: 화면·폰트·템플릿이 모두 로드되는지 확인하고 종료 코드로 알린다."""
    def finish():
        problems = list(engine.qml_warnings)
        if not engine.rootObjects():
            problems.append('QML 화면을 불러오지 못했습니다')
        if 'Pretendard' not in QFontDatabase.families():
            problems.append('Pretendard 폰트가 등록되지 않았습니다')
        if not os.path.exists(resource_path('template.pptx')):
            problems.append('template.pptx 가 없습니다')
        else:
            try:
                fit = LineFit(resource_path('template.pptx'))
                if not fit.box or not fit.ratio('가사'):
                    problems.append('템플릿에서 가사 글상자를 찾지 못해 줄바꿈을 계산할 수 없습니다')
                elif not fit.box.exact:
                    problems.append(f'템플릿 글꼴({fit.box.latin})이 없어 줄바꿈을 정확히 계산할 수 없습니다')
            except Exception as e:
                problems.append(f'줄바꿈 계산 정보를 읽지 못했습니다: {e}')
        for p in problems:
            print(f'SELF-TEST FAIL: {p}', flush=True)
        if not problems:
            print('SELF-TEST OK', flush=True)
        app.exit(1 if problems else 0)
    QTimer.singleShot(1500, finish)


def main():
    app, engine, backend = create_app(sys.argv)
    if '--self-test' in sys.argv:
        self_test(app, engine)
    elif not engine.rootObjects():
        sys.exit(1)

    code = app.exec()
    backend.shutdown()
    sys.exit(code)
