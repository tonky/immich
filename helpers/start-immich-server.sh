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

# Video thumbnails and probes with upstream's pinned jellyfin-ffmpeg; the image's
# `ENV PATH=…:/usr/src/app/server/bin` (immich-admin, for `docker exec`).
PATH="$(helpers/pinned-tool.sh jellyfin-ffmpeg):$PATH:$PWD/server/bin"
export PATH

# The compose's container, as helpers/container/immich-e2e-server.mounts lays it out.
NAME=immich-e2e-server
STATE=".enve/containers/$NAME"
# `compose up --force-recreate --renew-anon-volumes`: every start gets an empty /data and
# database together (the server records its /data folder checks in the database).
rm -rf "$STATE/data"
dropdb -h "$DB_HOSTNAME" -p "$DB_PORT" -U "$DB_USERNAME" --if-exists --force "$DB_DATABASE_NAME"
createdb -h "$DB_HOSTNAME" -p "$DB_PORT" -U "$DB_USERNAME" "$DB_DATABASE_NAME"
mkdir -p "$STATE/data" "$STATE/build/plugins"
helpers/provision-geodata.sh "$STATE/build/geodata"
# The image ships the core plugin at /build/plugins/immich-plugin-core (manifest + dist).
helpers/build-core-plugin.sh
ln -sfn "$PWD/packages/plugin-core" "$STATE/build/plugins/immich-plugin-core"
# `docker exec` (helpers/container/path/docker) runs with the container's environment.
env -0 > "$STATE/env"

exec helpers/container/view.sh "$NAME" server/bin/start.sh
