"""ManualForm.qml(곡 찾기 서랍의 '직접 입력' 탭)을 화면 없이 불러 prefill → submitted 값과 슬라이드 수를 시험한다."""
import os
import unittest

from PySide6.QtCore import Q_ARG, QMetaObject, QObject, QUrl
from PySide6.QtQml import QQmlComponent, QQmlEngine

from src.utils.helpers import resource_path

QML = resource_path(os.path.join('src', 'qml_ui', 'qml', 'ManualForm.qml'))


class ManualForm(unittest.TestCase):
    def setUp(self):
        self.engine = QQmlEngine()
        self.engine.rootContext().setContextProperty('assetsUrl', QUrl.fromLocalFile(resource_path('assets')).toString())
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(QML))
        self.form = self.component.create()
        self.assertIsNotNone(self.form, self.component.errorString())
        self.got = []
        self.form.submitted.connect(lambda info, text: self.got.append((info, text)))

    def tearDown(self):
        self.form.deleteLater()

    def child(self, name):
        return self.form.findChild(QObject, name)

    def call(self, name, *args):
        """QML 함수 부르기 (인자는 var 하나까지)"""
        ok = QMetaObject.invokeMethod(self.form, name, *[Q_ARG('QVariant', a) for a in args])
        self.assertIsNot(ok, False)

    def test_prefill_and_submit(self):
        self.call('prefill', {'title': '주 품에', 'artist': '어노인팅', 'album': '앨범', 'song_id': '123',
                              'notice': "멜론에서 '주 품에'를 찾지 못해 제목을 미리 채웠어요"})
        self.assertEqual(self.child('manualTitle').property('text'), '주 품에')
        self.assertEqual(self.child('manualNotice').property('text'), "멜론에서 '주 품에'를 찾지 못해 제목을 미리 채웠어요")
        self.assertFalse(self.form.property('canSubmit'))
        self.assertFalse(self.child('manualSubmit').property('enabled'))

        text = '첫 줄\n둘째 줄\n셋째 줄\n\n넷째 줄\n\n\n다섯째 줄'
        self.child('manualLyrics').setProperty('text', text)
        self.assertEqual(self.form.property('slideCount'), 4)    # 담으면 2줄씩 나뉘는 기준
        self.assertTrue(self.child('manualSubmit').property('enabled'))
        self.assertIn('4장', self.child('manualSlideCount').property('text'))

        self.call('submit')
        self.assertEqual(len(self.got), 1)
        info, got_text = self.got[0]
        info = info.toVariant() if hasattr(info, 'toVariant') else info
        self.assertEqual(info, {'title': '주 품에', 'artist': '어노인팅', 'album': '앨범', 'song_id': '123'})
        self.assertEqual(got_text, text)

    def test_submit_without_prefill_and_reset(self):
        self.call('prefill', {'title': '새 곡'})
        self.child('manualLyrics').setProperty('text', '하나\n둘\n셋')
        self.assertEqual(self.form.property('slideCount'), 2)
        self.call('submit')
        info, _ = self.got[0]
        info = info.toVariant() if hasattr(info, 'toVariant') else info
        self.assertEqual(info, {'title': '새 곡', 'artist': '', 'album': '', 'song_id': ''})

        self.call('reset')
        self.assertEqual(self.child('manualLyrics').property('text'), '')
        self.assertEqual(self.form.property('notice'), '')
        self.call('submit')    # 가사가 없으면 담지 않는다
        self.assertEqual(len(self.got), 1)

    def test_blank_lyrics_cannot_submit(self):
        self.child('manualLyrics').setProperty('text', '  \n\n \n')
        self.assertEqual(self.form.property('slideCount'), 0)
        self.assertFalse(self.form.property('canSubmit'))


if __name__ == '__main__':
    unittest.main()
