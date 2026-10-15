"""저장한 곡 구성(프리셋): 예전에 만든 슬라이드 구성 그대로 곡을 다시 연다.

편집기는 곡마다 가사 텍스트가 유일한 원본(빈 줄로 나뉜 덩어리가 슬라이드 한 장)이므로 구성 = 그 텍스트다.
멜론 곡 번호(song_id)로 검색 결과와 잇는다. 앨범아트는 저장하지 않고 곡 번호로 다시 받는다.
파일: 앱 데이터 폴더의 presets.json (src/utils/app_state.py) — {"version": 1, "presets": [...]}
  프리셋: {id, song_id, title, artist, album, text, saved_at('YYYY-MM-DDTHH:MM:SS', 이 컴퓨터 시각)}
"""
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


def add(presets, entries, now):
    """곡 구성들을 더한다. entries: [{song_id, title, artist, album, text}], now: saved_at 문자열.
    같은 곡에 같은 텍스트가 이미 있으면 새로 만들지 않고 저장 시각만 바꾼다.
    반환: (새 목록, 새로 저장한 수, 이미 있던 수). 목록은 최근 저장한 것이 앞"""
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
            'title': e.get('title') or '',
            'artist': e.get('artist') or '',
            'album': e.get('album') or '',
            'text': text,
            'saved_at': now,
        })
        # 곡마다 최근 MAX_PER_SONG개만 남긴다
        mine = [p for p in result if p['song_id'] == song_id]
        for p in mine[MAX_PER_SONG:]:
            result.remove(p)
    return result, added, same


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
