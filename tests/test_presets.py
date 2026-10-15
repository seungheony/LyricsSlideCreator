import json
import os
import tempfile
import unittest
from unittest import mock

from src.qml_ui.backend import Backend
from src.utils import presets


def entry(song_id='1', text='첫 줄\n둘째 줄\n\n셋째 줄', **kw):
    return dict({'song_id': song_id, 'title': '제목', 'artist': '가수', 'album': '앨범', 'text': text}, **kw)


class Pure(unittest.TestCase):
    def test_add_newest_first(self):
        items, added, same = presets.add([], [entry('1')], '2026-10-01T10:00:00')
        items, added, same = presets.add(items, [entry('1', '다른 구성')], '2026-10-08T10:00:00')
        self.assertEqual((added, same), (1, 0))
        self.assertEqual([p['text'] for p in presets.for_song(items, '1')], ['다른 구성', entry()['text']])
        self.assertEqual(presets.counts(items), {'1': 2})

    def test_same_text_only_moves_to_top(self):
        items, _, _ = presets.add([], [entry('1'), entry('1', 'B')], '2026-10-01T10:00:00')
        first_id = presets.for_song(items, '1')[1]['id']
        items, added, same = presets.add(items, [entry('1')], '2026-10-15T09:00:00')
        self.assertEqual((added, same), (0, 1))
        top = presets.for_song(items, '1')[0]
        self.assertEqual((top['id'], top['saved_at']), (first_id, '2026-10-15T09:00:00'))
        self.assertEqual(len(items), 2)

    def test_keeps_recent_per_song(self):
        items = []
        for i in range(presets.MAX_PER_SONG + 3):
            items, _, _ = presets.add(items, [entry('1', f'구성 {i}')], f'2026-10-{i + 1:02d}T00:00:00')
        items, _, _ = presets.add(items, [entry('2')], '2026-10-20T00:00:00')
        mine = presets.for_song(items, '1')
        self.assertEqual(len(mine), presets.MAX_PER_SONG)
        self.assertEqual(mine[0]['text'], f'구성 {presets.MAX_PER_SONG + 2}')
        self.assertEqual(len(presets.for_song(items, '2')), 1)

    def test_name_and_manual(self):
        items, _, _ = presets.add([], [entry('manual-x', manual=True)], 'now', '  주일   예배  ')
        self.assertEqual((items[0]['name'], items[0]['manual']), ('주일 예배', True))
        items, _, _ = presets.add([], [entry('1')], 'now')
        self.assertEqual((items[0]['name'], items[0]['manual']), ('', False))

    def test_same_text_takes_new_name(self):
        items, _, _ = presets.add([], [entry('1')], 'a', '처음')
        items, added, same = presets.add(items, [entry('1')], 'b', '청년부')
        self.assertEqual((added, same, len(items), items[0]['name']), (0, 1, 1, '청년부'))

    def test_skips_empty(self):
        items, added, _ = presets.add([], [entry('1', '  \n'), entry('', 'x')], 'now')
        self.assertEqual((items, added), ([], 0))

    def test_remove(self):
        items, _, _ = presets.add([], [entry('1'), entry('2')], 'now')
        items = presets.remove(items, presets.for_song(items, '1')[0]['id'])
        self.assertEqual(presets.counts(items), {'2': 1})


class SearchManual(unittest.TestCase):
    def setUp(self):
        self.items, _, _ = presets.add([], [
            entry('manual-a', '주 품에 품으소서\n능력의 주\n\n다음 줄', title='주 품에', artist='CCM', manual=True),
            entry('1', '주 품에 품으소서', title='주 품에', artist='멜론 가수'),      # 멜론 곡은 찾지 않는다
        ], 'now')
        # 같은 직접 입력 곡의 예전 프리셋: 결과는 곡마다 하나, 최근 것 기준
        self.items, _, _ = presets.add(self.items, [entry('manual-a', '옛 가사', title='옛 제목', manual=True)], 'old')
        self.items = self.items[1:] + self.items[:1]

    def test_title_and_artist_ignore_spaces_and_case(self):
        for key in ('주품에', ' 주 품 에 ', 'ccm'):
            with self.subTest(key):
                found = presets.search_manual(self.items, key, 'song')
                self.assertEqual([r['song_id'] for r in found], ['manual-a'])
                self.assertTrue(found[0]['manual'])
                self.assertEqual(found[0]['title'], '주 품에')

    def test_lyrics_snippet(self):
        found = presets.search_manual(self.items, '품으 소서', 'lyric')
        self.assertEqual(found[0]['snippet'], '주 품에 <b>품으소서</b>')
        # 줄을 넘어 걸쳐도 찾는다
        self.assertEqual(len(presets.search_manual(self.items, '품으소서 능력', 'lyric')), 1)
        self.assertEqual(presets.search_manual(self.items, '없는 가사', 'lyric'), [])
        self.assertEqual(presets.search_manual(self.items, '  ', 'lyric'), [])

    def test_snippet_is_escaped(self):
        items, _, _ = presets.add([], [entry('manual-b', '<i>노래</i> & 찬양', manual=True)], 'now')
        self.assertEqual(presets.search_manual(items, '찬양', 'lyric')[0]['snippet'], '&lt;i&gt;노래&lt;/i&gt; &amp; <b>찬양</b>')


class Storage(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.env = mock.patch.dict(os.environ, {'LSC_DATA_DIR': self.dir.name})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.dir.cleanup()

    def test_round_trip(self):
        items, _, _ = presets.add([], [entry('1')], 'now')
        self.assertTrue(presets.save(items))
        self.assertEqual(presets.load(), items)

    def test_broken_entries_are_dropped(self):
        with open(os.path.join(self.dir.name, presets.FILE_NAME), 'w', encoding='utf-8') as f:
            json.dump({'version': 1, 'presets': [{'song_id': '1'}, 'x', entry('2')]}, f)
        self.assertEqual([p['song_id'] for p in presets.load()], ['2'])

    def test_backend(self):
        backend = Backend(mock.Mock())
        changed = mock.Mock()
        backend.presetsChanged.connect(changed)
        res = json.loads(backend.savePresets(json.dumps([entry('1'), entry('2', 'A'), entry('manual-c', 'B', manual=True)]), '이름'))
        self.assertEqual(res, {'added': 3, 'same': 0})
        self.assertEqual(json.loads(backend.presetCounts()), {'1': 1, '2': 1, 'manual-c': 1})
        self.assertEqual(len(json.loads(backend.allPresets())), 3)
        self.assertEqual([r['song_id'] for r in json.loads(backend.searchManualPresets('제목', 'song'))], ['manual-c'])
        backend.shutdown()

        # 다시 켜도 남아 있다
        backend = Backend(mock.Mock())
        backend.presetsChanged.connect(changed)
        found = json.loads(backend.presetsFor('2'))
        self.assertEqual(found[0]['text'], 'A')
        self.assertTrue(backend.deletePreset(found[0]['id']))
        self.assertFalse(backend.deletePreset(found[0]['id']))
        self.assertEqual(json.loads(backend.presetCounts()), {'1': 1, 'manual-c': 1})
        self.assertEqual(changed.call_count, 2)
        backend.shutdown()

    def test_backend_save_failure(self):
        backend = Backend(mock.Mock())
        with mock.patch.object(presets, 'save', return_value=False):
            res = json.loads(backend.savePresets(json.dumps([entry('1')]), ''))
        self.assertIn('error', res)
        self.assertEqual(json.loads(backend.presetCounts()), {})
        backend.shutdown()


if __name__ == '__main__':
    unittest.main()
