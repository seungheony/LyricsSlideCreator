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

    def test_skips_empty(self):
        items, added, _ = presets.add([], [entry('1', '  \n'), entry('', 'x')], 'now')
        self.assertEqual((items, added), ([], 0))

    def test_remove(self):
        items, _, _ = presets.add([], [entry('1'), entry('2')], 'now')
        items = presets.remove(items, presets.for_song(items, '1')[0]['id'])
        self.assertEqual(presets.counts(items), {'2': 1})


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
        res = json.loads(backend.savePresets(json.dumps([entry('1'), entry('2', 'A')])))
        self.assertEqual(res, {'added': 2, 'same': 0})
        self.assertEqual(json.loads(backend.presetCounts()), {'1': 1, '2': 1})
        backend.shutdown()

        # 다시 켜도 남아 있다
        backend = Backend(mock.Mock())
        backend.presetsChanged.connect(changed)
        found = json.loads(backend.presetsFor('2'))
        self.assertEqual(found[0]['text'], 'A')
        self.assertTrue(backend.deletePreset(found[0]['id']))
        self.assertFalse(backend.deletePreset(found[0]['id']))
        self.assertEqual(json.loads(backend.presetCounts()), {'1': 1})
        self.assertEqual(changed.call_count, 2)
        backend.shutdown()

    def test_backend_save_failure(self):
        backend = Backend(mock.Mock())
        with mock.patch.object(presets, 'save', return_value=False):
            res = json.loads(backend.savePresets(json.dumps([entry('1')])))
        self.assertIn('error', res)
        self.assertEqual(json.loads(backend.presetCounts()), {})
        backend.shutdown()


if __name__ == '__main__':
    unittest.main()
