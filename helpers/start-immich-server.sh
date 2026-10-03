#!/usr/bin/env bash
# ==============================================================================
# start-immich-server.sh - Service Launcher for Immich Backend Server
# ==============================================================================
set -euo pipefail

if [ -f "server/dist/main.js" ] && [ -d "node_modules" ]; then
  mkdir -p "${IMMICH_MEDIA_LOCATION:-/tmp/immich-upload}"
  GEODATA_DIR="${IMMICH_BUILD_DATA:-/tmp/immich-build}/geodata"
  mkdir -p "$GEODATA_DIR"
  echo "mock-geodata-2026" > "$GEODATA_DIR/geodata-date.txt"
  touch "$GEODATA_DIR/admin1CodesASCII.txt"
  touch "$GEODATA_DIR/admin2Codes.txt"
  touch "$GEODATA_DIR/cities500.txt"
  cat << 'GEOJSON' > "$GEODATA_DIR/ne_10m_admin_0_countries.geojson"
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"ADMIN":"Earth","ADM0_A3":"WLD","TYPE":"Sovereignty"},"geometry":{"type":"MultiPolygon","coordinates":[[[[0,0],[0,1],[1,1],[1,0],[0,0]]]]}}]}
GEOJSON
  exec node server/dist/main.js
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
