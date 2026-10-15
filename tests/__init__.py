"""테스트 공통 준비: 화면 없이(offscreen) 돌리고, Qt 글꼴·JS 엔진을 쓰려고 앱 객체를 하나 만든다.
앱 데이터 폴더(src/utils/app_state.py)는 임시 폴더로 돌려 개발용 user_data/를 건드리지 않는다."""
import atexit
import os
import shutil
import tempfile

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
_data_dir = tempfile.mkdtemp(prefix='lsc-test-data-')
os.environ['LSC_DATA_DIR'] = _data_dir
atexit.register(shutil.rmtree, _data_dir, ignore_errors=True)

from PySide6.QtGui import QGuiApplication  # noqa: E402

app = QGuiApplication.instance() or QGuiApplication([])
