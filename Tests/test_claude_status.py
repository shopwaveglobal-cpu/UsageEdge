import importlib.util
import pathlib
import io
import json
import tempfile
import unittest
from unittest.mock import patch

path = pathlib.Path(__file__).resolve().parents[1] / 'Tools' / 'claude_status.py'
spec = importlib.util.spec_from_file_location('claude_status', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class StatusTests(unittest.TestCase):
    def test_only_rate_limits_are_retained(self):
        data = {'session_id': 'private', 'rate_limits': {'five_hour': {'used_percentage': 23.5, 'resets_at': 2000000000}, 'seven_day': {'used_percentage': 40, 'resets_at': 2000001000}}}
        self.assertEqual(mod.extract(data), {'five_hour': {'used_percentage': 23.5, 'resets_at': 2000000000}, 'seven_day': {'used_percentage': 40, 'resets_at': 2000001000}})
    def test_invalid_or_absent_values_are_not_invented(self):
        self.assertEqual(mod.extract({'rate_limits': {'five_hour': {'used_percentage': True}, 'seven_day': {'used_percentage': 101}}}), {})
        self.assertEqual(mod.extract({}), {})
    def test_missing_limits_preserve_previous_observation(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(mod.Path, 'home', return_value=pathlib.Path(tmp)), patch('sys.stdout', io.StringIO()):
                with patch('sys.stdin', io.StringIO(json.dumps({'rate_limits': {'five_hour': {'used_percentage': 20}}}))):
                    mod.main()
                file = pathlib.Path(tmp) / 'Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json'
                original = file.read_bytes()
                with patch('sys.stdin', io.StringIO('{}')):
                    mod.main()
                self.assertEqual(file.read_bytes(), original)

    def test_capture_saves_only_limits_with_private_permissions(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = {'session_id': 'private', 'rate_limits': {'five_hour': {'used_percentage': 20}}}
            with patch.object(mod.Path, 'home', return_value=pathlib.Path(tmp)), patch('sys.stdin', io.StringIO(json.dumps(payload))), patch('sys.stdout', io.StringIO()):
                mod.main()
            file = pathlib.Path(tmp) / 'Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json'
            snapshot = json.loads(file.read_text())
            self.assertEqual(snapshot['rate_limits'], {'five_hour': {'used_percentage': 20}})
            self.assertNotIn('private', file.read_text())
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)

if __name__ == '__main__': unittest.main()
