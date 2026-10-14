"""editor.js(슬라이드 모델 순수 로직)를 QJSEngine에 불러 시험한다."""
import json
import os
import unittest

from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EDITOR_JS = os.path.join(ROOT, 'src', 'qml_ui', 'qml', 'editor.js')


def load_engine():
    with open(EDITOR_JS, encoding='utf-8') as f:
        code = f.read().replace('.pragma library', '', 1)
    engine = QJSEngine()
    result = engine.evaluate(code, EDITOR_JS)
    assert not result.isError(), result.toString()
    return engine


class EditorJs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = load_engine()

    def call(self, expr):
        """JS 식을 실행해 JSON으로 되돌린다. (null은 None)"""
        r = self.engine.evaluate(f'JSON.stringify({expr})')
        self.assertFalse(r.isError(), r.toString())
        return json.loads(r.toString()) if not r.isUndefined() else None

    @staticmethod
    def blocks(*groups):
        return [{'lines': list(g)} for g in groups]

    def drop(self, groups, src, target, keep):
        b = json.dumps(self.blocks(*groups), ensure_ascii=False)
        return self.call(f'planDrop({b}, {json.dumps(src)}, {json.dumps(target)}, {str(keep).lower()})')

    # ── parseBlocks ──
    def test_parse_blocks_positions(self):
        text = '가\n나\n\n다'
        self.assertEqual(self.call(f'parseBlocks({json.dumps(text)})'),
                         [{'start': 0, 'end': 3, 'lines': ['가', '나']},
                          {'start': 5, 'end': 6, 'lines': ['다']}])

    def test_parse_blocks_blank_lines_and_trim(self):
        text = '\n\n  가  \n\n\n\n 나 \n\n'
        got = self.call(f'parseBlocks({json.dumps(text)})')
        self.assertEqual([b['lines'] for b in got], [['가'], ['나']])
        self.assertEqual(self.call('parseBlocks("")'), [])
        self.assertEqual(self.call('parseBlocks("  \\n \\n")'), [])

    def test_parse_blocks_crlf(self):
        # \r은 trim으로 사라지고, 위치는 원문 기준(\r 포함)
        got = self.call('parseBlocks("가\\r\\n나\\r\\n\\r\\n다")')
        self.assertEqual([b['lines'] for b in got], [['가', '나'], ['다']])
        self.assertEqual(got[1]['start'], 8)

    def test_parse_blocks_nbsp_only_line_is_blank(self):
        got = self.call('parseBlocks("가\\n\\u00a0\\n나")')
        self.assertEqual([b['lines'] for b in got], [['가'], ['나']])

    # ── serialize / regroup ──
    def test_serialize_roundtrip(self):
        text = '가\n나\n\n다\n라'
        self.assertEqual(self.call(f'serialize(linesOf(parseBlocks({json.dumps(text)})))'), text)

    def test_regroup(self):
        self.assertEqual(self.call('regroup(["a","b","c","d","e"], 2)'), [['a', 'b'], ['c', 'd'], ['e']])
        self.assertEqual(self.call('regroup(["a","b","c"], 1)'), [['a'], ['b'], ['c']])
        self.assertEqual(self.call('regroup([], 2)'), [])

    def test_all_lines(self):
        self.assertEqual(self.call('allLines(parseBlocks("a\\nb\\n\\nc"))'), ['a', 'b', 'c'])

    # ── blockIndexAt ──
    def test_block_index_at(self):
        text = '가\n나\n\n다'   # 블록 0: 0~3, 블록 1: 5~6
        b = f'parseBlocks({json.dumps(text)})'
        self.assertEqual(self.call(f'blockIndexAt({b}, 0)'), 0)
        self.assertEqual(self.call(f'blockIndexAt({b}, 3)'), 0)
        self.assertEqual(self.call(f'blockIndexAt({b}, 4)'), 1)   # 빈 줄 → 다음 슬라이드
        self.assertEqual(self.call(f'blockIndexAt({b}, 99)'), 1)  # 끝 너머 → 마지막

    # ── resolveDrop ──
    def resolve(self, groups, src, target):
        b = json.dumps(self.blocks(*groups), ensure_ascii=False)
        return self.call(f'resolveDrop({b}, {json.dumps(src)}, {json.dumps(target)})')

    def test_resolve_drop_allowed(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # 첫 줄 → 앞 슬라이드 끝
        self.assertEqual(self.resolve(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 1}),
                         {'type': 'line', 'slide': 0, 'at': 2})
        # 마지막 줄 → 뒤 슬라이드 처음
        self.assertEqual(self.resolve(g, {'slide': 1, 'line': 1}, {'type': 'line', 'slide': 2, 'at': 1}),
                         {'type': 'line', 'slide': 2, 'at': 0})
        # 첫 줄 → 앞쪽 새 슬라이드
        self.assertEqual(self.resolve(g, {'slide': 1, 'line': 0}, {'type': 'new', 'at': 1}),
                         {'type': 'new', 'at': 1})
        # 마지막 줄 → 뒤쪽 새 슬라이드
        self.assertEqual(self.resolve(g, {'slide': 1, 'line': 1}, {'type': 'new', 'at': 2}),
                         {'type': 'new', 'at': 2})

    def test_resolve_drop_rejected(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # 마지막 줄을 앞 슬라이드로 / 첫 줄을 뒤 슬라이드로
        self.assertIsNone(self.resolve(g, {'slide': 1, 'line': 1}, {'type': 'line', 'slide': 0, 'at': 0}))
        self.assertIsNone(self.resolve(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 2, 'at': 0}))
        # 멀리 있는 슬라이드, 같은 슬라이드
        self.assertIsNone(self.resolve(g, {'slide': 0, 'line': 1}, {'type': 'line', 'slide': 2, 'at': 0}))
        self.assertIsNone(self.resolve(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 1, 'at': 0}))
        # 가운데 줄(3줄 슬라이드)은 어디로도 못 감
        g3 = [['a'], ['b', 'c', 'd'], ['e']]
        self.assertIsNone(self.resolve(g3, {'slide': 1, 'line': 1}, {'type': 'line', 'slide': 0, 'at': 1}))
        self.assertIsNone(self.resolve(g, {'slide': 1, 'line': 1}, {'type': 'new', 'at': 1}))
        self.assertIsNone(self.resolve(g, {'slide': 1, 'line': 0}, None))

    def test_resolve_drop_single_line_slide_allows_all_four(self):
        g = [['a', 'b'], ['c'], ['e', 'f']]
        s = {'slide': 1, 'line': 0}
        self.assertIsNotNone(self.resolve(g, s, {'type': 'line', 'slide': 0, 'at': 0}))
        self.assertIsNotNone(self.resolve(g, s, {'type': 'line', 'slide': 2, 'at': 0}))
        self.assertIsNotNone(self.resolve(g, s, {'type': 'new', 'at': 1}))
        self.assertIsNotNone(self.resolve(g, s, {'type': 'new', 'at': 2}))

    # ── planDrop ──
    def test_plan_drop_keep_off(self):
        g = [['a', 'b'], ['c', 'd']]
        # c를 앞 슬라이드 끝으로: 3줄이 돼도 그대로
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}, False)
        self.assertEqual(plan, {'groups': [['a', 'b', 'c'], ['d']], 'focus': 0})
        # b를 뒤 슬라이드 처음으로
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'line', 'slide': 1, 'at': 0}, False)
        self.assertEqual(plan, {'groups': [['a'], ['b', 'c', 'd']], 'focus': 1})

    def test_plan_drop_keep_off_new_slide_and_empty_source(self):
        g = [['a', 'b'], ['c']]
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}, False)
        self.assertEqual(plan, {'groups': [['a', 'b', 'c']], 'focus': 0})   # 빈 슬라이드는 사라짐
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'new', 'at': 1}, False)
        self.assertEqual(plan, {'groups': [['a'], ['b'], ['c']], 'focus': 1})

    def test_plan_drop_keep_two_cascades_and_preserves_lines(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # c를 앞으로: [a,b,c] 넘침 → a가 맨 앞 새 슬라이드, 소스는 뒤에서 e를 당겨 채움 → f는 혼자
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}, True)
        self.assertEqual(plan['groups'], [['a'], ['b', 'c'], ['d', 'e'], ['f']])
        self.assertEqual(plan['focus'], 1)
        flat = [x for grp in plan['groups'] for x in grp]
        self.assertEqual(flat, ['a', 'b', 'c', 'd', 'e', 'f'])   # 줄 수·순서 보존
        self.assertTrue(all(len(grp) <= 2 for grp in plan['groups']))

    def test_plan_drop_keep_two_forward(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # b를 뒤로: [b,c,d] 넘침 → d가 다음으로 → ... 마지막은 새 슬라이드
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'line', 'slide': 1, 'at': 0}, True)
        flat = [x for grp in plan['groups'] for x in grp]
        self.assertEqual(flat, ['a', 'b', 'c', 'd', 'e', 'f'])
        self.assertTrue(all(len(grp) <= 2 for grp in plan['groups']))
        self.assertIn('b', plan['groups'][plan['focus']])

    def test_plan_drop_focus_with_repeated_lines(self):
        # 같은 가사 줄이 반복돼도 옮긴 줄이 들어간 슬라이드를 가리킨다
        g = [['x', 'x'], ['x', 'y']]
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}, False)
        self.assertEqual(plan, {'groups': [['x', 'x', 'x'], ['y']], 'focus': 0})
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'line', 'slide': 1, 'at': 0}, False)
        self.assertEqual(plan, {'groups': [['x'], ['x', 'x', 'y']], 'focus': 1})

    def test_plan_drop_no_change_is_null(self):
        # 한 줄짜리 슬라이드 둘을 붙였다 뗄 때처럼 결과가 같으면 null
        g = [['a']]
        self.assertIsNone(self.drop(g, {'slide': 0, 'line': 0}, {'type': 'new', 'at': 0}, False))


if __name__ == '__main__':
    unittest.main()
