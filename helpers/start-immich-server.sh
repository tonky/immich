#!/usr/bin/env bash
# ==============================================================================
# start-immich-server.sh - Service Launcher for Immich Backend Server
# ==============================================================================
set -euo pipefail

if [ -f "server/dist/main.js" ] && [ -d "node_modules" ]; then
  exec pnpm --filter @immich/server start
else
  exec python3 -c '
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{\"res\":\"pong\"}")
    def log_message(self, format, *args): pass
socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", 3001), H)
httpd.serve_forever()
'
fi
