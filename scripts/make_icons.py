"""앱 아이콘 생성: assets/app-icon/*.svg → AppIcon.icns(macOS), AppIcon.ico(Windows)

사용법 (macOS에서, SVG를 고친 뒤 한 번 실행하고 결과 파일을 커밋한다):
    python scripts/make_icons.py

- 32px 이하는 icon-small.svg(음표·줄을 굵게, 뒤 슬라이드 한 장 생략), 그 외는 icon.svg
- macOS 아이콘은 Apple 격자(1024 안에 824 둥근 사각형)를 그대로 쓰고,
  Windows 아이콘은 여백을 줄여 둥근 사각형이 칸을 거의 채우게 한다
- .icns는 macOS 내장 iconutil로 만든다. .ico는 PNG를 그대로 담는 형식이라 직접 쓴다
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile

from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QRectF, Qt
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, 'assets', 'app-icon')
SMALL_MAX = 32

# iconutil이 요구하는 파일 이름 → 픽셀 크기
ICNS_SIZES = {
    'icon_16x16.png': 16, 'icon_16x16@2x.png': 32,
    'icon_32x32.png': 32, 'icon_32x32@2x.png': 64,
    'icon_128x128.png': 128, 'icon_128x128@2x.png': 256,
    'icon_256x256.png': 256, 'icon_256x256@2x.png': 512,
    'icon_512x512.png': 512, 'icon_512x512@2x.png': 1024,
}
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
# Windows용: 둥근 사각형(100~924) 바깥 여백을 줄여서 그린다
WINDOWS_VIEW = QRectF(68, 68, 888, 888)


def render(size, windows=False):
    name = 'icon-small.svg' if size <= SMALL_MAX else 'icon.svg'
    renderer = QSvgRenderer(os.path.join(ICON_DIR, name))
    if windows:
        renderer.setViewBox(WINDOWS_VIEW)
    image = QImage(size, size, QImage.Format.Format_ARGB32)
    image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    renderer.render(painter)
    painter.end()
    return image


def png_bytes(image):
    data = QByteArray()
    buf = QBuffer(data)
    buf.open(QIODevice.OpenModeFlag.WriteOnly)
    image.save(buf, 'PNG')
    return bytes(data)


def make_icns():
    if shutil.which('iconutil') is None:
        print('iconutil이 없어 .icns는 건너뜀 (macOS에서 실행할 것)')
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, 'AppIcon.iconset')
        os.mkdir(iconset)
        for file_name, size in ICNS_SIZES.items():
            render(size).save(os.path.join(iconset, file_name), 'PNG')
        out = os.path.join(ICON_DIR, 'AppIcon.icns')
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', out], check=True)
    print('완료:', os.path.relpath(out, ROOT))


def make_ico():
    images = [png_bytes(render(size, windows=True)) for size in ICO_SIZES]
    header = struct.pack('<HHH', 0, 1, len(images))
    offset = len(header) + 16 * len(images)
    entries = b''
    for size, data in zip(ICO_SIZES, images):
        dim = 0 if size >= 256 else size  # 256은 0으로 적는 규칙
        entries += struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    out = os.path.join(ICON_DIR, 'AppIcon.ico')
    with open(out, 'wb') as f:
        f.write(header + entries + b''.join(images))
    print('완료:', os.path.relpath(out, ROOT))


def main():
    app = QGuiApplication(sys.argv)  # noqa: F841 (QPainter/QImage 사용에 필요)
    make_icns()
    make_ico()


if __name__ == '__main__':
    main()
