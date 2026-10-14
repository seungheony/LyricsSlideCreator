import requests
from bs4 import BeautifulSoup
import re
import urllib.parse

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

            if song_id:
                results.append({'song_id': song_id, 'title': title, 'artist': artist, 'album': album})
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


def _parse_image_url(soup):
    img_tag = soup.select_one('.thumb img')
    return img_tag['src'] if img_tag else ""


class MelonScraper:
    def __init__(self):
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.melon.com/index.htm'
        }

    def search_song(self, keyword):
        if not keyword: return []
        try:
            encoded_keyword = urllib.parse.quote(keyword)
            search_url = f"https://www.melon.com/search/song/index.htm?q={encoded_keyword}"
            response = requests.get(search_url, headers=self.headers, timeout=10)
            if response.status_code != 200: return []
            return parse_search(response.text)
        except Exception: return []

    def get_song_detail(self, song_id):
        if not song_id: return None
        try:
            url = f"https://www.melon.com/song/detail.htm?songId={song_id}"
            response = requests.get(url, headers=self.headers, timeout=10)
            lyrics, image_url = parse_detail(response.text)
            return {'song_id': song_id, 'lyrics': lyrics, 'image_url': image_url}
        except Exception: return None

    def get_album_image_url(self, song_id):
        """곡 상세 페이지에서 앨범아트 URL만 가져온다."""
        if not song_id: return ''
        try:
            url = f"https://www.melon.com/song/detail.htm?songId={song_id}"
            response = requests.get(url, headers=self.headers, timeout=10)
            return parse_detail(response.text)[1]
        except Exception:
            return ''
