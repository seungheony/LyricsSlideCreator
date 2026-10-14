import requests
from bs4 import BeautifulSoup
import html as html_lib
import re
import urllib.parse

SONG_PAGE_SIZE = 50      # 멜론 곡 검색이 한 번에 주는 행 수
LYRIC_PAGE_SIZE = 15     # 멜론 가사 검색이 한 번에 주는 행 수


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
    """검색 결과 HTML에서 곡 목록(받은 행 전부)을 뽑는다."""
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
    return results


def _clean_snippet(text):
    """가사 검색 미리보기 정리. 멜론이 줄바꿈 태그를 글자로 남기거나(`<br...`) 중간에 자르므로 지운다"""
    text = re.sub(r'<br\s*/?>', ' ', text, flags=re.I)
    text = re.sub(r'<b?r?\s*/?>?(?=\.{3}$)', '', text.strip(), flags=re.I)
    text = re.sub(r'^(\.{3})\s*b?r?\s*/?>', r'\1 ', text, flags=re.I)    # 앞쪽이 태그 중간에서 잘린 경우
    return ' '.join(text.split())


def parse_lyric_search(html):
    """가사 검색 결과 HTML에서 곡 목록을 뽑는다.

    각 항목: song_id, title, artist, album, adult, snippet(일치한 가사 일부, 일치 구절만 <b>로 감싼 안전한 HTML)
    """
    soup = BeautifulSoup(html, 'html.parser')
    results = []
    for dl in soup.select('dl.cntt_lyric'):
        try:
            detail = dl.select_one('a.btn_icon_detail[data-song-no]')
            song_id = detail.get('data-song-no', '').strip() if detail else ''
            if not song_id:
                continue
            title = ' '.join(((detail.get('title') or detail.get_text()) or '').split())
            title = title.replace('곡정보 - 페이지 이동', '').strip()

            artists = [' '.join(a.get_text().split()) for a in dl.select('dd.info .atist > a')]
            artist = ', '.join(a for a in artists if a) or "아티스트 미상"

            album_link = dl.select_one('dd.info .album a')
            album = ' '.join((album_link.get('title', '') if album_link else '').split())
            album = album.replace(' - 페이지 이동', '').strip() or "앨범 미상"

            snippet = ''
            lyric_link = dl.select_one('dd.lyric a')
            if lyric_link:
                # 일치한 구절을 표시(\x01~\x02)해 두고, 나머지는 이스케이프한 뒤 <b>로 바꾼다
                # (QML StyledText에 그대로 넣어도 안전하게)
                raw = ''.join(f'\x01{c.get_text()}\x02' if getattr(c, 'name', None) == 'b' else c.get_text()
                              for c in lyric_link.children)
                snippet = html_lib.escape(_clean_snippet(raw), quote=False).replace('\x01', '<b>').replace('\x02', '</b>')

            adult = dl.select_one('[class*="age_19"]') is not None
            results.append({'song_id': song_id, 'title': title, 'artist': artist, 'album': album,
                            'adult': adult, 'snippet': snippet})
        except Exception:
            continue
    return results


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

    def _search(self, kind, keyword, start, parse, page_size, params):
        """검색 한 쪽. 반환: {results, total}. 실패하면 MelonError (결과가 정말 없을 때만 빈 목록)

        첫 쪽(start=1)은 검색 페이지 그대로, 그다음 쪽은 멜론 페이지의 '다음' 링크(pageObj.sendPage)가
        부르는 것과 같은 요청(startIndex·pageSize와 정렬 매개변수)으로 목록 조각만 받는다. 조각에는 총 건수가 없다.
        """
        q = urllib.parse.quote(keyword)
        if start <= 1:
            html = self._get(f"https://www.melon.com/search/{kind}/index.htm?q={q}")
        else:
            extra = ''.join(f'&{k}={v}' for k, v in params.items())
            html = self._get(f"https://www.melon.com/search/{kind}/index.htm"
                             f"?startIndex={start}&pageSize={page_size}&q={q}{extra}")
        results = parse(html)
        total = parse_search_total(html)
        if not results and start <= 1:
            if total is None and 'section_no_data' not in html:
                raise MelonError('parse')    # 결과 영역도 '없음' 표시도 없음: 페이지 구조가 바뀜
            if total:
                raise MelonError('parse')    # 총 건수는 있는데 행을 못 읽음
        return {'results': results, 'total': total}

    def search_song(self, keyword, start=1):
        """곡 검색(제목·가수). start는 1부터 세는 시작 위치(다음 쪽은 앞서 받은 개수 + 1)"""
        if not keyword:
            return {'results': [], 'total': 0}
        return self._search('song', keyword, start, parse_search, SONG_PAGE_SIZE,
                            {'sort': 'hit', 'section': 'all', 'sectionId': '', 'genreDir': ''})

    def search_lyric(self, keyword, start=1):
        """가사 검색(가사에 이 구절이 있는 곡). 항목에 일치한 가사 일부(snippet)가 붙는다"""
        if not keyword:
            return {'results': [], 'total': 0}
        return self._search('lyric', keyword, start, parse_lyric_search, LYRIC_PAGE_SIZE,
                            {'sort': 'weight', 'section': ''})

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
