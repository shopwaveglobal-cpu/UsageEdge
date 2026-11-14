#!/usr/bin/env python3
"""Exercise the real login controller with a local fake CLI and no browser or credentials."""
import json
import importlib.util
import io
import os
import pathlib
import subprocess
import sys
import tempfile
from unittest.mock import patch

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'Sources' / 'main.swift').read_text()
fake = str((root / 'Tests' / 'Integration' / 'fake-codex').resolve())
original_paths = '["/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]'
changes = [
 ('final class UsageModel:', 'var testOpened: [URL] = []\nfunc testOpen(_ url: URL) -> Bool { testOpened.append(url); return true }\n\nfinal class UsageModel:', 1),
 ('init() { schedule(); refresh() }', 'init() {}', 1),
 ('  refreshClaudeStatus()\n', '', 1),
 ('  if UserDefaults.standard.bool(forKey: "kimi.enabled") { refreshKimi() }\n', '', 1),
 ('  for provider in APIProvider.allCases where UserDefaults.standard.bool(forKey: "enabled.\\(provider.rawValue)") { refreshAPI(provider) }\n', '', 1),
 ('FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json")', 'URL(fileURLWithPath: ProcessInfo.processInfo.environment["USAGEEDGE_FAKE_SNAPSHOT"]!)', 1),
 ('UserDefaults.standard', 'UserDefaults(suiteName: ProcessInfo.processInfo.environment["USAGEEDGE_TEST_DEFAULTS"]!)!', 13),
 (original_paths, '[' + json.dumps(fake, ensure_ascii=False) + ']', 2),
 ('NSWorkspace.shared.open(start.url)', 'testOpen(start.url)', 1),
 ('scheduleResets("Codex", windows: result); ', '', 1),
 ('scheduleResets("Claude", windows: []); ', '', 3),
 ('scheduleResets("Claude", windows: snapshot.windows); ', '', 1),
]
for before, after, expected in changes:
 count = source.count(before)
 if count != expected:
  raise RuntimeError(f'검사 준비 실패: 예상 {expected}, 실제 {count}: {before[:40]}')
 source = source.replace(before, after)
source = source[:source.index('let app = NSApplication.shared')]
source += (root / 'Tests' / 'Integration' / 'assertions.swift').read_text()
with tempfile.TemporaryDirectory(prefix='usageedge-test-') as directory:
 work = pathlib.Path(directory)
 (work / 'main.swift').write_text(source)
 sdk = sys.argv[1] if len(sys.argv) > 1 else subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
 cmd = ['swiftc', '-sdk', sdk, '-module-cache-path', str(work / 'cache'), str(root / 'Sources' / 'Quota.swift'), str(root / 'Sources' / 'CodexAuth.swift'), str(root / 'Sources' / 'APIProviders.swift'), str(root / 'Sources' / 'ProviderAccess.swift'), str(root / 'Sources' / 'KimiLocalRequest.swift'), str(work / 'main.swift'), '-o', str(work / 'test')]
 subprocess.run(cmd, check=True, timeout=120)
 spec = importlib.util.spec_from_file_location('claude_status', root / 'Tools' / 'claude_status.py')
 capture = importlib.util.module_from_spec(spec); spec.loader.exec_module(capture)
 payload = {'session_id': 'do-not-store', 'rate_limits': {'five_hour': {'used_percentage': 25}, 'seven_day': {'used_percentage': 80}}}
 with patch.object(capture.Path, 'home', return_value=work), patch('sys.stdin', io.StringIO(json.dumps(payload))), patch('sys.stdout', io.StringIO()):
  capture.main()
 snapshot = work / 'Library/Application Support/UsageEdge/ClaudeStatus/snapshot.json'
 assert 'do-not-store' not in snapshot.read_text()
 env = os.environ.copy(); env['USAGEEDGE_FAKE_SNAPSHOT'] = str(snapshot); env['USAGEEDGE_TEST_DEFAULTS'] = 'usageedge.test.' + work.name
 subprocess.run([str(work / 'test')], check=True, timeout=30, env=env)
