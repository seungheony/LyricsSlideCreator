import json
import os
import unittest
from unittest import mock

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from src.qml_ui.backend import AlbumArtProvider, Backend, detail_error, error_report, search_error  # noqa: E402
from src.utils.melon_api import MelonError  # noqa: E402


class Messages(unittest.TestCase):
    def test_search_error_kinds(self):
        self.assertIn('인터넷 연결', search_error(MelonError('network'))['message'])
        http = search_error(MelonError('http', 503))
        self.assertEqual(http['kind'], 'http')
        self.assertIn('503', http['message'])
        self.assertIn('업데이트', search_error(MelonError('parse'))['message'])

    def test_detail_error_reasons(self):
        texts = {r: detail_error({'reason': r, 'status': 500}) for r in
                 ('adult', 'no_lyrics', 'not_found', 'network', 'http', 'parse')}
        self.assertIn('19금', texts['adult'])
        self.assertIn('등록되지 않은', texts['no_lyrics'])
        self.assertIn('찾을 수 없', texts['not_found'])
        self.assertIn('인터넷 연결', texts['network'])
        self.assertEqual(len(set(texts.values())), 6)


class ErrorReport(unittest.TestCase):
    def test_home_folder_is_masked(self):
        home = os.path.expanduser('~')
        text = error_report('PPT를 만들지 못했어요', f'File "{home}/app/x.py", line 3\nValueError: boom', version='1.2.3')
        self.assertIn('v1.2.3', text)
        self.assertIn('PPT를 만들지 못했어요', text)
        self.assertIn('ValueError: boom', text)
        self.assertNotIn(home, text)
        self.assertIn('~/app/x.py', text)

    def test_empty_detail(self):
        self.assertTrue(error_report('제목', '', version='1').endswith('제목\n'))


class ArtCache(unittest.TestCase):
    def test_lru_limit(self):
        from PySide6.QtCore import QBuffer, QByteArray, QIODevice
        from PySide6.QtGui import QImage
        img = QImage(2, 2, QImage.Format.Format_RGB32)
        img.fill(0)
        data = QByteArray()
        buf = QBuffer(data)
        buf.open(QIODevice.OpenModeFlag.WriteOnly)
        img.save(buf, 'PNG')
        provider = AlbumArtProvider()
        provider.MAX_IMAGES = 3
        for key in 'abc':
            self.assertTrue(provider.put(key, bytes(data)))
        provider.has('a')                      # a를 최근에 씀 → b가 가장 오래됨
        provider.put('d', bytes(data))
        self.assertTrue(provider.has('a'))
        self.assertFalse(provider.has('b'))
        self.assertFalse(provider.put('x', b'not an image'))


class BackendFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PySide6.QtCore import QCoreApplication
        cls.app = QCoreApplication.instance() or QCoreApplication([])

    def setUp(self):
        with mock.patch('src.qml_ui.backend.updater.take_last_result', return_value=None):
            self.backend = Backend(AlbumArtProvider())
        self.backend._pool.shutdown(wait=False)
        self.backend._pool = SyncPool()
        self.backend._thumb_pool = SyncPool()
        self.events = []
        self.backend.searchFinished.connect(lambda t, j: self.events.append(('search', json.loads(j))))
        self.backend.detailFinished.connect(lambda t, j: self.events.append(('detail', json.loads(j))))

    def test_search_error_payload(self):
        with mock.patch.object(self.backend._scraper, 'search_song', side_effect=MelonError('network')):
            self.backend.search(1, '사랑')
        payload = self.events[0][1]
        self.assertEqual(payload['results'], [])
        self.assertEqual(payload['error']['kind'], 'network')

    def test_search_ok_payload(self):
        found = {'results': [{'song_id': '1'}], 'total': 77}
        with mock.patch.object(self.backend._scraper, 'search_song', return_value=found):
            self.backend.search(1, '사랑')
        self.assertEqual(self.events[0][1], {'results': [{'song_id': '1'}], 'total': 77, 'mode': 'song',
                                             'start': 1, 'fallback': False, 'error': None})

    def test_search_more_passes_start_and_keeps_thumbnails(self):
        gen = self.backend._thumb_gen
        with mock.patch.object(self.backend._scraper, 'search_song', return_value={'results': [], 'total': None}) as song, \
                mock.patch.object(self.backend._scraper, 'search_lyric') as lyric:
            self.backend.searchPage(2, '사랑', 'song', 51)
        song.assert_called_once_with('사랑', 51)
        lyric.assert_not_called()                   # 더 보기가 비었다고 가사 검색으로 바꾸지 않는다
        self.assertEqual(self.backend._thumb_gen, gen)

    def test_lyric_mode(self):
        found = {'results': [{'song_id': '9', 'snippet': 'a'}], 'total': 3}
        with mock.patch.object(self.backend._scraper, 'search_lyric', return_value=found) as lyric, \
                mock.patch.object(self.backend._scraper, 'search_song') as song:
            self.backend.searchPage(1, ' 구절 ', 'lyric', 1)
        lyric.assert_called_once_with('구절', 1)
        song.assert_not_called()
        self.assertEqual((self.events[0][1]['mode'], self.events[0][1]['fallback']), ('lyric', False))

    def test_song_search_empty_falls_back_to_lyric(self):
        lyric_res = {'results': [{'song_id': '9', 'snippet': 'a'}], 'total': 3}
        with mock.patch.object(self.backend._scraper, 'search_song', return_value={'results': [], 'total': 0}), \
                mock.patch.object(self.backend._scraper, 'search_lyric', return_value=lyric_res):
            self.backend.searchPage(1, '가사 구절', 'song', 1)
        payload = self.events[0][1]
        self.assertEqual((payload['mode'], payload['fallback'], payload['total']), ('lyric', True, 3))
        self.assertEqual(payload['results'], lyric_res['results'])

    def test_fallback_failure_keeps_empty_result(self):
        with mock.patch.object(self.backend._scraper, 'search_song', return_value={'results': [], 'total': 0}), \
                mock.patch.object(self.backend._scraper, 'search_lyric', side_effect=MelonError('network')):
            self.backend.searchPage(1, '없는', 'song', 1)
        payload = self.events[0][1]
        self.assertEqual((payload['results'], payload['mode'], payload['fallback'], payload['error']),
                         ([], 'song', False, None))

    def test_detail_sent_before_art_and_cached(self):
        det = {'song_id': '1', 'lyrics': '가사', 'image_url': 'http://x/a.jpg', 'reason': None}
        order = []
        self.backend.detailFinished.connect(lambda t, j: order.append('detail'))
        with mock.patch.object(self.backend._scraper, 'get_song_detail', return_value=det) as get, \
                mock.patch.object(self.backend, '_download_art', side_effect=lambda *a: order.append('art')):
            self.backend.songDetail(1, '1')
            self.backend.songDetail(2, '1')
        self.assertEqual(order, ['detail', 'art', 'detail', 'art'])
        self.assertEqual(get.call_count, 1)    # 두 번째는 보관한 상세를 쓴다
        self.assertEqual(self.events[0][1], {'song_id': '1', 'lyrics': '가사'})

    def test_detail_failure_message_and_no_cache(self):
        det = {'song_id': '1', 'lyrics': '', 'image_url': '', 'reason': 'network'}
        with mock.patch.object(self.backend._scraper, 'get_song_detail', return_value=det) as get:
            self.backend.songDetail(1, '1')
            self.backend.songDetail(2, '1')
        self.assertIn('인터넷 연결', self.events[0][1]['error'])
        self.assertTrue(self.events[0][1]['retry'])    # 연결 문제는 다시 시도하면 될 수 있다
        self.assertEqual(get.call_count, 2)    # 연결 문제는 보관하지 않는다

    def test_detail_retry_only_when_it_may_help(self):
        for reason, retry in (('network', True), ('http', True), ('no_lyrics', False), ('adult', False), ('not_found', False)):
            self.events.clear()
            det = {'song_id': 'r' + reason, 'lyrics': '', 'image_url': '', 'reason': reason, 'status': 503}
            with mock.patch.object(self.backend._scraper, 'get_song_detail', return_value=det):
                self.backend.songDetail(1, 'r' + reason)
            self.assertEqual(self.events[0][1]['retry'], retry, reason)

    def test_detail_exception_can_retry_and_keeps_traceback(self):
        with mock.patch.object(self.backend._scraper, 'get_song_detail', side_effect=ValueError('boom')):
            self.backend.songDetail(1, 'x')
        out = self.events[0][1]
        self.assertTrue(out['retry'])
        self.assertTrue(out['detail'].strip().endswith('ValueError: boom'))   # 대화상자 요약은 이 마지막 줄

    def test_stale_thumbnail_dropped_and_retry_allowed(self):
        calls = []
        det = {'song_id': '1', 'lyrics': '', 'image_url': 'u', 'reason': 'adult'}
        pending = []
        self.backend._thumb_pool = type('P', (), {'submit': lambda self, fn: pending.append(fn)})()
        with mock.patch.object(self.backend._scraper, 'get_song_detail', return_value=det), \
                mock.patch.object(self.backend._scraper, 'search_song', return_value={'results': [], 'total': 1}), \
                mock.patch.object(self.backend, '_download_art', side_effect=lambda *a: calls.append(a)):
            self.backend.loadArt('1')
            self.backend.search(5, '새 검색')      # 대기 중이던 썸네일은 버려진다
            pending.pop()()
            self.assertEqual(calls, [])
            self.assertNotIn('1', self.backend._art_inflight)   # 다시 요청할 수 있다
            self.backend.loadArt('1')
            pending.pop()()
            self.assertEqual(calls, [('1', 'u')])


class SyncPool:
    def submit(self, fn):
        fn()


if __name__ == '__main__':
    unittest.main()
