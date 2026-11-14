import http.server
import pathlib
import shutil
import subprocess
import threading

root = pathlib.Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        assert self.path == '/api/v1/oauth/usage'
        token = self.headers.get('Authorization')
        if token == 'Bearer good':
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0.25},"limit7d":{"usedRatio":0.8}}}}}')
        elif token == 'Bearer redirect':
            self.send_response(302); self.send_header('Location', '/unexpected'); self.end_headers()
        else:
            self.send_response(401); self.end_headers()
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
try:
    shell = shutil.which('powershell.exe') or shutil.which('pwsh')
    subprocess.run([shell, '-NoProfile', '-File', str(root / 'Tests/Integration/windows_kimi_http.ps1'), '-Port', str(server.server_port)], check=True, timeout=60)
finally:
    server.shutdown(); server.server_close(); thread.join()
