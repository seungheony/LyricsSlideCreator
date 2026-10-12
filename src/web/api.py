import os
import traceback

import webview

from src.utils.melon_api import MelonScraper
from src.utils.ppt_engine import PPTBuilder
from src.utils.helpers import resource_path
from src.utils.version import get_version


class Api:
    """JS에서 window.pywebview.api.* 로 호출하는 백엔드 브리지.

    pywebview는 호출마다 별도 스레드에서 실행하므로 QThread 같은 별도 처리가 필요 없다.
    언더스코어로 시작하는 속성은 JS에 노출되지 않는다.
    """

    def __init__(self):
        self._window = None
        self._scraper = MelonScraper()
        self._template_path = resource_path("template.pptx")

    def set_window(self, window):
        self._window = window

    # ── 초기 정보 ──
    def init(self):
        return {
            'version': get_version(),
            'template': os.path.basename(self._template_path),
        }

    # ── 멜론 ──
    def search(self, keyword):
        keyword = (keyword or '').strip()
        if not keyword:
            return []
        return self._scraper.search_song(keyword)

    def album_art(self, song_id):
        return self._scraper.get_album_image_url(song_id)

    def song_detail(self, song_id):
        try:
            det = self._scraper.get_song_detail(song_id)
        except Exception:
            return {'error': '가사를 불러오는 중 오류가 발생했습니다.', 'detail': traceback.format_exc()}
        if not det or not det.get('lyrics'):
            return {'error': '가사 정보를 가져오지 못했습니다.\n네트워크 상태를 확인하거나 다른 곡으로 시도해보세요.'}
        return det

    # ── 슬라이드 ──
    def choose_template(self):
        paths = self._window.create_file_dialog(
            webview.FileDialog.OPEN, file_types=('PowerPoint (*.pptx)',)
        )
        if not paths:
            return None
        self._template_path = paths[0]
        return os.path.basename(self._template_path)

    def generate_ppt(self, chunks, default_name):
        if not chunks:
            return {'error': '가사가 없습니다.'}
        if not os.path.exists(self._template_path):
            return {'error': '템플릿 파일을 찾을 수 없습니다.', 'detail': f'경로: {self._template_path}'}

        filename = (default_name or 'lyrics').replace('/', '_') + '.pptx'
        save_path = self._window.create_file_dialog(
            webview.FileDialog.SAVE, save_filename=filename, file_types=('PowerPoint (*.pptx)',)
        )
        if not save_path:
            return {'cancelled': True}
        if isinstance(save_path, (list, tuple)):
            save_path = save_path[0]
        if not save_path.lower().endswith('.pptx'):
            save_path += '.pptx'

        try:
            ppt_buffer = PPTBuilder(self._template_path).generate_slides_to_memory(chunks)
            if not ppt_buffer:
                return {'error': 'PPT 생성 실패.', 'detail': '메모리에서 PPT 객체를 생성하지 못했습니다.'}
            if not PPTBuilder.save_to_file(ppt_buffer, save_path):
                return {'error': '파일 저장 실패.', 'detail': f'다음 경로에 파일을 쓸 수 없습니다:\n{save_path}\n\n권한 문제를 확인해주세요.'}
        except Exception:
            return {'error': 'PPT 생성 중 예외가 발생했습니다.', 'detail': traceback.format_exc()}

        return {'path': save_path}
