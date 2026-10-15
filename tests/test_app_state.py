import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from src.qml_ui.backend import Backend
from src.utils import app_state

TEST_DOMAIN = app_state.BUNDLE_ID + '.unittest'


def temp_data_dir():
    """앱 데이터 폴더를 새 임시 폴더로 (with 문)"""
    d = tempfile.TemporaryDirectory()
    return d, mock.patch.dict(os.environ, {'LSC_DATA_DIR': d.name})


class BundleId(unittest.TestCase):
    def test_same_as_build_script(self):
        with open(os.path.join(app_state.resource_path('scripts'), 'build.py'), encoding='utf-8') as f:
            found = re.search(r"^BUNDLE_ID = '([^']+)'", f.read(), re.M).group(1)
        self.assertEqual(found, app_state.BUNDLE_ID)


class DataDir(unittest.TestCase):
    def test_dev_mode_uses_project_folder(self):
        with mock.patch.dict(os.environ):
            os.environ.pop('LSC_DATA_DIR', None)
            self.assertFalse(app_state.is_built())
            self.assertEqual(app_state.data_dir(), app_state.resource_path('user_data'))

    def test_built_app_uses_user_folder(self):
        with mock.patch.dict(os.environ), mock.patch.object(app_state, 'is_built', return_value=True):
            os.environ.pop('LSC_DATA_DIR', None)
            path = app_state.data_dir()
        self.assertTrue(path.endswith(app_state.APP_DIR_NAME))
        self.assertNotIn(app_state.resource_path(''), path)

    def test_round_trip(self):
        d, env = temp_data_dir()
        with d, env:
            self.assertEqual(app_state.load(), {})
            app_state.save({'tutorials_seen': ['search']})
            self.assertEqual(app_state.load(), {'tutorials_seen': ['search']})
            # 한글은 그대로 (\\uXXXX로 늘어나지 않게)
            app_state.write_json(app_state.data_path('x.json'), {'a': '가사'})
            with open(app_state.data_path('x.json'), encoding='utf-8') as f:
                self.assertIn('가사', f.read())

    def test_broken_file_reads_empty(self):
        d, env = temp_data_dir()
        with d, env:
            with open(app_state.data_path('state.json'), 'w', encoding='utf-8') as f:
                f.write('{"tutorials_seen": [')
            self.assertEqual(app_state.load(), {})

    def test_unwritable_is_ignored(self):
        with mock.patch.dict(os.environ, {'LSC_DATA_DIR': '/nonexistent-dir/x'}):
            app_state.save({'tutorials_seen': ['search']})
            self.assertFalse(app_state.write_json(app_state.data_path('x.json'), {}))


@unittest.skipUnless(sys.platform == 'darwin', 'macOS 환경설정 plist')
class PlistMigration(unittest.TestCase):
    def tearDown(self):
        subprocess.run(['defaults', 'delete', TEST_DOMAIN], capture_output=True)
        # delete 뒤에도 빈 plist 파일이 남는다. 시험이 남긴 파일은 지운다
        path = os.path.expanduser(f'~/Library/Preferences/{TEST_DOMAIN}.plist')
        if os.path.exists(path):
            os.remove(path)

    def test_moves_tutorials_and_keeps_other_keys(self):
        subprocess.run(['defaults', 'write', TEST_DOMAIN, 'tutorials_seen', '-array', 'search', 'editor'], check=True)
        subprocess.run(['defaults', 'write', TEST_DOMAIN, 'NSNavLastRootDirectory', '/tmp'], check=True)
        d, env = temp_data_dir()
        with d, env:
            self.assertEqual(app_state.migrate_plist(TEST_DOMAIN), {'tutorials_seen': ['search', 'editor']})
            with open(app_state.data_path('state.json'), encoding='utf-8') as f:
                self.assertEqual(json.load(f), {'tutorials_seen': ['search', 'editor']})
        gone = subprocess.run(['defaults', 'read', TEST_DOMAIN, 'tutorials_seen'], capture_output=True)
        self.assertNotEqual(gone.returncode, 0)
        out = subprocess.run(['defaults', 'read', TEST_DOMAIN, 'NSNavLastRootDirectory'], capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), '/tmp')

    def test_nothing_to_move(self):
        d, env = temp_data_dir()
        with d, env:
            self.assertEqual(app_state.migrate_plist(TEST_DOMAIN), {})
            self.assertFalse(os.path.exists(app_state.data_path('state.json')))


class BackendTutorial(unittest.TestCase):
    def test_seen_stays_in_memory_when_save_fails(self):
        with mock.patch.object(app_state, 'load', return_value={}), \
                mock.patch.dict(os.environ, {'LSC_DATA_DIR': '/nonexistent-dir/x'}):
            backend = Backend(mock.Mock())
            self.assertFalse(backend.tutorialSeen('search'))
            backend.markTutorialSeen('search')
            self.assertTrue(backend.tutorialSeen('search'))
            self.assertFalse(backend.tutorialSeen('editor'))
            backend.shutdown()

    def test_reads_state_once(self):
        with mock.patch.object(app_state, 'load', return_value={'tutorials_seen': ['editor']}) as load:
            backend = Backend(mock.Mock())
            self.assertTrue(backend.tutorialSeen('editor'))
            self.assertTrue(backend.tutorialSeen('editor'))
            self.assertEqual(load.call_count, 1)
            backend.shutdown()


class BackendWindow(unittest.TestCase):
    def test_round_trip(self):
        d, env = temp_data_dir()
        with d, env:
            backend = Backend(mock.Mock())
            self.assertIsNone(backend.window_geometry())
            backend.save_window_geometry(10, 20, 1200, 900, True)
            backend.shutdown()
            backend = Backend(mock.Mock())
            self.assertEqual(backend.window_geometry(), {'x': 10, 'y': 20, 'width': 1200, 'height': 900, 'maximized': True})
            backend.shutdown()

    def test_bad_values_are_ignored(self):
        for bad in ({'x': 0, 'y': 0, 'width': 0, 'height': 500}, {'x': 'a'}, [1, 2]):
            with mock.patch.object(app_state, 'load', return_value={'window': bad}):
                backend = Backend(mock.Mock())
                self.assertIsNone(backend.window_geometry())
                backend.shutdown()


if __name__ == '__main__':
    unittest.main()
