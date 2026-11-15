#!/usr/bin/env python3
"""Create a UTF-8 Windows preview archive from a fixed, reviewable file list."""
from pathlib import Path
import sys
import unicodedata
import zipfile

root = Path(__file__).resolve().parents[1] / 'Windows'
files = ('README.md', 'Quota.ps1', 'Kimi.ps1', 'Copilot.ps1', 'ClaudeSetup.ps1', 'ClaudeStatus.ps1', 'ClaudeSnapshot.ps1', 'UsageEdge.ps1', '실행.cmd', '검사.ps1')
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 Tools/package_windows.py OUTPUT.zip')
for name in files:
    source = root / name
    if source.is_symlink() or not source.is_file():
        raise SystemExit('Missing or unsupported source file: ' + name)
with zipfile.ZipFile(sys.argv[1], 'x', compression=zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        archive.write(root / name, 'Windows/' + unicodedata.normalize('NFC', name))
