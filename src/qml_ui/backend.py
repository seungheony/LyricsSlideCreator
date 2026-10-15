import errno
import json
import os
import platform
import shutil
import subprocess
import sys
import threading
import traceback
from collections import OrderedDict
from datetime import datetime
from urllib.parse import urlencode
from concurrent.futures import ThreadPoolExecutor

from PySide6.QtCore import QObject, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication, QImage
from PySide6.QtQml import QQmlImageProviderBase
from PySide6.QtQuick import QQuickImageProvider

from src.utils.melon_api import MelonError, MelonScraper
from src.utils.ppt_engine import PPTBuilder
from src.utils.line_fit import LineFit
from src.utils.helpers import resource_path
from src.utils import app_state, presets, updater
from src.utils.version import get_version, parse_version


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


def error_report(title, detail, version=None):
    """오류 정보 복사용 글: 버전·운영체제·제목·자세한 내용. 사용자 폴더 경로는 '~'로 바꿔 계정 이름이 새지 않게 한다"""
    home = os.path.expanduser('~')
    text = detail or ''
    if home and home not in ('~', os.sep):
        for variant in {home, home.replace('\\', '/')}:
            text = text.replace(variant, '~')
    head = f'Lyrics Slide Creator v{version or get_version()} · {sys.platform}'
    return '\n'.join([head, title, '', text]).strip() + '\n'


def feedback_url(version=None):
    """'문의하기': GitHub 새 이슈 화면 주소. 이슈 양식(.github/ISSUE_TEMPLATE/feedback.yml)의
    버전·운영체제 칸을 미리 채운다 (개인정보 없음)"""
    query = {'template': 'feedback.yml', 'version': version or get_version(), 'os': platform.platform(terse=True)}
    return f'https://github.com/{updater.REPO}/issues/new?' + urlencode(query)


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

    searchFinished = Signal(int, str)    # token, JSON 객체 {results, total, mode, start, fallback, error}  (mode: 'song'|'lyric', error: null 또는 {kind, status, message})
    detailFinished = Signal(int, str)    # token, JSON 객체 (error 키가 있으면 실패). 앨범아트는 뒤따라 artReady로 온다
    artReady = Signal(str)               # song_id
    generateFinished = Signal(str)       # JSON 객체 (path 또는 error)
    templateChanged = Signal()
    updateAvailable = Signal(str)        # JSON 객체 (version, notes(StyledText HTML), page, manual)
    updateChecked = Signal(str)          # 직접 확인했는데 새 버전이 없을 때. JSON 객체 (status: latest|dev|error, message)
    updateProgress = Signal(float)       # 0.0 ~ 1.0
    updateFailed = Signal(str)           # JSON 객체 (message, detail)
    updateCancelled = Signal()           # 다운로드를 취소함 (받던 파일은 지웠다)
    updateReady = Signal()               # 설치 시작됨 → 앱을 종료해야 함
    presetsChanged = Signal()            # 저장한 프리셋이 바뀜 (검색 결과·보관함을 다시 그린다)

    def __init__(self, art_provider):
        super().__init__()
        self._state = app_state.load()
        self._presets = presets.load()
        self._art = art_provider
        self._scraper = MelonScraper()
        self._pool = ThreadPoolExecutor(max_workers=4)        # 네트워크 작업: 앱 종료 때 기다리지 않는다
        self._ppt_pool = ThreadPoolExecutor(max_workers=1)    # PPT 저장: 앱 종료 때 끝까지 기다린다 (파일이 깨지지 않게)
        self._thumb_pool = ThreadPoolExecutor(max_workers=3)   # 검색 결과 썸네일 전용: 곡 열기·검색을 막지 않게 따로 둔다
        self._thumb_gen = 0              # 검색할 때마다 올린다: 이전 검색의 대기 중 썸네일 작업은 버린다
        self._art_inflight = set()
        self._detail_cache = OrderedDict()   # song_id → 받은 상세(가사·이미지 URL·원인). 곡 열기에 재사용
        self._detail_lock = threading.Lock()
        self._template_path = resource_path("template.pptx")
        self._line_fit = None            # 템플릿 글상자 기준 줄바꿈 계산기 (처음 쓸 때 만든다, 실패하면 False)
        self._update = None
        self._update_cancel = threading.Event()
        self._update_thread = None
        # 지난 업데이트 결과를 확인하고 남은 다운로드 파일을 지운다 (앱 폴더 밖에 아무것도 남기지 않는다)
        self._last_update = updater.take_last_result(get_version())

    # ── 정보 ──
    @Slot(result=str)
    def version(self):
        return get_version()

    @Slot(str, str)
    def copyErrorReport(self, title, detail):
        """오류 대화상자의 '오류 정보 복사': 개발자에게 알릴 때 붙여 넣을 글을 클립보드에 둔다"""
        QGuiApplication.clipboard().setText(error_report(title, detail))

    @Slot(result=str)
    def feedbackUrl(self):
        return feedback_url()

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
    # 시작할 때 한 번 읽어 메모리에 둔다. 저장에 실패해도 이번 실행에서는 다시 띄우지 않는다
    @Slot(str, result=bool)
    def tutorialSeen(self, name):
        return name in self._state.get('tutorials_seen', [])

    @Slot(str)
    def markTutorialSeen(self, name):
        seen = self._state.get('tutorials_seen', [])
        if name not in seen:
            self._state['tutorials_seen'] = seen + [name]
            app_state.save(self._state)

    # ── 창 크기·위치 ── (다음 실행 때 같은 자리에 연다, src/qml_ui/app.py)
    def window_geometry(self):
        """저장한 창 위치 {x, y, width, height, maximized}. 없거나 이상하면 None"""
        w = self._state.get('window')
        if not isinstance(w, dict):
            return None
        try:
            geo = {k: int(w[k]) for k in ('x', 'y', 'width', 'height')}
        except (KeyError, TypeError, ValueError):
            return None
        if geo['width'] <= 0 or geo['height'] <= 0:
            return None
        geo['maximized'] = w.get('maximized') is True
        return geo

    def save_window_geometry(self, x, y, width, height, maximized):
        if width <= 0 or height <= 0:
            return
        geo = {'x': int(x), 'y': int(y), 'width': int(width), 'height': int(height), 'maximized': bool(maximized)}
        if self._state.get('window') != geo:
            self._state['window'] = geo
            app_state.save(self._state)

    # ── 프리셋 ── (src/utils/presets.py)
    @Slot(result=str)
    def presetCounts(self):
        """곡 번호 → 저장한 프리셋 수 (JSON 객체)"""
        return json.dumps(presets.counts(self._presets))

    @Slot(str, result=str)
    def presetsFor(self, song_id):
        """그 곡의 프리셋 (JSON 배열, 최근 저장한 것부터)"""
        return json.dumps(presets.for_song(self._presets, song_id), ensure_ascii=False)

    @Slot(result=str)
    def allPresets(self):
        """보관함: 모든 프리셋 (JSON 배열, 최근 저장한 것부터)"""
        return json.dumps(self._presets, ensure_ascii=False)

    @Slot(str, str, result=str)
    def searchManualPresets(self, keyword, mode):
        """직접 입력한 곡 중 검색어에 맞는 곡 (JSON 배열, 검색 결과 맨 위에 붙인다). mode: 'song' | 'lyric'"""
        return json.dumps(presets.search_manual(self._presets, keyword, mode), ensure_ascii=False)

    @Slot(str, str, result=str)
    def savePresets(self, entries_json, name):
        """콘티 곡들의 프리셋을 저장한다. entries_json: [{song_id, title, artist, album, manual, text}], name: 프리셋 이름
        반환: JSON 객체 {added, same} 또는 저장하지 못했으면 {error, detail}"""
        now = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
        entries = json.loads(entries_json)
        # 이번 실행에서 곡 상세를 받았으면 앨범아트 주소를 같이 남긴다 (보관함이 상세 페이지를 다시 받지 않게)
        with self._detail_lock:
            for e in entries:
                det = self._detail_cache.get(str(e.get('song_id')))
                if det and det.get('image_url') and not e.get('manual'):
                    e['image_url'] = det['image_url']
        updated, added, same = presets.add(self._presets, entries, now, name)
        if not presets.save(updated):
            return json.dumps({'error': '프리셋을 저장하지 못했어요\n저장 폴더에 쓸 수 없어요. 디스크 공간이 부족하지 않은지 확인하고 다시 시도해 주세요.',
                               'detail': f'경로: {app_state.data_path(presets.FILE_NAME)}'}, ensure_ascii=False)
        self._presets = updated
        self.presetsChanged.emit()
        return json.dumps({'added': added, 'same': same})

    @Slot(str, str, result=bool)
    def renamePreset(self, preset_id, name):
        updated = presets.rename(self._presets, preset_id, name)
        if updated is None or not presets.save(updated):
            return False
        self._presets = updated
        self.presetsChanged.emit()
        return True

    @Slot(str, result=bool)
    def deletePreset(self, preset_id):
        updated = presets.remove(self._presets, preset_id)
        if len(updated) == len(self._presets) or not presets.save(updated):
            return False
        self._presets = updated
        self.presetsChanged.emit()
        return True

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
        self.searchPage(token, keyword, 'song', 1)

    @Slot(int, str, str, int)
    def searchPage(self, token, keyword, mode, start):
        """검색 한 쪽. mode: 'song'(제목·가수) 또는 'lyric'(가사 구절), start: 1부터 세는 시작 위치.
        곡 검색의 첫 쪽이 비면 같은 검색어로 가사 검색을 해서 결과를 대신 보여 준다(fallback)"""
        if start <= 1:
            self._thumb_gen += 1         # 이전 검색 결과의 대기 중 썸네일은 더 받지 않는다 (더 보기는 그대로)

        def work():
            error = None
            fallback = False
            shown = mode                 # 실제로 보여 주는 검색 방식
            res = {'results': [], 'total': 0}
            key = keyword.strip()
            try:
                res = self._run_search(mode, key, start)
                if mode == 'song' and start <= 1 and not res['results']:
                    try:
                        lyric = self._run_search('lyric', key, 1)
                    except MelonError:
                        lyric = None     # 가사 검색이 안 돼도 '곡 결과 없음'은 그대로 알린다
                    if lyric and lyric['results']:
                        res, shown, fallback = lyric, 'lyric', True
            except MelonError as e:
                error = search_error(e)
            except Exception:
                traceback.print_exc()
                error = search_error(MelonError('parse'))
            out = {'results': res['results'], 'total': res['total'], 'mode': shown, 'start': start,
                   'fallback': fallback, 'error': error}
            self.searchFinished.emit(token, json.dumps(out, ensure_ascii=False))
        self._pool.submit(work)

    def _run_search(self, mode, keyword, start):
        if mode == 'lyric':
            return self._scraper.search_lyric(keyword, start)
        return self._scraper.search_song(keyword, start)

    @Slot(int, str)
    def songDetail(self, token, song_id):
        def work():
            image_url = ''
            try:
                det = self._detail(song_id)
                image_url = det.get('image_url', '')
                if det['reason']:
                    # retry: 다시 시도하면 될 수 있는 실패 (연결·응답 문제). 가사가 없는 곡 등은 다시 시도해도 같다
                    out = {'error': detail_error(det), 'retry': det['reason'] in ('network', 'http')}
                else:
                    out = {'song_id': song_id, 'lyrics': det['lyrics']}
            except Exception:
                out = {'error': '가사를 불러오다 문제가 생겼어요.', 'detail': traceback.format_exc(), 'retry': True}
            # 가사를 먼저 보내고, 앨범아트는 뒤에 받는다 (편집 화면은 artReady로 나중에 채운다)
            self.detailFinished.emit(token, json.dumps(out, ensure_ascii=False))
            if image_url and 'error' not in out and not self._art.has(song_id):
                self._download_art(song_id, image_url)
        self._pool.submit(work)

    @Slot(str)
    def loadArt(self, song_id):
        """검색 결과 썸네일: 곡 상세 페이지에서 앨범아트 URL을 찾아 내려받는다."""
        self.loadArtFrom(song_id, '')

    @Slot(str, str)
    def loadArtFrom(self, song_id, image_url):
        """앨범아트를 받는다. image_url을 알면(프리셋에 저장해 둔 주소) 상세 페이지 없이 그림만 받는다"""
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
                # 저장해 둔 주소가 안 되면(멜론이 그림 주소를 바꿈) 상세 페이지에서 다시 찾는다
                if image_url and self._download_art(song_id, image_url):
                    return
                url = self._detail(song_id).get('image_url')
                if url:
                    self._download_art(song_id, url)
            except Exception:
                traceback.print_exc()
            finally:
                self._art_inflight.discard(song_id)   # 실패해도 다음에 다시 받을 수 있다
        self._thumb_pool.submit(work)

    def _download_art(self, song_id, url):
        """반환: 받았는지"""
        try:
            resp = self._scraper.get(url)
            if resp.status_code == 200 and self._art.put(song_id, resp.content):
                self.artReady.emit(song_id)
                return True
        except Exception:
            pass
        return False

    # ── PPT 생성 ──
    @Slot(str, str, str)
    def generatePpt(self, songs_json, file_url, title=''):
        """콘티 전체를 한 PPT로 저장한다. songs_json: [{title, artist, chunks}] (곡 순서대로).
        처음·곡 사이·끝의 빈 슬라이드는 ppt_engine이 넣는다. title: 문서 속성의 제목"""
        songs = json.loads(songs_json)
        save_path = QUrl(file_url).toLocalFile() or file_url
        if not save_path.lower().endswith('.pptx'):
            save_path += '.pptx'
        template = self._template_path

        def work():
            if not os.path.exists(template):
                result = {'error': '템플릿 파일을 찾지 못했어요.', 'detail': f'경로: {template}'}
            else:
                try:
                    buffer = PPTBuilder(template).generate_setlist_to_memory(songs, title)
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
        self._ppt_pool.submit(work)

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
    @Slot(bool)
    def checkForUpdate(self, manual=False):
        """새 버전 확인. 자동 확인(manual=False)은 실패해도 조용히 넘어가고, 직접 확인은 결과를 알린다"""
        def work():
            if parse_version(get_version()) is None:
                if manual:
                    self.updateChecked.emit(json.dumps(
                        {'status': 'dev', 'message': '개발 모드에서는 업데이트를 확인하지 않아요'}, ensure_ascii=False))
                return
            try:
                info = updater.find_update(get_version())
            except Exception:
                if manual:
                    self.updateChecked.emit(json.dumps(
                        {'status': 'error', 'message': '업데이트를 확인하지 못했어요. 인터넷 연결을 확인해 주세요'},
                        ensure_ascii=False))
                return
            if not info:
                if manual:
                    self.updateChecked.emit(json.dumps(
                        {'status': 'latest', 'message': '최신 버전을 쓰고 있어요'}, ensure_ascii=False))
                return
            self._update = info
            self.updateAvailable.emit(json.dumps({
                'version': info['version'],
                'notes': updater.notes_html(updater.release_notes(info['notes'])),
                'page': info['page'],
                'manual': manual,
            }, ensure_ascii=False))
        self._pool.submit(work)

    @Slot(result=str)
    def lastUpdateResult(self):
        """지난 업데이트 결과 (JSON 객체 ok, version, detail). 업데이트한 적이 없으면 빈 문자열"""
        return json.dumps(self._last_update, ensure_ascii=False) if self._last_update else ''

    @Slot()
    def startUpdate(self):
        info = self._update
        if not info or (self._update_thread and self._update_thread.is_alive()):
            return
        cancel = self._update_cancel = threading.Event()

        def fail(message, detail=''):
            self.updateFailed.emit(json.dumps({'message': message, 'detail': detail}, ensure_ascii=False))

        def work():
            try:
                updater.can_install()    # 받기 전에 설치할 수 있는 위치인지 확인
                path = updater.download(
                    info, lambda done, total: self.updateProgress.emit(done / total if total else 0.0), cancel)
                updater.install(path, get_version(), info['version'], cancel)
            except updater.UpdateCancelled:
                self.updateCancelled.emit()
                return
            except updater.UpdateError as e:
                fail(str(e), e.detail)
                return
            except Exception as e:
                fail('업데이트하다 문제가 생겼어요.\n다시 시도하거나 릴리스 페이지에서 직접 받아 설치해 주세요.',
                     f'{type(e).__name__}: {e}\n{traceback.format_exc()}')
                return
            self.updateReady.emit()
        # 스레드 풀과 따로 둔다: 검색 등이 밀려 있어도 바로 시작하고, 종료할 때 이 작업만 따로 정리한다
        self._update_thread = threading.Thread(target=work, name='update', daemon=True)
        self._update_thread.start()

    @Slot()
    def cancelUpdate(self):
        """다운로드 취소 ([취소] 버튼, 창 닫기). 받던 파일은 다운로드 스레드가 지운다"""
        updater.cancel(self._update_cancel)

    def shutdown(self):
        """앱 종료 직전. 네트워크 작업은 기다리지 않고, 저장 중인 PPT만 끝까지 기다린다"""
        if updater.cancel(self._update_cancel) and self._update_thread and self._update_thread.is_alive():
            # 받던 파일은 다운로드 스레드가 지운다. 연결이 멈춰 있으면 기다리지 않고 직접 지운다
            # (지우지 못한 것은 다음 실행 때 지운다)
            self._update_thread.join(timeout=2)
            if self._update_thread.is_alive():
                shutil.rmtree(updater.UPDATE_DIR, ignore_errors=True)
        self._pool.shutdown(wait=False, cancel_futures=True)
        self._thumb_pool.shutdown(wait=False, cancel_futures=True)
        self._ppt_pool.shutdown(wait=True)
