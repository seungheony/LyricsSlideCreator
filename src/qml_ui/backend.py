import json
import os
import threading
import traceback
from concurrent.futures import ThreadPoolExecutor

import requests
from PySide6.QtCore import QObject, QSize, QUrl, Signal, Slot
from PySide6.QtGui import QImage
from PySide6.QtQml import QQmlImageProviderBase
from PySide6.QtQuick import QQuickImageProvider

from src.utils.melon_api import MelonScraper
from src.utils.ppt_engine import PPTBuilder
from src.utils.helpers import resource_path
from src.utils.version import get_version


class AlbumArtProvider(QQuickImageProvider):
    """QML의 image://art/<song_id> 요청에 미리 받아둔 앨범아트를 돌려준다.

    이미지는 Python(requests)이 내려받으므로 Qt의 HTTPS/TLS 플러그인에 의존하지 않는다.
    """

    def __init__(self):
        super().__init__(QQmlImageProviderBase.ImageType.Image)
        self._images = {}
        self._lock = threading.Lock()

    def put(self, key, data):
        img = QImage()
        if not img.loadFromData(data):
            return False
        with self._lock:
            self._images[key] = img
        return True

    def has(self, key):
        with self._lock:
            return key in self._images

    def requestImage(self, id, size, requested_size):
        with self._lock:
            img = self._images.get(id.split('?')[0], QImage())
        if size is not None and not img.isNull():
            size.setWidth(img.width())
            size.setHeight(img.height())
        return img


class Backend(QObject):
    """QML에서 backend.* 로 호출하는 브리지.

    시간이 걸리는 작업은 스레드 풀에서 실행하고 결과를 시그널(JSON 문자열)로 돌려준다.
    다른 스레드에서 emit한 시그널은 Qt가 메인 스레드로 넘겨주므로 QML에서 안전하게 받을 수 있다.
    """

    searchFinished = Signal(int, str)    # token, JSON 배열
    detailFinished = Signal(int, str)    # token, JSON 객체 (error 키가 있으면 실패)
    artReady = Signal(str)               # song_id
    generateFinished = Signal(str)       # JSON 객체 (path 또는 error)
    templateChanged = Signal()

    def __init__(self, art_provider):
        super().__init__()
        self._art = art_provider
        self._scraper = MelonScraper()
        self._pool = ThreadPoolExecutor(max_workers=6)
        self._art_requested = set()
        self._template_path = resource_path("template.pptx")

    # ── 정보 ──
    @Slot(result=str)
    def version(self):
        return get_version()

    @Slot(result=str)
    def templateName(self):
        return os.path.basename(self._template_path)

    @Slot(str, result=str)
    def setTemplate(self, file_url):
        path = QUrl(file_url).toLocalFile() or file_url
        if path:
            self._template_path = path
            self.templateChanged.emit()
        return os.path.basename(self._template_path)

    # ── 멜론 ──
    @Slot(int, str)
    def search(self, token, keyword):
        def work():
            try:
                results = self._scraper.search_song(keyword.strip())
            except Exception:
                results = []
            self.searchFinished.emit(token, json.dumps(results, ensure_ascii=False))
        self._pool.submit(work)

    @Slot(int, str)
    def songDetail(self, token, song_id):
        def work():
            try:
                det = self._scraper.get_song_detail(song_id)
                if not det or not det.get('lyrics'):
                    det = {'error': '가사 정보를 가져오지 못했습니다.\n네트워크 상태를 확인하거나 다른 곡으로 시도해보세요.'}
                elif det.get('image_url'):
                    self._download_art(song_id, det['image_url'])
            except Exception:
                det = {'error': '가사를 불러오는 중 오류가 발생했습니다.', 'detail': traceback.format_exc()}
            self.detailFinished.emit(token, json.dumps(det, ensure_ascii=False))
        self._pool.submit(work)

    @Slot(str)
    def loadArt(self, song_id):
        """검색 결과 썸네일: 곡 상세 페이지에서 앨범아트 URL을 찾아 내려받는다."""
        if self._art.has(song_id):
            self.artReady.emit(song_id)
            return
        if song_id in self._art_requested:
            return
        self._art_requested.add(song_id)

        def work():
            url = self._scraper.get_album_image_url(song_id)
            if url:
                self._download_art(song_id, url)
        self._pool.submit(work)

    def _download_art(self, song_id, url):
        try:
            resp = requests.get(url, headers=self._scraper.headers, timeout=10)
            if resp.status_code == 200 and self._art.put(song_id, resp.content):
                self.artReady.emit(song_id)
        except Exception:
            pass

    # ── PPT 생성 ──
    @Slot(str, str)
    def generatePpt(self, chunks_json, file_url):
        chunks = json.loads(chunks_json)
        save_path = QUrl(file_url).toLocalFile() or file_url
        if not save_path.lower().endswith('.pptx'):
            save_path += '.pptx'
        template = self._template_path

        def work():
            if not os.path.exists(template):
                result = {'error': '템플릿 파일을 찾을 수 없습니다.', 'detail': f'경로: {template}'}
            else:
                try:
                    buffer = PPTBuilder(template).generate_slides_to_memory(chunks)
                    if not buffer:
                        result = {'error': 'PPT 생성 실패.', 'detail': '메모리에서 PPT 객체를 생성하지 못했습니다.'}
                    elif not PPTBuilder.save_to_file(buffer, save_path):
                        result = {'error': '파일 저장 실패.', 'detail': f'다음 경로에 파일을 쓸 수 없습니다:\n{save_path}\n\n권한 문제를 확인해주세요.'}
                    else:
                        result = {'path': save_path}
                except Exception:
                    result = {'error': 'PPT 생성 중 예외가 발생했습니다.', 'detail': traceback.format_exc()}
            self.generateFinished.emit(json.dumps(result, ensure_ascii=False))
        self._pool.submit(work)

    def shutdown(self):
        self._pool.shutdown(wait=False, cancel_futures=True)
