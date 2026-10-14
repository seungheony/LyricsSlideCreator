import os
import unittest

from src.utils.line_fit import LineFit

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class LineFitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fit = LineFit(os.path.join(ROOT, 'template.pptx'))

    def test_reference_widths(self):
        # 템플릿 가사 글상자(Pretendard, 쓸 수 있는 폭 705.6pt)에서 '가' 한 글자는 36.25pt
        self.assertAlmostEqual(self.fit.width_pt('가' * 19), 688.75, places=2)
        self.assertAlmostEqual(self.fit.width_pt('가' * 20), 725.0, places=2)

    def test_wraps_over_limit(self):
        self.assertLess(self.fit.ratio('가' * 19), 1)
        self.assertGreater(self.fit.ratio('가' * 20), 1)

    def test_empty_line(self):
        self.assertEqual(self.fit.ratio(''), 0)


if __name__ == '__main__':
    unittest.main()
