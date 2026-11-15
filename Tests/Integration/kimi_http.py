import http.server
import pathlib
import subprocess
import sys
import tempfile
import time
import os
import threading

root = pathlib.Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        assert self.path == '/api/v1/oauth/usage'
        token = self.headers.get('Authorization')
        if token in ('Bearer good', 'Bearer slow'):
            if token == 'Bearer slow':
                pathlib.Path(self.server.marker).touch()
                time.sleep(1)
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0.25},"limit7d":{"usedRatio":0.8}}}}}')
        elif token == 'Bearer redirect':
            self.send_response(302); self.send_header('Location', '/unexpected'); self.end_headers()
        else:
            self.send_response(401); self.end_headers()
    def log_message(self, *args): pass

with tempfile.TemporaryDirectory(prefix='usageedge-kimi-') as tmp:
    binary = str(pathlib.Path(tmp) / 'test')
    files = ['Sources/Quota.swift', 'Sources/APIProviders.swift', 'Sources/ProviderAccess.swift', 'Sources/KimiLocalRequest.swift', 'Tests/Integration/kimi_http.swift']
    subprocess.run(['swiftc', '-sdk', sys.argv[1], '-module-cache-path', tmp] + [str(root / file) for file in files] + ['-o', binary], check=True, timeout=120)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.marker = str(pathlib.Path(tmp) / 'slow-started')
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    try:
        subprocess.run([binary, str(server.server_port)], check=True, timeout=40)
        source = (root / 'Sources/main.swift').read_text()
        replacements = [
            ('init() { copilotEnabled = UserDefaults.standard.bool(forKey: "copilot.enabled"); inspectClaudeSetup(); schedule(); refresh() }', 'init() {}', 1),
            ('providerAccess.save(token, account: "KimiCodeLocal")', 'testSave(token)', 1),
            ('providerAccess.remove(account: "KimiCodeLocal")', 'testRemove()', 1),
            ('providerAccess.key(account: "KimiCodeLocal")', 'testKey()', 1),
            ('UserDefaults.standard', 'UserDefaults(suiteName: ProcessInfo.processInfo.environment["USAGEEDGE_TEST_DEFAULTS"]!)!', 17),
            ('scheduleResets("Kimi", windows: []); ', '', 2),
            ('self.scheduleResets("Kimi", windows: result); ', '', 1),
        ]
        for before, after, expected in replacements:
            assert source.count(before) == expected, (before, source.count(before))
            source = source.replace(before, after)
        source = source[:source.index('let app = NSApplication.shared')]
        source = 'var fakeToken: String?\nfunc testSave(_ token: String) -> Bool { fakeToken = token; return true }\nfunc testKey() -> String? { fakeToken }\nfunc testRemove() -> Bool { fakeToken = nil; return true }\n' + source
        source += (root / 'Tests/Integration/kimi_model.swift').read_text()
        model_source = pathlib.Path(tmp) / 'main.swift'; model_source.write_text(source)
        model_binary = str(pathlib.Path(tmp) / 'model')
        files = ['Sources/Quota.swift', 'Sources/CodexAuth.swift', 'Sources/APIProviders.swift', 'Sources/ProviderAccess.swift', 'Sources/KimiLocalRequest.swift']
        subprocess.run(['swiftc', '-sdk', sys.argv[1], '-module-cache-path', tmp] + [str(root / file) for file in files] + [str(model_source), '-o', model_binary], check=True, timeout=120)
        env = dict(os.environ, USAGEEDGE_TEST_DEFAULTS='usageedge.kimi.test.' + pathlib.Path(tmp).name, USAGEEDGE_KIMI_STARTED=server.marker)
        subprocess.run([model_binary, str(server.server_port)], check=True, timeout=30, env=env)
    finally: server.shutdown(); server.server_close(); thread.join()
