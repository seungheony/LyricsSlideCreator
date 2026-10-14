import os
import sys

from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QSize, QTimer, QUrl
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication, QIcon, QImage
from PySide6.QtQml import QQmlApplicationEngine

from src.qml_ui.backend import AlbumArtProvider, Backend
from src.utils import updater
from src.utils.helpers import resource_path
from src.utils.line_fit import LineFit
from src.utils.ppt_engine import PPTBuilder


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
    # 주의: app.aboutToQuit 등 Qt 시그널에 backend의 Slot 메서드를 직접 connect하지 말 것. Nuitka로 컴파일한 앱에서
    # 시작하자마자 무관한 곳(python-pptx 템플릿 읽기)에서 SIGSEGV로 죽는다(v1.3.0-beta.1 개발 중 발견, 소스 실행에서는 멀쩡함).
    # 창을 닫으면 main()이 backend.shutdown()을 부르고, 거기서 진행 중인 업데이트 다운로드를 취소한다

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
        problems.extend(check_runtime())
        for p in problems:
            print(f'SELF-TEST FAIL: {p}', flush=True)
        if not problems:
            print('SELF-TEST OK', flush=True)
        app.exit(1 if problems else 0)
    QTimer.singleShot(1500, finish)


def check_runtime():
    """실행에 필요한 것들이 빌드에 들어갔는지 확인한다: 메모리 PPT 생성, JPEG(앨범아트) 해석, HTTPS 인증서"""
    problems = []
    try:
        from pptx import Presentation
        # 곡 하나 = 빈 슬라이드, 가사, 빈 슬라이드
        buffer = PPTBuilder(resource_path('template.pptx')).generate_setlist_to_memory(
            [{'title': '점검', 'artist': '', 'chunks': ['가사 첫 줄\n둘째 줄']}], '점검')
        if not buffer or len(Presentation(buffer).slides) != 3:
            problems.append('메모리에서 PPT를 만들지 못했습니다')
    except Exception as e:
        problems.append(f'메모리에서 PPT를 만들지 못했습니다: {e}')

    # 멜론 앨범아트는 JPEG: imageformats 플러그인(qjpeg)이 빠지면 그림이 보이지 않는다
    image = QImage(4, 4, QImage.Format.Format_RGB32)
    image.fill(0x00CD3C)
    data = QByteArray()
    buf = QBuffer(data)
    buf.open(QIODevice.OpenModeFlag.WriteOnly)
    decoded = QImage()
    if not image.save(buf, 'JPG') or not decoded.loadFromData(bytes(data), 'JPG') or decoded.width() != 4:
        problems.append('JPEG 이미지를 읽지 못합니다 (앨범아트가 보이지 않음)')

    # HTTPS: requests는 certifi 인증서 파일이 없으면 연결 자체를 하지 않는다. 운영체제 인증서는 truststore로 쓴다 (run.py)
    try:
        import certifi
        if not os.path.exists(certifi.where()):
            problems.append(f'HTTPS 인증서 파일이 없습니다: {certifi.where()}')
    except Exception as e:
        problems.append(f'certifi를 불러오지 못했습니다: {e}')
    try:
        import ssl
        import truststore
        if ssl.SSLContext is not truststore.SSLContext:
            problems.append('운영체제 인증서 저장소(truststore)를 쓰지 않고 있습니다')
    except Exception as e:
        problems.append(f'truststore를 불러오지 못했습니다: {e}')
    return problems


def main():
    updater.hold_app_mutex()
    app, engine, backend = create_app(sys.argv)
    if '--self-test' in sys.argv:
        self_test(app, engine)
    elif not engine.rootObjects():
        sys.exit(1)

    code = app.exec()
    backend.shutdown()
    # 남은 네트워크 작업(검색·앨범아트·업데이트 확인)이 끝나기를 기다리지 않고 바로 끝낸다.
    # sys.exit는 스레드 풀의 작업이 끝날 때까지(연결 시간 제한만큼) 프로세스를 붙잡는다. PPT 저장은 shutdown()에서 기다렸다
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)
