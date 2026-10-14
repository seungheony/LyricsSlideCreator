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


class BundleId(unittest.TestCase):
    def test_same_as_build_script(self):
        with open(os.path.join(app_state.resource_path('scripts'), 'build.py'), encoding='utf-8') as f:
            found = re.search(r"^BUNDLE_ID = '([^']+)'", f.read(), re.M).group(1)
        self.assertEqual(found, app_state.BUNDLE_ID)

    def test_dev_mode_uses_json(self):
        self.assertFalse(app_state.use_plist())


class JsonFile(unittest.TestCase):
    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(app_state, 'STATE_FILE', os.path.join(d, 's.json')):
            self.assertEqual(app_state.load(), {})
            app_state.save({'tutorials_seen': ['search']})
            self.assertEqual(app_state.load(), {'tutorials_seen': ['search']})

    def test_unwritable_is_ignored(self):
        with mock.patch.object(app_state, 'STATE_FILE', '/nonexistent-dir/s.json'):
            app_state.save({'tutorials_seen': ['search']})


@unittest.skipUnless(sys.platform == 'darwin', 'macOS 환경설정 plist')
class Plist(unittest.TestCase):
    def tearDown(self):
        subprocess.run(['defaults', 'delete', TEST_DOMAIN], capture_output=True)
        # delete 뒤에도 빈 plist 파일이 남는다. 시험이 남긴 파일은 지운다
        path = os.path.expanduser(f'~/Library/Preferences/{TEST_DOMAIN}.plist')
        if os.path.exists(path):
            os.remove(path)

    def test_round_trip(self):
        self.assertEqual(app_state.load(TEST_DOMAIN), {})
        app_state.save({'tutorials_seen': ['search', 'editor']}, TEST_DOMAIN)
        self.assertEqual(app_state.load(TEST_DOMAIN), {'tutorials_seen': ['search', 'editor']})

    def test_other_keys_are_kept(self):
        subprocess.run(['defaults', 'write', TEST_DOMAIN, 'NSNavLastRootDirectory', '/tmp'], check=True)
        app_state.save({'tutorials_seen': ['search']}, TEST_DOMAIN)
        out = subprocess.run(['defaults', 'read', TEST_DOMAIN, 'NSNavLastRootDirectory'], capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), '/tmp')


class BackendTutorial(unittest.TestCase):
    def test_seen_stays_in_memory_when_save_fails(self):
        with mock.patch.object(app_state, 'load', return_value={}), \
                mock.patch.object(app_state, 'STATE_FILE', '/nonexistent-dir/s.json'):
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


if __name__ == '__main__':
    unittest.main()
