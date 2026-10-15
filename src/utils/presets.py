"""프리셋: 예전에 만든 슬라이드 구성 그대로 곡을 다시 연다.

편집기는 곡마다 가사 텍스트가 유일한 원본(빈 줄로 나뉜 덩어리가 슬라이드 한 장)이므로 프리셋 = 그 텍스트다.
멜론 곡은 곡 번호(song_id)로 검색 결과와 잇는다. 앨범아트는 저장하지 않고 곡 번호로 다시 받는다.
직접 입력한 곡(manual)은 멜론에 없으므로 앱 안에서 제목·가수·가사로 찾는다(search_manual). song_id는 'manual-'로
시작하는 고유한 값이라(Main.qml manualId) 같은 곡을 다시 저장하면 같은 곡으로 묶인다.
파일: 앱 데이터 폴더의 presets.json (src/utils/app_state.py) — {"version": 1, "presets": [...]}
  프리셋: {id, song_id, name, title, artist, album, manual, image_url, text, saved_at('YYYY-MM-DDTHH:MM:SS', 이 컴퓨터 시각)}
  image_url: 멜론 앨범아트 주소 (저장할 때 알고 있으면). 보관함이 곡 상세 페이지를 거치지 않고 그림만 받는다
  name이 없는 프리셋(v1.4-beta.1)은 화면에서 저장한 날짜로 보인다
"""
import html
import re
import uuid

from src.utils import app_state

FILE_NAME = 'presets.json'
MAX_PER_SONG = 10       # 곡마다 최근 것만 남긴다


def load():
    data = app_state.read_json(app_state.data_path(FILE_NAME))
    items = data.get('presets')
    if not isinstance(items, list):
        return []
    return [p for p in items if isinstance(p, dict) and p.get('song_id') and isinstance(p.get('text'), str)]


def save(presets):
    return app_state.write_json(app_state.data_path(FILE_NAME), {'version': 1, 'presets': presets})


def add(presets, entries, now, name=''):
    """프리셋들을 더한다. entries: [{song_id, title, artist, album, manual, text}], now: saved_at 문자열,
    name: 프리셋 이름 (한 번에 저장하는 곡 모두에 붙는다).
    같은 곡에 같은 텍스트가 이미 있으면 새로 만들지 않고 이름·저장 시각만 바꾼다.
    반환: (새 목록, 새로 저장한 수, 이미 있던 수). 목록은 최근 저장한 것이 앞"""
    name = ' '.join((name or '').split())[:60]
    result = list(presets)
    added = same = 0
    for e in entries:
        song_id, text = str(e.get('song_id') or ''), e.get('text') or ''
        if not song_id or not text.strip():
            continue
        old = next((p for p in result if p['song_id'] == song_id and p['text'] == text), None)
        if old:
            result.remove(old)
            same += 1
        else:
            added += 1
        result.insert(0, {
            'id': old['id'] if old else uuid.uuid4().hex[:12],
            'song_id': song_id,
            'name': name,
            'title': e.get('title') or '',
            'artist': e.get('artist') or '',
            'album': e.get('album') or '',
            'manual': e.get('manual') is True,
            'image_url': e.get('image_url') or (old or {}).get('image_url') or '',
            'text': text,
            'saved_at': now,
        })
        # 곡마다 최근 MAX_PER_SONG개만 남긴다
        mine = [p for p in result if p['song_id'] == song_id]
        for p in mine[MAX_PER_SONG:]:
            result.remove(p)
    return result, added, same


def rename(presets, preset_id, name):
    """이름을 바꾼다. 반환: 새 목록 (그런 프리셋이 없으면 None)"""
    if not any(p.get('id') == preset_id for p in presets):
        return None
    name = ' '.join((name or '').split())[:60]
    return [dict(p, name=name) if p.get('id') == preset_id else p for p in presets]


def remove(presets, preset_id):
    return [p for p in presets if p.get('id') != preset_id]


def for_song(presets, song_id):
    """그 곡의 구성 (최근 저장한 것부터)"""
    return [p for p in presets if p['song_id'] == song_id]


def counts(presets):
    """곡 번호 → 저장한 구성 수"""
    out = {}
    for p in presets:
        out[p['song_id']] = out.get(p['song_id'], 0) + 1
    return out


def _squash(text):
    """비교용: 공백을 모두 빼고 소문자로 ('주 품에' = '주품에')"""
    return re.sub(r'\s+', '', text or '').lower()


def search_manual(presets, keyword, mode='song'):
    """직접 입력한 곡 중 검색어에 맞는 곡 (검색 결과 맨 위에 붙인다).
    mode 'song': 제목·가수, 'lyric': 가사. 공백·대소문자는 무시한다. 곡마다 가장 최근 프리셋 기준으로 하나씩.
    반환: [{song_id, title, artist, album, manual: True, snippet}] (snippet: 가사 검색에서 일치한 줄, 일치한 부분만 <b>,
    멜론 가사 검색 결과와 같은 이스케이프된 HTML)"""
    key = _squash(keyword)
    if not key:
        return []
    out = []
    seen = set()
    for p in presets:
        if not p.get('manual') or p['song_id'] in seen:
            continue
        seen.add(p['song_id'])
        snippet = ''
        if mode == 'lyric':
            if key not in _squash(p['text']):
                continue
            snippet = _snippet(p['text'], keyword)
        elif key not in _squash(p.get('title', '') + p.get('artist', '')):
            continue
        out.append({'song_id': p['song_id'], 'title': p.get('title') or '', 'artist': p.get('artist') or '',
                    'album': '', 'manual': True, 'snippet': snippet})
    return out


def _snippet(text, keyword):
    """검색어가 들어간 줄 (한 줄 안에서 찾으면 그 부분을 굵게). 줄을 넘어 걸치면 시작하는 줄"""
    key = _squash(keyword)
    pattern = re.compile(r'\s*'.join(map(re.escape, key)), re.I)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines:
        m = pattern.search(line)
        if m:
            return html.escape(line[:m.start()]) + '<b>' + html.escape(m.group(0)) + '</b>' + html.escape(line[m.end():])
    joined = ' '.join(lines)
    m = pattern.search(joined)
    return html.escape(joined[max(0, m.start() - 20):m.end() + 20]) if m else ''
