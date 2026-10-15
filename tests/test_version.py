import unittest

from src.utils.version import is_newer, parse_version


class ParseVersion(unittest.TestCase):
    def test_valid(self):
        cases = {
            'v1.2.0': (1, 2, 0, 1, 0),
            '1.2.0': (1, 2, 0, 1, 0),
            'v1.2': (1, 2, 0, 1, 0),
            'v1.2.0-beta.1': (1, 2, 0, 0, 1),
            'v1.1-beta': (1, 1, 0, 0, 0),
            ' v10.20.30 ': (10, 20, 30, 1, 0),
        }
        for text, expected in cases.items():
            with self.subTest(text):
                self.assertEqual(parse_version(text), expected)

    def test_invalid(self):
        for text in ('TEST', '', None, 'v1', 'v1.2.0-rc.1', 'v1.2.0-test.1', 'v1.2.0.4', 'abc', 'v1.2.0-beta.'):
            with self.subTest(text):
                self.assertIsNone(parse_version(text))


class IsNewer(unittest.TestCase):
    def test_table(self):
        cases = [
            ('v1.2.1', 'v1.2.0', True),
            ('v1.3.0', 'v1.2.9', True),
            ('v2.0.0', 'v1.9.9', True),
            ('v1.2.0', 'v1.2.0-beta.3', True),     # 정식 > 같은 번호 베타
            ('v1.2.0-beta.2', 'v1.2.0-beta.1', True),
            ('v1.2.0-beta.10', 'v1.2.0-beta.9', True),
            ('v1.2.0-beta.1', 'v1.1.9', True),
            ('v1.2.0', 'v1.2.0', False),
            ('v1.2.0-beta.1', 'v1.2.0', False),    # 베타 < 같은 번호 정식
            ('v1.1.0', 'v1.2.0', False),
            ('v1.2', 'v1.2.0', False),             # 같은 버전의 다른 표기
            ('v1.4', 'v1.3.1', True),              # v1.4부터 끝자리 0은 떼고 낸다 (scripts/release.sh)
            ('v1.4-beta.2', 'v1.4-beta.1', True),
            ('v1.4', 'v1.4-beta.2', True),
            ('v1.4-beta.1', 'v1.3.1', True),
            ('v1.4.1', 'v1.4', True),
            ('v1.1-beta', 'v1.1.0', False),
            ('v1.2.0', 'TEST', False),             # 개발 모드는 비교 안 함
            ('garbage', 'v1.0.0', False),
        ]
        for cand, cur, expected in cases:
            with self.subTest(f'{cand} vs {cur}'):
                self.assertEqual(is_newer(cand, cur), expected)


if __name__ == '__main__':
    unittest.main()
