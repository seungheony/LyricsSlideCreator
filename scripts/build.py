"""배포용 빌드.

사용법:
    python scripts/build.py 1.2.0

- macOS:   dist/가사 슬라이드 생성기.app  +  dist/LyricsSlideCreator-<버전>-macOS.zip
- Windows: dist/LyricsSlideCreator-<버전>-Setup.exe  (Inno Setup 필요: iscc가 PATH에 있거나 기본 설치 경로)

Nuitka로 폴더 형태(standalone)/앱 번들로 빌드한다. 실행 파일 하나(onefile)와 달리
실행할 때마다 파일을 풀 필요가 없어 빠르게 켜지고, 앱 폴더 밖에 캐시가 생기지 않는다.
"""
import os
import platform
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from src.utils.version import parse_version  # noqa: E402

# 화면에 보이는 이름. 파일 이름·번들 ID 등 업데이트와 연결된 내부 이름(APP_FILE_NAME, BUNDLE_ID)은 바꾸지 않는다
# (macOS 업데이트는 새 앱을 기존 .app 경로 그대로 덮어쓰므로 .app 이름이 바뀌어도 업데이트에는 영향 없음)
APP_NAME = '가사 슬라이드 생성기'
APP_FILE_NAME = 'LyricsSlideCreator'
BUNDLE_ID = 'io.github.seungheony.lyricsslidecreator'
DIST = os.path.join(ROOT, 'dist')
BUILD = os.path.join(ROOT, 'build')

# 앱이 쓰지 않는 Qt 모듈. Nuitka가 QML 모듈을 통째로 가져오면서 웹 엔진(200MB+) 등이 딸려오므로 뺀다.
# 파일 이름에 이 문자열이 들어가면 제외 (macOS: QtWebEngineCore, Windows: Qt6WebEngineCore.dll 등)
EXCLUDED_QT = [
    'WebEngine', 'WebView', 'WebChannel', 'WebSockets', 'Pdf', 'Quick3D', 'Qt3D', '3D', 'ShaderTools',
    'Multimedia', 'SpatialAudio', 'Charts', 'DataVisualization', 'Graphs', 'Location', 'Positioning',
    'RemoteObjects', 'Scxml', 'StateMachine', 'Sensors', 'QtTest', 'TextToSpeech', 'Labs', 'Qt5Compat',
    'Particles', 'Timeline', 'VirtualKeyboard', 'Scene2D', 'Scene3D', 'VectorImage', 'LocalStorage',
    # Basic 외 Controls 스타일
    'Imagine', 'Material', 'Universal', 'FluentWinUI3', 'Fusion', 'NativeStyle', 'Controls2IOS',
    'Controls2MacOS', 'Controls2Macos', 'Controls2Native', 'Controls2Windows', 'QtWidgets', 'OpenGLWidgets',
    'designer', 'DesignSupport', 'DesignHelpers', 'QtSql', 'QuickTest', 'XmlListModel',
]


def run(cmd, **kwargs):
    print('$', ' '.join(f'"{c}"' if ' ' in c else c for c in cmd), flush=True)
    subprocess.run(cmd, check=True, cwd=ROOT, **kwargs)


def numeric_version(version):
    """Windows 파일 버전은 숫자 4자리만 허용: 1.2.0-beta.1 → 1.2.0.1"""
    major, minor, patch, is_release, pre_num = parse_version(version)
    return f'{major}.{minor}.{patch}.{0 if is_release else pre_num}'


def nuitka(version, extra):
    excludes = []
    for name in EXCLUDED_QT:
        excludes += [f'--noinclude-dlls=*{name}*', f'--noinclude-data-files=*{name}*']
    excludes += ['--noinclude-data-files=PySide6/qml/QtQuick/Controls/iOS/*',
                 '--noinclude-data-files=PySide6/qml/QtQuick/Controls/macOS/*']
    run([
        sys.executable, '-m', 'nuitka', '--assume-yes-for-downloads',
        '--enable-plugin=pyside6', '--include-qt-plugins=qml,imageformats',
        '--nofollow-import-to=PySide6.QtWidgets', '--nofollow-import-to=tkinter',
        '--include-data-dir=assets=assets',
        '--include-data-dir=src/qml_ui/qml=src/qml_ui/qml',
        '--include-data-files=template.pptx=template.pptx',
        f'--output-dir={BUILD}',
        f'--product-name={APP_NAME}', f'--product-version={numeric_version(version)}',
        f'--file-version={numeric_version(version)}', '--company-name=seungheony',
        f'--file-description={APP_NAME}',
        *extra, *excludes, 'run.py',
    ])


def build_macos(version):
    nuitka(version, [
        '--mode=app',
        f'--macos-app-name={APP_NAME}',
        f'--macos-signed-app-name={BUNDLE_ID}',
        f'--macos-app-version={version}',
    ])
    app_src = os.path.join(BUILD, 'run.app')
    app_dst = os.path.join(DIST, f'{APP_NAME}.app')
    shutil.rmtree(app_dst, ignore_errors=True)
    shutil.move(app_src, app_dst)
    # ditto: 심볼릭 링크·권한·확장 속성을 보존하는 macOS 표준 압축 방식 (업데이트 시에도 ditto로 푼다)
    zip_path = os.path.join(DIST, f'{APP_FILE_NAME}-{version}-macOS.zip')
    run(['ditto', '-c', '-k', '--keepParent', app_dst, zip_path])
    return [zip_path]


def find_iscc():
    found = shutil.which('iscc')
    if found:
        return found
    for base in (os.environ.get('ProgramFiles(x86)'), os.environ.get('ProgramFiles'),
                 os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Programs')):
        if base:
            path = os.path.join(base, 'Inno Setup 6', 'ISCC.exe')
            if os.path.exists(path):
                return path
    sys.exit('Inno Setup(ISCC.exe)을 찾을 수 없습니다. https://jrsoftware.org/isinfo.php 에서 설치하세요.')


def build_windows(version):
    nuitka(version, ['--mode=standalone', '--windows-console-mode=disable',
                     f'--output-filename={APP_FILE_NAME}.exe'])
    run([find_iscc(),
         f'/DAppVersion={version}',
         f'/DAppNumericVersion={numeric_version(version)}',
         f'/DSourceDir={os.path.join(BUILD, "run.dist")}',
         f'/DOutputDir={DIST}',
         os.path.join(ROOT, 'installer', 'windows.iss')])
    return [os.path.join(DIST, f'{APP_FILE_NAME}-{version}-Setup.exe')]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    version = sys.argv[1].lstrip('v')
    if parse_version(version) is None:
        sys.exit(f'버전 형식이 올바르지 않습니다: {sys.argv[1]}')

    run([sys.executable, os.path.join('scripts', 'set_version.py'), version])
    os.makedirs(DIST, exist_ok=True)
    system = platform.system()
    if system == 'Darwin':
        outputs = build_macos(version)
    elif system == 'Windows':
        outputs = build_windows(version)
    else:
        sys.exit(f'지원하지 않는 OS: {system}')
    for path in outputs:
        print(f'완료: {os.path.relpath(path, ROOT)} ({os.path.getsize(path) / 1e6:.1f}MB)')


if __name__ == '__main__':
    main()
