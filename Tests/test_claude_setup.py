import importlib.util
import json
import shlex
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / 'Tools' / 'setup_claude.py'
spec = importlib.util.spec_from_file_location('setup_claude', path)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

class SetupTests(unittest.TestCase):
    def test_preserves_existing_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'settings.json'
            file.write_text('{"theme":"dark"}')
            setup.install(file)
            value = json.loads(file.read_text())
            self.assertEqual(value['theme'], 'dark')
            self.assertEqual(value['statusLine']['type'], 'command')
            self.assertIn('claude_status.py', value['statusLine']['command'])
            self.assertEqual(Path(shlex.split(value['statusLine']['command'])[1]), path.with_name('claude_status.py'))
    def test_refuses_existing_statusline_and_bad_json(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'settings.json'
            for before in ('{"statusLine":{"type":"command","command":"existing"}}', '{broken'):
                file.write_text(before)
                with self.assertRaises(ValueError): setup.install(file)
                self.assertEqual(file.read_text(), before)
    def test_new_file_is_private(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'new' / 'settings.json'
            setup.install(file)
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
    def test_refuses_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'target.json'; target.write_text('{}')
            link = Path(folder) / 'settings.json'; link.symlink_to(target)
            with self.assertRaises(ValueError): setup.install(link)
            self.assertEqual(target.read_text(), '{}')

if __name__ == '__main__': unittest.main()
