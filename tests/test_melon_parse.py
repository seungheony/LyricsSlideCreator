import os
import unittest
from unittest import mock

import requests

from src.utils.melon_api import (MelonError, MelonScraper, parse_detail, parse_detail_status,
                                parse_lyric_search, parse_search, parse_search_total)

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixtures')


def read(name):
    with open(os.path.join(FIXTURES, name), encoding='utf-8') as f:
        return f.read()


class ParseSearch(unittest.TestCase):
    def test_results(self):
        results = parse_search(read('melon_search.html'))
        self.assertEqual(len(results), 2)   # 곡 번호가 없는 행은 건너뜀
        first = results[0]
        self.assertEqual(first['song_id'], '1001')
        # 속성 값을 쓰므로 <b> 조각으로 띄어쓰기가 사라지지 않고, NBSP는 공백 하나로 정리된다
        self.assertEqual(first['title'], '사 랑 할 때 -')
        self.assertEqual(first['artist'], '가수 A, 가수 B')
        self.assertEqual(first['album'], '테스트 앨범')

    def test_fallbacks(self):
        second = parse_search(read('melon_search.html'))[1]
        self.assertEqual(second['song_id'], '1002')   # goSongDetail 링크에서 추출
        self.assertEqual(second['title'], '두번째 곡')
        self.assertEqual(second['artist'], '아티스트 미상')
        self.assertEqual(second['album'], '앨범 미상')

    def test_empty_and_no_limit(self):
        self.assertEqual(parse_search(''), [])
        self.assertEqual(parse_search('<p>없음</p>'), [])
        rows = ''.join(f'<tr><td><input class="input_check" value="{i}"></td></tr>' for i in range(1, 51))
        self.assertEqual(len(parse_search(f'<table><tbody>{rows}</tbody></table>')), 50)   # 10개로 자르지 않는다

    def test_adult_badge_and_total(self):
        html = read('melon_search.html')
        first, second = parse_search(html)[:2]
        self.assertTrue(first['adult'])
        self.assertFalse(second['adult'])
        self.assertEqual(parse_search_total(html), 1234)
        self.assertIsNone(parse_search_total('<p>없음</p>'))


class ParseLyricSearch(unittest.TestCase):
    def test_results(self):
        html = read('melon_lyric.html')
        results = parse_lyric_search(html)
        self.assertEqual(len(results), 2)    # 곡 번호가 없는 항목은 건너뜀
        first = results[0]
        self.assertEqual((first['song_id'], first['title'], first['artist'], first['album']),
                         ('600297752', '사랑해 너를', '유해준', '사랑해 너를'))
        self.assertFalse(first['adult'])
        # 일치한 구절만 굵게
        self.assertEqual(first['snippet'], '내 맘이 말을 해 너라는 사람에게많이 좋아한다고 <b>사랑해 너를</b> 영원히 내가 모든 걸 다 주어도...')
        self.assertEqual(parse_search_total(html), 1000)

    def test_second_item(self):
        second = parse_lyric_search(read('melon_lyric.html'))[1]
        self.assertEqual(second['song_id'], '1137102')
        self.assertEqual(second['title'], '사랑해 & 너를')
        self.assertEqual(second['artist'], '야다 (Yada), 게스트')
        self.assertEqual(second['album'], '앨범 미상')
        self.assertTrue(second['adult'])
        # 멜론이 잘라 남긴 `<br...`는 지운다
        self.assertEqual(second['snippet'], '그댄 어디에도 없는데 <b>사랑해 너를</b> 너만을 사랑해 슬픈 사랑 하지 말자고 했던 ...')

    def test_snippet_is_escaped(self):
        html = ('<dl class="cntt_lyric"><dt><a class="btn_icon_detail" data-song-no="1" title="가 곡정보 - 페이지 이동"></a></dt>'
                '<dd class="lyric"><a>a &lt;i&gt;x&amp;y <b>z</b></a></dd></dl>')
        self.assertEqual(parse_lyric_search(html)[0]['snippet'], 'a &lt;i&gt;x&amp;y <b>z</b>')

    def test_cut_tags(self):
        html = ('<dl class="cntt_lyric"><dt><a class="btn_icon_detail" data-song-no="1"></a></dt>'
                '<dd class="lyric"><a>...BR&gt;나를 사랑해 준 너에게 <b>사랑해</b> 나만의&lt;BR...</a></dd></dl>')
        self.assertEqual(parse_lyric_search(html)[0]['snippet'], '... 나를 사랑해 준 너에게 <b>사랑해</b> 나만의...')

    def test_empty(self):
        self.assertEqual(parse_lyric_search(''), [])
        self.assertEqual(parse_lyric_search('<div class="section_no_data"></div>'), [])


class ParseDetail(unittest.TestCase):
    def test_lyrics_and_image(self):
        lyrics, image = parse_detail(read('melon_detail.html'))
        self.assertEqual(lyrics, '첫째 줄\n둘째 줄\n\n셋째 줄')
        self.assertEqual(image, 'https://example.com/cover.jpg')

    def test_missing(self):
        self.assertEqual(parse_detail('<html></html>'), ('', ''))

    def test_status_reasons(self):
        page = "<script>var lyricItemYN = '{}'; var adultFlg = '{}';</script>"
        self.assertIsNone(parse_detail_status('', '가사'))
        self.assertEqual(parse_detail_status(page.format('N', '0'), ''), 'no_lyrics')
        self.assertEqual(parse_detail_status(page.format('Y', '1'), ''), 'adult')
        self.assertEqual(parse_detail_status(page.format('Y', '0'), ''), 'parse')
        self.assertEqual(parse_detail_status('<html></html>', ''), 'not_found')


def response(text='', status=200):
    return mock.Mock(status_code=status, text=text)


class ScraperErrors(unittest.TestCase):
    def setUp(self):
        self.scraper = MelonScraper()

    def patch_get(self, **kwargs):
        return mock.patch.object(self.scraper.session, 'get', **kwargs)

    def test_network_error(self):
        with self.patch_get(side_effect=requests.ConnectionError()):
            with self.assertRaises(MelonError) as cm:
                self.scraper.search_song('사랑')
        self.assertEqual(cm.exception.kind, 'network')

    def test_http_error(self):
        with self.patch_get(return_value=response(status=503)):
            with self.assertRaises(MelonError) as cm:
                self.scraper.search_song('사랑')
        self.assertEqual((cm.exception.kind, cm.exception.status), ('http', 503))

    def test_parse_error_when_total_but_no_rows(self):
        html = '<strong class="serch_totcnt">총 <em>5</em>건</strong><table><tbody></tbody></table>'
        with self.patch_get(return_value=response(html)):
            with self.assertRaises(MelonError) as cm:
                self.scraper.search_song('사랑')
        self.assertEqual(cm.exception.kind, 'parse')

    def test_unknown_page_is_parse_error(self):
        with self.patch_get(return_value=response('<html>점검 중</html>')):
            with self.assertRaises(MelonError):
                self.scraper.search_song('사랑')

    def test_really_empty(self):
        html = '<strong class="serch_totcnt">총 <em>0</em>건</strong><div class="section_no_data"></div>'
        with self.patch_get(return_value=response(html)):
            self.assertEqual(self.scraper.search_song('없는곡'), {'results': [], 'total': 0})

    def test_search_urls(self):
        """첫 쪽은 검색 페이지, 다음 쪽은 멜론의 pageObj.sendPage와 같은 startIndex·pageSize 요청"""
        html = read('melon_search.html')
        with self.patch_get(return_value=response(html)) as get:
            first = self.scraper.search_song('사랑')
            self.scraper.search_song('사랑', 51)
            self.scraper.search_lyric('사랑해 너를', 16)
        self.assertEqual(first['total'], 1234)
        urls = [c.args[0] for c in get.call_args_list]
        self.assertTrue(urls[0].endswith('/search/song/index.htm?q=%EC%82%AC%EB%9E%91'))
        self.assertIn('startIndex=51&pageSize=50&q=%EC%82%AC%EB%9E%91', urls[1])
        self.assertIn('/search/lyric/index.htm?startIndex=16&pageSize=15&q=', urls[2])

    def test_later_page_empty_is_not_error(self):
        with self.patch_get(return_value=response('<table><tbody></tbody></table>')):
            self.assertEqual(self.scraper.search_song('사랑', 51), {'results': [], 'total': None})

    def test_lyric_search(self):
        with self.patch_get(return_value=response(read('melon_lyric.html'))):
            res = self.scraper.search_lyric('사랑해 너를')
        self.assertEqual((len(res['results']), res['total']), (2, 1000))

    def test_detail_reasons(self):
        with self.patch_get(side_effect=requests.Timeout()):
            self.assertEqual(self.scraper.get_song_detail('1')['reason'], 'network')
        with self.patch_get(return_value=response(status=403)):
            det = self.scraper.get_song_detail('1')
        self.assertEqual((det['reason'], det['status']), ('http', 403))
        with self.patch_get(return_value=response("<script>var lyricItemYN = 'Y'; var adultFlg = '1';</script>")):
            self.assertEqual(self.scraper.get_song_detail('1')['reason'], 'adult')
        with self.patch_get(return_value=response(read('melon_detail.html'))):
            det = self.scraper.get_song_detail('1')
        self.assertIsNone(det['reason'])
        self.assertEqual(det['lyrics'], '첫째 줄\n둘째 줄\n\n셋째 줄')


if __name__ == '__main__':
    unittest.main()
