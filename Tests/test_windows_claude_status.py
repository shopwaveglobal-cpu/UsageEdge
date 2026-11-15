import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELL = shutil.which('powershell.exe') or shutil.which('pwsh')
SCRIPT = ROOT / 'Windows' / 'ClaudeStatus.ps1'

@unittest.skipUnless(SHELL, 'PowerShell is required')
class ClaudeStatusTests(unittest.TestCase):
    def sanitize(self, data):
        result = subprocess.run([SHELL, '-NoProfile', '-File', str(SCRIPT), '-SanitizeOnly'], input=json.dumps(data), text=True, capture_output=True, check=True)
        return json.loads(result.stdout)

    def test_keeps_only_documented_quota_fields(self):
        payload = {'session_id': 'private', 'transcript_path': 'secret', 'rate_limits': {'five_hour': {'used_percentage': 23.5, 'resets_at': 2000000000, 'extra': 'secret'}, 'seven_day': {'used_percentage': 40}}}
        result = self.sanitize(payload)
        self.assertEqual(result, {'five_hour': {'used_percentage': 23.5, 'resets_at': 2000000000}, 'seven_day': {'used_percentage': 40}})
        self.assertNotIn('secret', json.dumps(result))

    def test_missing_and_invalid_limits_are_not_invented(self):
        self.assertEqual(self.sanitize({'rate_limits': {'five_hour': {'used_percentage': True}, 'seven_day': {'used_percentage': 101}}}), {})
        self.assertEqual(self.sanitize({}), {})

    @unittest.skipUnless(os.name == 'nt', 'DPAPI requires Windows')
    def test_capture_encrypts_and_preserves_last_valid_observation(self):
        with tempfile.TemporaryDirectory() as folder:
            env = dict(os.environ, LOCALAPPDATA=folder)
            command = [SHELL, '-NoProfile', '-File', str(SCRIPT)]
            data = {'session_id': 'private', 'rate_limits': {'five_hour': {'used_percentage': 20}}}
            subprocess.run(command, input=json.dumps(data), text=True, capture_output=True, check=True, env=env)
            snapshot = pathlib.Path(folder) / 'UsageEdge' / 'ClaudeStatus' / 'snapshot.dat'
            encrypted = snapshot.read_bytes()
            self.assertNotIn(b'private', encrypted)
            self.assertNotIn(b'used_percentage', encrypted)
            subprocess.run(command, input='{}', text=True, capture_output=True, check=True, env=env)
            self.assertEqual(snapshot.read_bytes(), encrypted)
            decrypt = "Add-Type -AssemblyName System.Security; $p=Join-Path $env:LOCALAPPDATA 'UsageEdge/ClaudeStatus/snapshot.dat'; $b=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($p),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); [Text.Encoding]::UTF8.GetString($b)"
            result = subprocess.run([SHELL, '-NoProfile', '-Command', decrypt], text=True, capture_output=True, check=True, env=env)
            saved = json.loads(result.stdout)
            self.assertEqual(saved['rate_limits']['five_hour']['used_percentage'], 20)
            self.assertNotIn('private', result.stdout)
            env['USAGEEDGE_TEST_ROOT'] = str(ROOT / 'Windows')
            read = ". (Join-Path $env:USAGEEDGE_TEST_ROOT 'Quota.ps1'); . (Join-Path $env:USAGEEDGE_TEST_ROOT 'ClaudeSnapshot.ps1'); Get-ClaudeSnapshot | ConvertTo-Json -Depth 6 -Compress"
            result = subprocess.run([SHELL, '-NoProfile', '-Command', read], text=True, capture_output=True, check=True, env=env)
            state = json.loads(result.stdout)
            self.assertEqual(state['State'], 'fresh')
            self.assertEqual(state['Windows'][0]['Remaining'], 80)
            data['rate_limits']['five_hour']['used_percentage'] = 30
            subprocess.run(command, input=json.dumps(data), text=True, capture_output=True, check=True, env=env)
            result = subprocess.run([SHELL, '-NoProfile', '-Command', read], text=True, capture_output=True, check=True, env=env)
            self.assertEqual(json.loads(result.stdout)['Windows'][0]['Remaining'], 70)

if __name__ == '__main__': unittest.main()
