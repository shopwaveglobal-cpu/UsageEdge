import pathlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]

class PackageTests(unittest.TestCase):
    def test_powershell_non_ascii_scripts_have_utf8_bom(self):
        scripts = list((root / 'Windows').glob('*.ps1')) + list((root / 'Tests/Integration').glob('*.ps1'))
        for script in scripts:
            data = script.read_bytes()
            if any(byte > 127 for byte in data):
                self.assertTrue(data.startswith(b'\xef\xbb\xbf'), str(script))

    def test_contents_and_utf8_names(self):
        with tempfile.TemporaryDirectory() as folder:
            output = pathlib.Path(folder) / 'windows.zip'
            subprocess.run(['python3', str(root / 'Tools/package_windows.py'), str(output)], check=True)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(set(archive.namelist()), {'Windows/README.md', 'Windows/Quota.ps1', 'Windows/Kimi.ps1', 'Windows/Copilot.ps1', 'Windows/ClaudeSetup.ps1', 'Windows/ClaudeStatus.ps1', 'Windows/ClaudeSnapshot.ps1', 'Windows/UsageEdge.ps1', 'Windows/실행.cmd', 'Windows/검사.ps1'})
                for item in archive.infolist():
                    if any(ord(char) > 127 for char in item.filename):
                        self.assertTrue(item.flag_bits & 0x800)
                self.assertEqual(archive.read('Windows/실행.cmd'), (root / 'Windows/실행.cmd').read_bytes())

    def test_missing_file_does_not_create_partial_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            work = pathlib.Path(folder)
            (work / 'Tools').mkdir(); (work / 'Windows').mkdir()
            script = work / 'Tools/package_windows.py'
            shutil.copyfile(root / 'Tools/package_windows.py', script)
            output = work / 'preview.zip'
            result = subprocess.run(['python3', str(script), str(output)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_existing_output_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            output = pathlib.Path(folder) / 'preview.zip'
            output.write_bytes(b'previous')
            result = subprocess.run(['python3', str(root / 'Tools/package_windows.py'), str(output)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b'previous')

if __name__ == '__main__': unittest.main()
