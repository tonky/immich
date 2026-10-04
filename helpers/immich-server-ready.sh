#!/usr/bin/env bash
# ==============================================================================
# immich-server-ready.sh - The e2e server answers and its worker has imported geodata
# ==============================================================================
# The API listens before the microservices worker finishes MapRepository.init: on a fresh
# database it imports ~220k geodata records (11-18 s on a CI runner), and metadata jobs for
# assets with GPS wait for it. Specs that upload such an asset in beforeAll and wait 10 s
# for `assetUpload` (asset.e2e-spec: thompson-springs.jpg) then time out. The worker records
# the import as `reverse-geocoding-state` in system_metadata; ready means both.
#
# Usage: helpers/immich-server-ready.sh   (exit 0 when ready)
set -euo pipefail

curl -s -f --connect-timeout 1 --max-time 3 "http://127.0.0.1:${IMMICH_PORT:-2285}/api/server/ping" >/dev/null
imported="$(psql -h "${DB_HOSTNAME:-127.0.0.1}" -p "${DB_PORT:-5435}" -U "${DB_USERNAME:-postgres}" \
  -d "${DB_DATABASE_NAME:-immich}" -tAc \
  "SELECT 1 FROM system_metadata WHERE key = 'reverse-geocoding-state'" 2>/dev/null || true)"
[ "$imported" = 1 ]
