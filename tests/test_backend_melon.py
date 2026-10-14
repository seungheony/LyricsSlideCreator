import json
import os
import unittest
from unittest import mock

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from src.qml_ui.backend import AlbumArtProvider, Backend, detail_error, search_error  # noqa: E402
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
        with mock.patch('src.qml_ui.backend.updater.cleanup'):
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
        with mock.patch.object(self.backend._scraper, 'search_song', return_value=[{'song_id': '1'}]):
            self.backend.search(1, '사랑')
        self.assertEqual(self.events[0][1], {'results': [{'song_id': '1'}], 'error': None})

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
        self.assertEqual(get.call_count, 2)    # 연결 문제는 보관하지 않는다

    def test_stale_thumbnail_dropped_and_retry_allowed(self):
        calls = []
        det = {'song_id': '1', 'lyrics': '', 'image_url': 'u', 'reason': 'adult'}
        pending = []
        self.backend._thumb_pool = type('P', (), {'submit': lambda self, fn: pending.append(fn)})()
        with mock.patch.object(self.backend._scraper, 'get_song_detail', return_value=det), \
                mock.patch.object(self.backend._scraper, 'search_song', return_value=[]), \
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
