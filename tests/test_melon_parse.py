import os
import unittest

from src.utils.melon_api import parse_detail, parse_search

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

    def test_empty_and_limit(self):
        self.assertEqual(parse_search(''), [])
        self.assertEqual(parse_search('<p>없음</p>'), [])
        rows = ''.join(f'<tr><td><input class="input_check" value="{i}"></td></tr>' for i in range(15))
        self.assertEqual(len(parse_search(f'<table><tbody>{rows}</tbody></table>')), 10)


class ParseDetail(unittest.TestCase):
    def test_lyrics_and_image(self):
        lyrics, image = parse_detail(read('melon_detail.html'))
        self.assertEqual(lyrics, '첫째 줄\n둘째 줄\n\n셋째 줄')
        self.assertEqual(image, 'https://example.com/cover.jpg')

    def test_missing(self):
        self.assertEqual(parse_detail('<html></html>'), ('', ''))


if __name__ == '__main__':
    unittest.main()
