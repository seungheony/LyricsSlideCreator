import requests
from bs4 import BeautifulSoup
import re
import urllib.parse


class MelonError(Exception):
    """멜론 요청 실패. kind: 'network'(연결 안 됨·시간 초과), 'http'(응답 코드가 정상이 아님), 'parse'(받았지만 읽지 못함)"""

    def __init__(self, kind, status=None):
        super().__init__(f'{kind} {status}' if status else kind)
        self.kind = kind
        self.status = status


def parse_search_total(html):
    """검색 페이지에 적힌 곡 총 건수. 못 찾으면 None"""
    m = re.search(r'serch_totcnt[^>]*>\s*총\s*<em>\s*([\d,]+)\s*</em>', html)
    return int(m.group(1).replace(',', '')) if m else None

def parse_search(html):
    """검색 결과 HTML에서 곡 목록(최대 10개)을 뽑는다."""
    soup = BeautifulSoup(html, 'html.parser')
    results = []
    rows = soup.select('table > tbody > tr')

    for row in rows:
        try:
            # 멜론은 검색어를 <b>로 감싸 텍스트 조각을 이으면 띄어쓰기가 사라진다.
            # 그래서 조각 대신 속성 값(value/title)을 쓰고 NBSP 등은 공백 하나로 정리한다.
            check = row.select_one('input.input_check')
            song_id = check.get('value', '') if check else ''
            if not song_id:
                song_link = row.select_one('a[href*="goSongDetail"]')
                m = re.search(r"goSongDetail\('(\d+)'\)", song_link['href']) if song_link else None
                song_id = m.group(1) if m else ''

            title_link = row.select_one('a.fc_gray')
            title = ' '.join(((title_link.get('title') or title_link.get_text()) if title_link else '').split())
            title = title.replace('상세정보 페이지 이동', '').strip()

            artists = [' '.join(a.get_text().split()) for a in row.select('#artistName > a')]
            artist = ', '.join(a for a in artists if a) or "아티스트 미상"

            album_link = row.select_one('a[href*="goAlbumDetail"]')
            album = ' '.join((album_link.get('title', '') if album_link else '').split())
            album = album.replace(' - 페이지 이동', '').strip() or "앨범 미상"

            adult = row.select_one('[class*="age_19"]') is not None

            if song_id:
                results.append({'song_id': song_id, 'title': title, 'artist': artist, 'album': album, 'adult': adult})
        except Exception:
            continue
    return results[:10]


def parse_detail(html):
    """곡 상세 HTML에서 가사와 앨범아트 URL을 뽑는다. 반환: (lyrics, image_url)"""
    soup = BeautifulSoup(html, 'html.parser')

    lyrics_div = soup.select_one('div.lyric')
    lyrics = ""
    if lyrics_div:
        for br in lyrics_div.find_all("br"): br.replace_with("\n")
        lyrics = lyrics_div.get_text().strip()

    return lyrics, _parse_image_url(soup)


def parse_detail_status(html, lyrics):
    """상세 페이지에서 가사를 못 얻은 원인. 가사가 있으면 None.

    'adult'(19금: 성인 인증을 해야 가사가 나옴), 'no_lyrics'(가사 미등록),
    'not_found'(없거나 비공개인 곡), 'parse'(가사가 있다는데 못 읽음 — 멜론 구조가 바뀐 듯)
    """
    if lyrics:
        return None
    lyric_yn = re.search(r"lyricItemYN\s*=\s*'(\w*)'", html)
    adult = re.search(r"adultFlg\s*=\s*'(\w*)'", html)
    if not lyric_yn:
        return 'not_found'
    if lyric_yn.group(1) == 'N':
        return 'no_lyrics'
    if adult and adult.group(1) == '1':
        return 'adult'
    return 'parse'


def _parse_image_url(soup):
    img_tag = soup.select_one('.thumb img')
    return img_tag['src'] if img_tag else ""


class MelonScraper:
    def __init__(self):
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.melon.com/index.htm'
        }
        # 연결을 재사용한다 (스레드 풀에서 함께 쓰므로 풀 크기를 넉넉히)
        self.session = requests.Session()
        self.session.headers.update(self.headers)
        adapter = requests.adapters.HTTPAdapter(pool_connections=4, pool_maxsize=12)
        self.session.mount('https://', adapter)

    def _get(self, url):
        """GET 한 번. 연결 실패와 정상이 아닌 응답 코드를 MelonError로 바꾼다"""
        try:
            response = self.session.get(url, timeout=10)
        except requests.RequestException as e:
            raise MelonError('network') from e
        if response.status_code != 200:
            raise MelonError('http', response.status_code)
        return response.text

    def get(self, url, **kwargs):
        """이미지 등 다른 주소도 같은 연결·헤더로 받는다. 실패하면 requests 예외"""
        return self.session.get(url, timeout=10, **kwargs)

    def search_song(self, keyword):
        """곡 검색. 실패하면 MelonError (결과가 정말 없을 때만 빈 목록)"""
        if not keyword:
            return []
        html = self._get(f"https://www.melon.com/search/song/index.htm?q={urllib.parse.quote(keyword)}")
        results = parse_search(html)
        if not results:
            total = parse_search_total(html)
            if total is None and 'section_no_data' not in html:
                raise MelonError('parse')    # 결과 영역도 '없음' 표시도 없음: 페이지 구조가 바뀜
            if total:
                raise MelonError('parse')    # 총 건수는 있는데 행을 못 읽음
        return results

    def get_song_detail(self, song_id):
        """곡 상세. 반환: {song_id, lyrics, image_url, reason}. reason은 가사를 못 얻은 원인
        (parse_detail_status의 값, 또는 연결 문제면 'network'/'http'), 가사가 있으면 None"""
        if not song_id:
            return {'song_id': song_id, 'lyrics': '', 'image_url': '', 'reason': 'not_found'}
        try:
            html = self._get(f"https://www.melon.com/song/detail.htm?songId={song_id}")
        except MelonError as e:
            return {'song_id': song_id, 'lyrics': '', 'image_url': '', 'reason': e.kind, 'status': e.status}
        lyrics, image_url = parse_detail(html)
        return {'song_id': song_id, 'lyrics': lyrics, 'image_url': image_url,
                'reason': parse_detail_status(html, lyrics)}
