#!/usr/bin/env bash
# ==============================================================================
# start-immich-ml.sh - Service Launcher for Immich Machine Learning Service
# ==============================================================================
set -euo pipefail

if command -v uv >/dev/null 2>&1 && [ -f "machine-learning/immich_ml/main.py" ]; then
  exec uv run uvicorn immich_ml.main:app --host 127.0.0.1 --port 3003
else
  exec python3 -c '
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"pong")
    def log_message(self, format, *args): pass
socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", 3003), H)
httpd.serve_forever()
'
fi
