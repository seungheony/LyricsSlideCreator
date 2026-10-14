"""배포용 빌드.

사용법:
    python scripts/build.py 1.2.0

- macOS:   dist/Lyrics Slide Creator.app  +  dist/LyricsSlideCreator-<버전>-macOS.zip
- Windows: dist/LyricsSlideCreator-<버전>-Setup.exe  (Inno Setup 필요: iscc가 PATH에 있거나 기본 설치 경로)

Nuitka로 폴더 형태(standalone)/앱 번들로 빌드한다. 실행 파일 하나(onefile)와 달리
실행할 때마다 파일을 풀 필요가 없어 빠르게 켜지고, 앱 폴더 밖에 캐시가 생기지 않는다.
"""
import os
import platform
import plistlib
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from scripts.third_party_notices import generate as generate_notices  # noqa: E402
from src.utils.version import parse_version  # noqa: E402

# 화면에 보이는 이름. 파일 이름·번들 ID 등 업데이트와 연결된 내부 이름(APP_FILE_NAME, BUNDLE_ID)은 바꾸지 않는다
# (macOS 업데이트는 새 앱을 기존 .app 경로 그대로 덮어쓰므로 .app 이름이 바뀌어도 업데이트에는 영향 없음)
APP_NAME = 'Lyrics Slide Creator'
APP_FILE_NAME = 'LyricsSlideCreator'
BUNDLE_ID = 'io.github.seungheony.lyricsslidecreator'
BUILD_INFO = os.path.join(ROOT, 'src', 'utils', '_build_info.py')
DIST = os.path.join(ROOT, 'dist')
BUILD = os.path.join(ROOT, 'build')
NOTICES = os.path.join(BUILD, 'THIRD_PARTY_NOTICES.txt')
# 앱 아이콘 (scripts/make_icons.py로 생성)
ICON_DIR = os.path.join(ROOT, 'assets', 'app-icon')

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
    # 서드파티 라이선스 고지: 설치된 패키지에서 만들어 앱에 넣는다 (src/·assets/가 아닌 build/에 만든다)
    os.makedirs(BUILD, exist_ok=True)
    print(f'서드파티 라이선스 고지: {generate_notices(NOTICES)}개 패키지', flush=True)
    excludes = []
    for name in EXCLUDED_QT:
        excludes += [f'--noinclude-dlls=*{name}*', f'--noinclude-data-files=*{name}*']
    excludes += ['--noinclude-data-files=PySide6/qml/QtQuick/Controls/iOS/*',
                 '--noinclude-data-files=PySide6/qml/QtQuick/Controls/macOS/*']
    run([
        sys.executable, '-m', 'nuitka', '--assume-yes-for-downloads',
        '--enable-plugin=pyside6', '--include-qt-plugins=qml,imageformats',
        '--nofollow-import-to=PySide6.QtWidgets', '--include-package=truststore', '--nofollow-import-to=tkinter',
        '--include-data-dir=assets=assets',
        '--include-data-dir=src/qml_ui/qml=src/qml_ui/qml',
        '--include-data-files=template.pptx=template.pptx',
        '--include-data-files=LICENSE=LICENSE',
        f'--include-data-files={NOTICES}=THIRD_PARTY_NOTICES.txt',
        f'--output-dir={BUILD}',
        # 제품 이름은 SignPath에 등록한 프로젝트 이름과 같아야 한다 (서명 조건)
        f'--product-name={APP_FILE_NAME}', f'--product-version={numeric_version(version)}',
        f'--file-version={numeric_version(version)}', '--company-name=seungheony',
        f'--file-description={APP_NAME}',
        *extra, *excludes, 'run.py',
    ])


# macOS 하한의 바닥값: PySide6 6.12 휠의 플랫폼 태그(macosx_14_0)이자 Qt 6.12의 요구 사항.
# 실제 하한은 앱에 들어가는 바이너리의 minos(최소 macOS 버전) 중 큰 값이다 (patch_info_plist가 계산해 기록)
MACOS_MIN_FLOOR = (14, 0)


def macho_minos(path):
    """Mach-O 파일(arm64)의 minos를 (주, 부) 튜플로. Mach-O가 아니거나 못 읽으면 None"""
    result = subprocess.run(['vtool', '-arch', 'arm64', '-show-build', path], capture_output=True, text=True)
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == 'minos':
            nums = [int(n) for n in parts[1].split('.') if n.isdigit()]
            return (nums + [0, 0])[:2] if nums else None
    return None


def macos_minimum(app_path):
    """앱이 실제로 요구하는 최소 macOS 버전을 구해 로그에 찍는다.

    실행 파일(run)·Python·Qt 프레임워크의 minos와 바닥값 중 큰 값. PySide6 바인딩(.so)은 휠의
    플랫폼 태그(14.0)만 믿고 minos는 SDK 버전(26.0 등)으로 찍혀 있어 제외한다(Qt 본체가 14.4라 실제 하한은 그 아래).
    """
    macos_dir = os.path.join(app_path, 'Contents', 'MacOS')
    found = {}
    for name in sorted(os.listdir(macos_dir)):
        path = os.path.join(macos_dir, name)
        if os.path.isfile(path) and (name == 'run' or name.startswith(('Python', 'libpython', 'Qt'))):
            minos = macho_minos(path)
            if minos:
                found[name] = tuple(minos)
    for name, minos in found.items():
        print(f'minos {minos[0]}.{minos[1]}  {name}', flush=True)
    floor = max([MACOS_MIN_FLOOR, *found.values()])
    print(f'LSMinimumSystemVersion: {floor[0]}.{floor[1]}', flush=True)
    return f'{floor[0]}.{floor[1]}'


def patch_info_plist(app_path):
    """Info.plist에 언어·분류·최소 macOS 버전을 넣고 다시 서명한다.

    언어 정보가 없으면 한국어 Mac에서도 OS 대화상자(PPT 저장 창 등)가 영어로 나온다.
    Info.plist를 고치면 Nuitka가 해 둔 서명이 깨지므로 ad-hoc으로 다시 서명한다(압축 전에).
    """
    plist_path = os.path.join(app_path, 'Contents', 'Info.plist')
    with open(plist_path, 'rb') as f:
        info = plistlib.load(f)
    info['CFBundleDevelopmentRegion'] = 'ko'
    info['CFBundleLocalizations'] = ['ko']
    info['LSApplicationCategoryType'] = 'public.app-category.productivity'
    info['LSMinimumSystemVersion'] = macos_minimum(app_path)
    with open(plist_path, 'wb') as f:
        plistlib.dump(info, f)
    run(['codesign', '--force', '--deep', '--sign', '-', app_path])
    run(['codesign', '--verify', '--deep', '--strict', app_path])


def build_macos(version):
    nuitka(version, [
        '--mode=app',
        f'--macos-app-name={APP_NAME}',
        f'--macos-signed-app-name={BUNDLE_ID}',
        f'--macos-app-version={version}',
        f'--macos-app-icon={os.path.join(ICON_DIR, "AppIcon.icns")}',
    ])
    app_src = os.path.join(BUILD, 'run.app')
    app_dst = os.path.join(DIST, f'{APP_NAME}.app')
    shutil.rmtree(app_dst, ignore_errors=True)
    shutil.move(app_src, app_dst)
    patch_info_plist(app_dst)
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


def add_exe_icon(exe_path, ico_path):
    """실행 파일에 아이콘(탐색기·바로가기·작업 표시줄)을 넣는다.

    Nuitka의 --windows-icon-from-ico는 쓰지 않는다: 그 옵션을 주면 Nuitka가 PySide6에
    QApplication 아이콘 코드를 덧붙이는데, 이 앱은 QtWidgets를 빼서 그 코드가 실패하고
    앱이 시작하자마자 접근 위반으로 죽는다 (v1.2.0-beta.4, 옵션만 빼면 통과하는 것으로 확인)
    """
    import ctypes
    from ctypes import wintypes
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.BeginUpdateResourceW.restype = wintypes.HANDLE
    kernel32.BeginUpdateResourceW.argtypes = (wintypes.LPCWSTR, wintypes.BOOL)
    kernel32.UpdateResourceW.argtypes = (wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                         wintypes.WORD, ctypes.c_char_p, wintypes.DWORD)
    kernel32.EndUpdateResourceW.argtypes = (wintypes.HANDLE, wintypes.BOOL)
    RT_ICON, RT_GROUP_ICON = 3, 14

    data = open(ico_path, 'rb').read()
    count = struct.unpack_from('<HHH', data, 0)[2]
    handle = kernel32.BeginUpdateResourceW(exe_path, False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())

    def update(kind, res_id, payload):
        if not kernel32.UpdateResourceW(handle, kind, res_id, 0, payload, len(payload)):
            raise ctypes.WinError(ctypes.get_last_error())

    # .ico 파일의 이미지마다 RT_ICON, 목록은 RT_GROUP_ICON(이미지 위치 대신 리소스 번호)
    group = struct.pack('<HHH', 0, 1, count)
    for i in range(count):
        width, height, colors, reserved, planes, bits, size, offset = struct.unpack_from('<BBBBHHII', data, 6 + 16 * i)
        update(RT_ICON, i + 1, data[offset:offset + size])
        group += struct.pack('<BBBBHHIH', width, height, colors, reserved, planes, bits, size, i + 1)
    update(RT_GROUP_ICON, 1, group)
    if not kernel32.EndUpdateResourceW(handle, False):
        raise ctypes.WinError(ctypes.get_last_error())

    # 실제로 들어갔는지 확인
    kernel32.LoadLibraryExW.restype = wintypes.HMODULE
    kernel32.LoadLibraryExW.argtypes = (wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD)
    kernel32.FindResourceW.argtypes = (wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p)
    kernel32.FindResourceW.restype = ctypes.c_void_p
    kernel32.FreeLibrary.argtypes = (wintypes.HMODULE,)
    module = kernel32.LoadLibraryExW(exe_path, None, 0x2)   # LOAD_LIBRARY_AS_DATAFILE
    found = module and kernel32.FindResourceW(module, 1, RT_GROUP_ICON)
    if module:
        kernel32.FreeLibrary(module)
    if not found:
        sys.exit(f'실행 파일에 아이콘을 넣지 못했습니다: {exe_path}')
    print(f'실행 파일 아이콘: {count}개 크기', flush=True)


def build_windows(version):
    nuitka(version, ['--mode=standalone', '--windows-console-mode=disable',
                     f'--output-filename={APP_FILE_NAME}.exe'])
    add_exe_icon(os.path.join(BUILD, 'run.dist', f'{APP_FILE_NAME}.exe'), os.path.join(ICON_DIR, 'AppIcon.ico'))
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

    system = platform.system()
    if system not in ('Darwin', 'Windows'):
        sys.exit(f'지원하지 않는 OS: {system}')
    os.makedirs(DIST, exist_ok=True)
    # 빌드용 버전 파일은 작업 폴더에 남기지 않는다 (남으면 개발 모드가 "TEST" 대신 그 버전으로 보인다)
    try:
        run([sys.executable, os.path.join('scripts', 'set_version.py'), version])
        outputs = build_macos(version) if system == 'Darwin' else build_windows(version)
    finally:
        if os.path.exists(BUILD_INFO):
            os.remove(BUILD_INFO)
    for path in outputs:
        print(f'완료: {os.path.relpath(path, ROOT)} ({os.path.getsize(path) / 1e6:.1f}MB)')


if __name__ == '__main__':
    main()
