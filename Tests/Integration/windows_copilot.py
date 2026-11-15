import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
shell = shutil.which('powershell.exe') or shutil.which('pwsh')
with tempfile.TemporaryDirectory(prefix='usageedge-gh-') as folder:
    path = Path(folder)
    payload = '{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":19.75}]}'
    if os.name == 'nt':
        fake = path / 'gh.cmd'
        fake.write_text('@echo off\r\nif "%USAGEEDGE_FAKE_GH_ERROR%"=="1" exit /b 1\r\necho %* | findstr /C:"settings/billing/ai_credit/usage" >nul\r\nif errorlevel 1 (echo test-user) else (echo ' + payload + ')\r\n', encoding='ascii')
        system = str(Path(os.environ['SystemRoot']) / 'System32')
        envpath = folder + os.pathsep + system + os.pathsep + os.environ['SystemRoot']
    else:
        fake = path / 'gh.exe'
        fake.write_text('#!/bin/sh\n[ "$USAGEEDGE_FAKE_GH_ERROR" = 1 ] && exit 1\ncase "$*" in *settings/billing/ai_credit/usage*) echo ' + "'" + payload + "'" + ';; *) echo test-user;; esac\n', encoding='ascii')
        fake.chmod(0o755)
        envpath = folder + os.pathsep + '/usr/bin:/bin'
    env = dict(os.environ, PATH=envpath)
    env.pop('USAGEEDGE_FAKE_GH_ERROR', None)
    subprocess.run([shell, '-NoProfile', '-File', str(root / 'Tests/Integration/windows_copilot.ps1')], check=True, timeout=40, env=env)
    if os.name == 'nt':
        env['USAGEEDGE_TEST_COPILOT'] = '1'
        subprocess.run([shell, '-NoProfile', '-STA', '-File', str(root / 'Windows/UITest.ps1')], check=True, timeout=90, env=env)
