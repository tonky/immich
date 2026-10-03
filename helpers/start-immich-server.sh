#!/usr/bin/env bash
# ==============================================================================
# start-immich-server.sh - Service Launcher for the Immich Backend Server
# ==============================================================================
# Runs the real server the e2e suite talks to, as upstream's docker-compose does:
# builds server/dist when missing, provisions geodata, then execs node. It never
# substitutes a stand-in: a server that cannot start fails its readiness probe.
set -euo pipefail

if [ ! -d node_modules ]; then
  echo "❌ [immich-server] node_modules missing: install dependencies first (pnpm install)" >&2
  exit 1
fi

if [ ! -f server/dist/main.js ]; then
  # `immich...` builds the server's workspace deps first (sdk, plugin-sdk), like its Dockerfile.
  echo "🔨 [immich-server] building server/dist..."
  pnpm --filter 'immich...' run build
fi

# Video thumbnails and probes with upstream's pinned jellyfin-ffmpeg.
PATH="$(helpers/pinned-tool.sh jellyfin-ffmpeg):$PATH"
export PATH

helpers/provision-geodata.sh "${IMMICH_BUILD_DATA:?}/geodata"
# The image ships the core plugin at /build/plugins/immich-plugin-core (manifest + dist).
helpers/build-core-plugin.sh
mkdir -p "$IMMICH_BUILD_DATA/plugins"
ln -sfn "$PWD/packages/plugin-core" "$IMMICH_BUILD_DATA/plugins/immich-plugin-core"
mkdir -p "${IMMICH_MEDIA_LOCATION:?}"

exec node server/dist/main.js
