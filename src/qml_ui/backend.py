import errno
import json
import os
import subprocess
import sys
import threading
import traceback
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor

from PySide6.QtCore import QObject, QUrl, Signal, Slot
from PySide6.QtGui import QImage
from PySide6.QtQml import QQmlImageProviderBase
from PySide6.QtQuick import QQuickImageProvider

from src.utils.melon_api import MelonError, MelonScraper
from src.utils.ppt_engine import PPTBuilder
from src.utils.line_fit import LineFit
from src.utils.helpers import resource_path
from src.utils import app_state, updater
from src.utils.version import get_version


class AlbumArtProvider(QQuickImageProvider):
    """QML의 image://art/<song_id> 요청에 미리 받아둔 앨범아트를 돌려준다.

    이미지는 Python(requests)이 내려받으므로 Qt의 HTTPS/TLS 플러그인에 의존하지 않는다.
    """

    MAX_IMAGES = 200    # 넘으면 가장 오래 안 쓴 것부터 버린다

    def __init__(self):
        super().__init__(QQmlImageProviderBase.ImageType.Image)
        self._images = OrderedDict()
        self._lock = threading.Lock()

    def put(self, key, data):
        img = QImage()
        if not img.loadFromData(data):
            return False
        with self._lock:
            self._images[key] = img
            self._images.move_to_end(key)
            while len(self._images) > self.MAX_IMAGES:
                self._images.popitem(last=False)
        return True

    def has(self, key):
        with self._lock:
            if key in self._images:
                self._images.move_to_end(key)
                return True
            return False

    def requestImage(self, id, size, requested_size):
        key = id.split('?')[0]
        with self._lock:
            img = self._images.get(key, QImage())
            if key in self._images:
                self._images.move_to_end(key)
        if size is not None and not img.isNull():
            size.setWidth(img.width())
            size.setHeight(img.height())
        return img


def _save_error(e, path):
    """저장 실패 원인별 안내 (해요체)."""
    detail = f'경로: {path}\n{type(e).__name__}: {e}'
    if isinstance(e, FileNotFoundError):
        msg = '저장할 폴더를 찾을 수 없어요. 폴더가 지워졌거나 USB·네트워크 드라이브가 빠졌는지 확인하고 다른 위치에 저장해 보세요.'
    elif isinstance(e, PermissionError) or getattr(e, 'errno', None) in (errno.EACCES, errno.EPERM, errno.EROFS):
        msg = ('이 파일에 쓸 수 없어요. PowerPoint 등에서 같은 파일이 열려 있다면 닫고 다시 시도하거나, '
               '다른 이름·다른 폴더에 저장해 보세요. 읽기 전용 폴더일 수도 있어요.')
    elif getattr(e, 'errno', None) in (errno.ENOSPC, getattr(errno, 'EDQUOT', errno.ENOSPC)):
        msg = '저장 공간이 부족해요. 디스크 공간을 확보하거나 다른 드라이브에 저장해 보세요.'
    else:
        msg = '파일을 저장하지 못했어요. 다른 이름이나 다른 폴더에 저장해 보세요.'
    return {'error': msg, 'detail': detail}


def search_error(e):
    """검색 실패 원인별 안내 (해요체)"""
    if e.kind == 'network':
        msg = '인터넷 연결을 확인해 주세요.\n멜론에 연결하지 못했어요.'
    elif e.kind == 'http':
        msg = f'멜론이 요청을 받아 주지 않아요 (오류 코드 {e.status}).\n잠시 뒤에 다시 시도해 주세요.'
    else:
        msg = '검색 결과를 읽지 못했어요.\n멜론 화면이 바뀐 것 같아요. 앱을 최신 버전으로 업데이트해 주세요.'
    return {'kind': e.kind, 'status': e.status, 'message': msg}


def detail_error(det):
    """가사를 못 얻은 원인별 안내 (해요체). det['reason']: adult, no_lyrics, not_found, network, http, parse"""
    reason = det.get('reason')
    if reason == 'adult':
        return '19금 곡이라 가사를 가져올 수 없어요.\n멜론이 성인 인증을 한 로그인 사용자에게만 가사를 보여 줘요.'
    if reason == 'no_lyrics':
        return '멜론에 가사가 등록되지 않은 곡이에요.\n다른 곡을 골라 보세요.'
    if reason == 'not_found':
        return '멜론에서 이 곡을 찾을 수 없어요.\n삭제되었거나 비공개된 곡일 수 있어요.'
    if reason == 'network':
        return '인터넷 연결을 확인해 주세요.\n멜론에 연결하지 못했어요.'
    if reason == 'http':
        return f'멜론이 요청을 받아 주지 않아요 (오류 코드 {det.get("status")}).\n잠시 뒤에 다시 시도해 주세요.'
    return '가사를 읽지 못했어요.\n멜론 화면이 바뀐 것 같아요. 앱을 최신 버전으로 업데이트해 주세요.'


class Backend(QObject):
    """QML에서 backend.* 로 호출하는 브리지.

    시간이 걸리는 작업은 스레드 풀에서 실행하고 결과를 시그널(JSON 문자열)로 돌려준다.
    다른 스레드에서 emit한 시그널은 Qt가 메인 스레드로 넘겨주므로 QML에서 안전하게 받을 수 있다.
    """

    searchFinished = Signal(int, str)    # token, JSON 객체 {results, error}  (error: null 또는 {kind, status, message})
    detailFinished = Signal(int, str)    # token, JSON 객체 (error 키가 있으면 실패). 앨범아트는 뒤따라 artReady로 온다
    artReady = Signal(str)               # song_id
    generateFinished = Signal(str)       # JSON 객체 (path 또는 error)
    templateChanged = Signal()
    updateAvailable = Signal(str)        # JSON 객체 (version, notes, page)
    updateProgress = Signal(float)       # 0.0 ~ 1.0
    updateFailed = Signal(str)           # 사용자에게 보여줄 사유
    updateReady = Signal()               # 설치 시작됨 → 앱을 종료해야 함

    def __init__(self, art_provider):
        super().__init__()
        self._art = art_provider
        self._scraper = MelonScraper()
        self._pool = ThreadPoolExecutor(max_workers=4)
        self._thumb_pool = ThreadPoolExecutor(max_workers=3)   # 검색 결과 썸네일 전용: 곡 열기·검색을 막지 않게 따로 둔다
        self._thumb_gen = 0              # 검색할 때마다 올린다: 이전 검색의 대기 중 썸네일 작업은 버린다
        self._art_inflight = set()
        self._detail_cache = OrderedDict()   # song_id → 받은 상세(가사·이미지 URL·원인). 곡 열기에 재사용
        self._detail_lock = threading.Lock()
        self._template_path = resource_path("template.pptx")
        self._line_fit = None            # 템플릿 글상자 기준 줄바꿈 계산기 (처음 쓸 때 만든다, 실패하면 False)
        self._update = None
        # 지난 업데이트에서 남은 다운로드 파일 정리 (앱 폴더 밖에 아무것도 남기지 않는다)
        updater.cleanup()

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
            self._line_fit = None
            self.templateChanged.emit()
        return os.path.basename(self._template_path)

    # ── PPT 줄바꿈 미리 계산 ── (템플릿의 가사 글상자 기준, src/utils/line_fit.py)
    def _fit(self):
        if self._line_fit is None:
            try:
                self._line_fit = LineFit(self._template_path)
            except Exception:
                traceback.print_exc()
                self._line_fit = False
        return self._line_fit or None

    @Slot(str, result=str)
    def lineWidthRatios(self, lines_json):
        """줄마다 글상자 폭 대비 글자 폭 비율 (JSON 배열). 1을 넘으면 PPT에서 줄바꿈된다. 계산할 수 없으면 0"""
        fit = self._fit()
        return json.dumps([fit.ratio(line) if fit else 0 for line in json.loads(lines_json)])

    @Slot(result=str)
    def lineFitInfo(self):
        """계산 기준 (JSON 객체: font, sizePt, availablePt, exact). 계산할 수 없으면 빈 객체"""
        fit = self._fit()
        if not fit or not fit.box or not fit.box.wraps:
            return '{}'
        box = fit.box
        font = box.latin if box.latin == box.east_asian else f'{box.east_asian} / {box.latin}'
        return json.dumps({'font': font, 'bold': box.bold, 'sizePt': round(box.size_pt, 1),
                           'availablePt': round(box.available_pt, 1), 'exact': box.exact})

    # ── 첫 실행 튜토리얼 ── (name: "search" | "editor")
    @Slot(str, result=bool)
    def tutorialSeen(self, name):
        return name in app_state.load().get('tutorials_seen', [])

    @Slot(str)
    def markTutorialSeen(self, name):
        state = app_state.load()
        seen = state.get('tutorials_seen', [])
        if name not in seen:
            state['tutorials_seen'] = seen + [name]
            app_state.save(state)

    # ── 멜론 ──
    DETAIL_CACHE_MAX = 40

    def _detail(self, song_id):
        """곡 상세. 같은 곡을 다시 받지 않도록 연결 문제가 아닌 결과는 메모리에 보관한다"""
        with self._detail_lock:
            det = self._detail_cache.get(song_id)
            if det:
                self._detail_cache.move_to_end(song_id)
                return det
        det = self._scraper.get_song_detail(song_id)
        if det['reason'] not in ('network', 'http', 'parse'):
            with self._detail_lock:
                self._detail_cache[song_id] = det
                while len(self._detail_cache) > self.DETAIL_CACHE_MAX:
                    self._detail_cache.popitem(last=False)
        return det

    @Slot(int, str)
    def search(self, token, keyword):
        self._thumb_gen += 1             # 이전 검색 결과의 대기 중 썸네일은 더 받지 않는다

        def work():
            error = None
            try:
                results = self._scraper.search_song(keyword.strip())
            except MelonError as e:
                results, error = [], search_error(e)
            except Exception:
                traceback.print_exc()
                results, error = [], search_error(MelonError('parse'))
            self.searchFinished.emit(token, json.dumps({'results': results, 'error': error}, ensure_ascii=False))
        self._pool.submit(work)

    @Slot(int, str)
    def songDetail(self, token, song_id):
        def work():
            image_url = ''
            try:
                det = self._detail(song_id)
                image_url = det.get('image_url', '')
                if det['reason']:
                    out = {'error': detail_error(det)}
                else:
                    out = {'song_id': song_id, 'lyrics': det['lyrics']}
            except Exception:
                out = {'error': '가사를 불러오다 문제가 생겼어요.', 'detail': traceback.format_exc()}
            # 가사를 먼저 보내고, 앨범아트는 뒤에 받는다 (편집 화면은 artReady로 나중에 채운다)
            self.detailFinished.emit(token, json.dumps(out, ensure_ascii=False))
            if image_url and 'error' not in out and not self._art.has(song_id):
                self._download_art(song_id, image_url)
        self._pool.submit(work)

    @Slot(str)
    def loadArt(self, song_id):
        """검색 결과 썸네일: 곡 상세 페이지에서 앨범아트 URL을 찾아 내려받는다."""
        if self._art.has(song_id):
            self.artReady.emit(song_id)
            return
        if song_id in self._art_inflight:
            return
        self._art_inflight.add(song_id)
        gen = self._thumb_gen

        def work():
            try:
                if gen != self._thumb_gen:
                    return               # 그 사이 새 검색을 했다
                det = self._detail(song_id)
                if det.get('image_url'):
                    self._download_art(song_id, det['image_url'])
            except Exception:
                traceback.print_exc()
            finally:
                self._art_inflight.discard(song_id)   # 실패해도 다음에 다시 받을 수 있다
        self._thumb_pool.submit(work)

    def _download_art(self, song_id, url):
        try:
            resp = self._scraper.get(url)
            if resp.status_code == 200 and self._art.put(song_id, resp.content):
                self.artReady.emit(song_id)
        except Exception:
            pass

    # ── PPT 생성 ──
    @Slot(str, str, str)
    def generatePpt(self, chunks_json, file_url, song_title=''):
        chunks = json.loads(chunks_json)
        save_path = QUrl(file_url).toLocalFile() or file_url
        if not save_path.lower().endswith('.pptx'):
            save_path += '.pptx'
        template = self._template_path

        def work():
            if not os.path.exists(template):
                result = {'error': '템플릿 파일을 찾지 못했어요.', 'detail': f'경로: {template}'}
            else:
                try:
                    buffer = PPTBuilder(template).generate_slides_to_memory(chunks, song_title)
                    if not buffer:
                        result = {'error': 'PPT를 만들지 못했어요', 'detail': '메모리에서 PPT 객체를 만들지 못했어요.'}
                    else:
                        try:
                            PPTBuilder.save_to_file(buffer, save_path)
                            result = {'path': save_path}
                        except OSError as e:
                            result = _save_error(e, save_path)
                except Exception:
                    result = {'error': 'PPT를 만들다 문제가 생겼어요', 'detail': traceback.format_exc()}
            self.generateFinished.emit(json.dumps(result, ensure_ascii=False))
        self._pool.submit(work)

    @Slot(str)
    def revealInFolder(self, path):
        """저장한 PPT를 파일 관리자에서 선택해 보여준다 (사용자가 누를 때만 호출)."""
        path = os.path.normpath(path)
        if not os.path.exists(path):
            return
        try:
            if sys.platform == 'darwin':
                subprocess.Popen(['open', '-R', path])
            elif sys.platform == 'win32':
                subprocess.Popen(['explorer', f'/select,{path}'])
            else:
                subprocess.Popen(['xdg-open', os.path.dirname(path)])
        except OSError:
            pass

    # ── 업데이트 ──
    @Slot()
    def checkForUpdate(self):
        def work():
            try:
                info = updater.find_update(get_version())
            except Exception:
                return  # 오프라인 등: 조용히 넘어간다
            if info:
                self._update = info
                self.updateAvailable.emit(json.dumps(
                    {k: info[k] for k in ('version', 'notes', 'page')}, ensure_ascii=False))
        self._pool.submit(work)

    @Slot()
    def startUpdate(self):
        info = self._update
        if not info:
            return

        def work():
            try:
                path = updater.download(info, lambda done, total: self.updateProgress.emit(done / total if total else 0.0))
                updater.install(path)
            except updater.UpdateError as e:
                self.updateFailed.emit(str(e))
                return
            except Exception as e:
                self.updateFailed.emit(f'업데이트하다 문제가 생겼어요.\n{e}')
                return
            self.updateReady.emit()
        self._pool.submit(work)

    def shutdown(self):
        self._pool.shutdown(wait=False, cancel_futures=True)
        self._thumb_pool.shutdown(wait=False, cancel_futures=True)
