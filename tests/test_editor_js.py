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
        self.assertEqual(self.call(f'blockIndexAt({b}, 4)'), 0)   # 바로 다음 빈 줄(Enter 직후) → 아직 그 슬라이드
        self.assertEqual(self.call(f'blockIndexAt({b}, 5)'), 1)
        self.assertEqual(self.call(f'blockIndexAt({b}, 99)'), 1)  # 끝 너머 → 마지막

    def test_block_index_at_blank_lines_between(self):
        text = '가\n\n\n다'   # 블록 0: 0~1, 빈 줄 2·3, 블록 1: 4~5
        b = f'parseBlocks({json.dumps(text)})'
        self.assertEqual(self.call(f'blockIndexAt({b}, 2)'), 0)
        self.assertEqual(self.call(f'blockIndexAt({b}, 3)'), 1)

    # ── sameLines ──
    def test_same_lines_ignores_positions(self):
        self.assertTrue(self.call('sameLines(parseBlocks("가\\n나"), parseBlocks("\\n 가\\n나 "))'))
        self.assertFalse(self.call('sameLines(parseBlocks("가\\n나"), parseBlocks("가\\n\\n나"))'))
        self.assertFalse(self.call('sameLines(parseBlocks("가\\n나"), parseBlocks("가\\n다"))'))
        self.assertTrue(self.call('sameLines([], [])'))

    # ── lineEnd ──
    def line_end(self, text, slide, line):
        return self.call(f'lineEnd({json.dumps(text)}, parseBlocks({json.dumps(text)})[{slide}], {line})')

    def test_line_end(self):
        text = '가나\n다라  \n\n마바'
        self.assertEqual(self.line_end(text, 0, 0), 2)
        self.assertEqual(self.line_end(text, 0, 1), 5)    # 뒤 공백 앞
        self.assertEqual(self.line_end(text, 1, 0), 11)
        self.assertEqual(self.line_end(text, 1, 5), 11)   # 없는 줄 → 슬라이드 끝

    # ── textDiff ──
    def apply_diff(self, before, after):
        d = self.call(f'textDiff({json.dumps(before)}, {json.dumps(after)})')
        if d is None:
            return before, None
        # JS 위치는 UTF-16 단위다
        u = before.encode('utf-16-le')
        got = u[:2 * d['start']] + d['insert'].encode('utf-16-le') + u[2 * d['end']:]
        return got.decode('utf-16-le'), d

    def test_text_diff_minimal_range(self):
        before = 'a\nb\n\nc\nd'
        after = 'a\n\nb\n\nc\nd'          # 1번 슬라이드 나누기
        got, d = self.apply_diff(before, after)
        self.assertEqual(got, after)
        self.assertEqual(d['end'] - d['start'], 0)   # 지우는 것 없이 \n 하나만 넣는다
        self.assertEqual(d['insert'], '\n')
        self.assertIsNone(self.call('textDiff("같다", "같다")'))

    def test_text_diff_roundtrips(self):
        cases = [('', 'abc'), ('abc', ''), ('aaa', 'aa'), ('abcabc', 'abc'), ('x\ny', 'x\n\ny'),
                 ('가나다', '가다'), ('a😀b', 'a😁b'), ('😀', '😀😀'), ('a\n\nb\n\nc', 'a\n\nc')]
        for before, after in cases:
            with self.subTest(before=before, after=after):
                self.assertEqual(self.apply_diff(before, after)[0], after)

    def test_text_diff_keeps_surrogate_pairs(self):
        # 이모지(서로게이트 쌍) 가운데서 자르지 않는다 (UTF-16 단위 위치)
        _, d = self.apply_diff('a😀b', 'a😁b')
        self.assertEqual(d['start'], 1)
        self.assertEqual(d['end'], 3)

    # ── listDiff ──
    def test_list_diff(self):
        self.assertIsNone(self.call('listDiff(["a","b"], ["a","b"])'))
        self.assertEqual(self.call('listDiff(["a","b","c"], ["a","x","c"])'), {'from': 1, 'oldEnd': 2, 'newEnd': 2})
        self.assertEqual(self.call('listDiff(["a","c"], ["a","b","c"])'), {'from': 1, 'oldEnd': 1, 'newEnd': 2})
        self.assertEqual(self.call('listDiff(["a","b","c"], ["a","c"])'), {'from': 1, 'oldEnd': 2, 'newEnd': 1})
        self.assertEqual(self.call('listDiff([], ["a"])'), {'from': 0, 'oldEnd': 0, 'newEnd': 1})
        # 반복되는 항목: 앞뒤가 겹치지 않게
        self.assertEqual(self.call('listDiff(["a","a"], ["a","a","a"])'), {'from': 2, 'oldEnd': 2, 'newEnd': 3})

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

    def test_plan_drop_keep_two_pushes_backward(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # c를 앞으로: [a,b,c] 넘침 → a가 맨 앞 새 슬라이드. 줄을 준 슬라이드는 d 혼자 남는다 (당겨 채우지 않음)
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}, True)
        self.assertEqual(plan, {'groups': [['a'], ['b', 'c'], ['d'], ['e', 'f']], 'focus': 1})

    def test_plan_drop_keep_two_pushes_forward(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f']]
        # b를 뒤로: [b,c,d] 넘침 → d가 다음으로 → [d,e,f] 넘침 → f는 맨 뒤 새 슬라이드. a는 혼자 남는다
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'line', 'slide': 1, 'at': 0}, True)
        self.assertEqual(plan, {'groups': [['a'], ['b', 'c'], ['d', 'e'], ['f']], 'focus': 1})

    def test_plan_drop_keep_two_does_not_pull_into_source(self):
        # 가운데 슬라이드가 줄을 줘도 반대쪽 이웃에서 당겨오지 않는다
        g = [['a', 'b'], ['c', 'd'], ['e']]
        plan = self.drop(g, {'slide': 1, 'line': 1}, {'type': 'line', 'slide': 2, 'at': 0}, True)
        self.assertEqual(plan, {'groups': [['a', 'b'], ['c'], ['d', 'e']], 'focus': 2})
        g = [['a'], ['b', 'c'], ['d', 'e']]
        plan = self.drop(g, {'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 1}, True)
        self.assertEqual(plan, {'groups': [['a', 'b'], ['c'], ['d', 'e']], 'focus': 0})

    def test_plan_drop_keep_two_new_slide_does_not_pull(self):
        # 새 슬라이드로 떼어내도 남은 슬라이드는 1줄 그대로
        g = [['a', 'b'], ['c', 'd']]
        plan = self.drop(g, {'slide': 0, 'line': 1}, {'type': 'new', 'at': 1}, True)
        self.assertEqual(plan, {'groups': [['a'], ['b'], ['c', 'd']], 'focus': 1})

    def test_plan_drop_keep_two_preserves_lines(self):
        g = [['a', 'b'], ['c', 'd'], ['e', 'f'], ['g', 'h']]
        moves = [({'slide': 1, 'line': 0}, {'type': 'line', 'slide': 0, 'at': 2}),
                 ({'slide': 2, 'line': 1}, {'type': 'line', 'slide': 3, 'at': 0}),
                 ({'slide': 0, 'line': 1}, {'type': 'line', 'slide': 1, 'at': 0})]
        for src, target in moves:
            with self.subTest(src=src, target=target):
                plan = self.drop(g, src, target, True)
                flat = [x for grp in plan['groups'] for x in grp]
                self.assertEqual(flat, list('abcdefgh'))   # 줄 수·순서 보존
                self.assertTrue(all(1 <= len(grp) <= 2 for grp in plan['groups']))

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

    # ── 3줄 이상 슬라이드 ──
    def test_long_slides_skips_kept(self):
        g = [['a', 'b', 'c'], ['d'], ['e', 'f', 'g', 'h']]
        self.assertEqual(self.call(f'longSlides({json.dumps(g)}, {{}})'), [0, 2])
        self.assertEqual(self.call(f'longSlides({json.dumps(g)}, {{"a\\nb\\nc": true}})'), [2])

    def test_split_asked_only_splits_asked(self):
        g = [['a', 'b', 'c'], ['d'], ['e', 'f', 'g', 'h']]
        got = self.call(f'splitAsked({json.dumps(g)}, ["e\\nf\\ng\\nh"])')
        self.assertEqual(got, {'groups': [['a', 'b', 'c'], ['d'], ['e', 'f'], ['g', 'h']], 'count': 1})
        got = self.call(f'splitAsked({json.dumps(g)}, [])')
        self.assertEqual(got, {'groups': g, 'count': 0})

    # ── 콘티 ──
    def test_move_item(self):
        self.assertEqual(self.call('moveItem(["a","b","c"], 0, 2)'), ['b', 'c', 'a'])
        self.assertEqual(self.call('moveItem(["a","b","c"], 2, 0)'), ['c', 'a', 'b'])
        self.assertEqual(self.call('moveItem(["a","b","c"], 1, 1)'), ['a', 'b', 'c'])
        self.assertEqual(self.call('moveItem(["a","b","c"], 0, 9)'), ['b', 'c', 'a'])   # 넘치면 끝으로
        self.assertEqual(self.call('moveItem(["a","b"], 5, 0)'), ['a', 'b'])            # 없는 항목은 그대로

    def test_deck_size_counts_blank_slides(self):
        # 처음·곡 사이·끝에 빈 슬라이드 (ppt_engine.setlist_chunks와 같은 규칙)
        self.assertEqual(self.call('deckSize([2, 1, 3])'), 6 + 4)
        self.assertEqual(self.call('deckSize([5])'), 5 + 2)
        self.assertEqual(self.call('deckSize([2, 0, 3])'), 5 + 3)   # 빈 곡은 건너뜀
        self.assertEqual(self.call('deckSize([0, 0])'), 0)
        self.assertEqual(self.call('deckSize([])'), 0)

    def test_deck_title(self):
        one = json.dumps([{'title': '은혜', 'artist': '손경민'}], ensure_ascii=False)
        self.assertEqual(self.call(f'deckTitle({one}, new Date(2026, 9, 4))'), '은혜 — 손경민')
        two = json.dumps([{'title': 'A', 'artist': 'x'}, {'title': 'B', 'artist': 'y'}])
        self.assertEqual(self.call(f'deckTitle({two}, new Date(2026, 9, 4))'), '2026-10-04 예배 가사')
        self.assertEqual(self.call('deckTitle([{"title": "A", "artist": ""}], new Date())'), 'A')
        self.assertEqual(self.call('deckTitle([], new Date())'), '')
        # 제목이 비면 '가사' (직접 입력)
        self.assertEqual(self.call('deckTitle([{"title": "", "artist": ""}], new Date())'), '가사')
        self.assertEqual(self.call('deckTitle([{"title": "", "artist": "가수"}], new Date())'), '가사 — 가수')

    def test_safe_file_name(self):
        self.assertEqual(self.call('safeFileName("a/b:c?")'), 'a_b_c_')
        self.assertEqual(self.call('safeFileName("")'), '가사')

    # ── 문단 안에서 묶기 ──
    def test_regroup_within_keeps_paragraph_boundaries(self):
        text = '가\n나\n다\n\n라\n마'
        self.assertEqual(self.call(f'regroupWithin({json.dumps(text)}, 2)'), [['가', '나'], ['다'], ['라', '마']])
        self.assertEqual(self.call('regroupWithin("", 2)'), [])

    # ── 가사 정리 ──
    def test_clean_text(self):
        text = '가\x0b나\u200b\n\u200b\n다\t라\x01\r\n마\u2028바\ufffe'
        self.assertEqual(self.call(f'cleanText({json.dumps(text)})'), '가\n나\n\n다 라\n마\n바')
        self.assertEqual(self.call('cleanText("😀 \\ud800 x")'), '😀  x')      # 짝 없는 서로게이트만 지운다
        self.assertEqual(self.call('cleanText("\u1100\u1161")'), '가')          # NFC

    def tidy(self, text, title=''):
        return self.call(f'tidyMelonLyrics({json.dumps(text, ensure_ascii=False)}, {json.dumps(title, ensure_ascii=False)})')

    def test_tidy_removes_title_line_only_when_first_single_line_paragraph(self):
        r = self.tidy('팔레트 (Feat. G-DRAGON)\n\n이상하게도 요즘엔\n난 꿈처럼', '팔레트 (Feat. G-DRAGON)')
        self.assertEqual(r, {'text': '이상하게도 요즘엔\n난 꿈처럼', 'marks': 0, 'title': True})
        # 공백·대소문자는 무시
        self.assertTrue(self.tidy('Palette\n\n가', 'p a l e t t e')['title'])
        # 첫 문단이 여러 줄이면 제목이 아니다 / 제목이 다르면 그대로
        self.assertFalse(self.tidy('팔레트\n가\n\n나', '팔레트')['title'])
        self.assertFalse(self.tidy('다른 줄\n\n가', '팔레트')['title'])
        # 두 번째 문단의 같은 줄은 가사이므로 남긴다
        self.assertEqual(self.tidy('가\n\n팔레트', '팔레트')['text'], '가\n\n팔레트')
        self.assertFalse(self.tidy('팔레트\n\n가', '')['title'])

    def test_tidy_removes_verse_numbers_and_chorus_marks(self):
        text = '1.내가 누려왔던\n2. 모든 것이\n\n(후렴) 모든 것이 은혜\n은혜 (후렴 2회)\n(후렴)'
        r = self.tidy(text)
        self.assertEqual(r['text'], '내가 누려왔던\n모든 것이\n\n모든 것이 은혜\n은혜')    # '(후렴)'만 있던 줄은 빠진다
        self.assertEqual(r['marks'], 5)
        self.assertFalse(r['title'])

    def test_tidy_leaves_other_text_alone(self):
        text = '2.0 버전의 사랑\n10명이 함께\n(Hey) 사랑해\n3. 은혜 (후렴구는 아니야)'
        r = self.tidy(text)
        self.assertEqual(r['text'].split('\n')[:3], ['2.0 버전의 사랑', '10명이 함께', '(Hey) 사랑해'])
        self.assertEqual(r['marks'], 2)   # '3.' 와 '(후렴구…)'
        self.assertEqual(self.tidy('가\n나')['marks'], 0)
        self.assertEqual(self.tidy('', '제목'), {'text': '', 'marks': 0, 'title': False})

    def test_tidy_drops_paragraphs_that_become_empty(self):
        self.assertEqual(self.tidy('가\n\n(후렴)\n\n나')['text'], '가\n\n나')

    def test_tidy_message(self):
        self.assertEqual(self.call('tidyMessage({marks: 3, title: false})'), '절 번호·후렴 표시 3개를 정리했어요')
        self.assertEqual(self.call('tidyMessage({marks: 0, title: true})'), '맨 앞의 제목 줄을 정리했어요')
        self.assertEqual(self.call('tidyMessage({marks: 2, title: true})'), '맨 앞의 제목 줄과 절 번호·후렴 표시 2개를 정리했어요')
        self.assertEqual(self.call('tidyMessage({marks: 0, title: false})'), '')


if __name__ == '__main__':
    unittest.main()
