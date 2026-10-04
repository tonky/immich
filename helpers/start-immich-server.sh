#!/usr/bin/env bash
# ==============================================================================
# start-immich-server.sh - Service Launcher for the Immich Backend Server
# ==============================================================================
# Runs the real server the e2e suite talks to, as upstream's docker-compose does: builds
# server/dist and web/build when their sources changed, provisions geodata, then execs
# node with nixpkgs' sharp (HEIC, JXL, RAW). It never substitutes a stand-in: a server
# that cannot start fails its readiness probe.
set -euo pipefail

if [ ! -d node_modules ]; then
  echo "❌ [immich-server] node_modules missing: install dependencies first (pnpm install)" >&2
  exit 1
fi

# Rebuilt whenever their sources changed, not only when missing (helpers/build-if-stale.sh).
# `immich...` builds the server's workspace deps first (sdk, plugin-sdk), like its Dockerfile.
helpers/build-if-stale.sh 'immich...' server/dist
# The image's /build/www (helpers/container/immich-e2e-server.mounts): shared-link pages
# render from its index.html. `immich-web...` builds the sdk first, as its Dockerfile stage;
# translations come from ../i18n.
helpers/build-if-stale.sh 'immich-web...' web/build i18n

# Video thumbnails and probes with upstream's pinned jellyfin-ffmpeg; the image's
# `ENV PATH=…:/usr/src/app/server/bin` (immich-admin, for `docker exec`).
PATH="$(helpers/pinned-tool.sh jellyfin-ffmpeg):$PATH:$PWD/server/bin"
export PATH

# The compose's container, as helpers/container/immich-e2e-server.mounts lays it out.
NAME=immich-e2e-server
STATE=".enve/containers/$NAME"
# `compose up --force-recreate --renew-anon-volumes`: every start gets an empty /data and
# database together (the server records its /data folder checks in the database). Emptied
# in place, not removed: on CI the directory is bind-mounted at /data (view.sh).
mkdir -p "$STATE/data"
(shopt -s dotglob nullglob && rm -rf -- "$STATE/data"/*)
dropdb -h "$DB_HOSTNAME" -p "$DB_PORT" -U "$DB_USERNAME" --if-exists --force "$DB_DATABASE_NAME"
createdb -h "$DB_HOSTNAME" -p "$DB_PORT" -U "$DB_USERNAME" "$DB_DATABASE_NAME"
mkdir -p "$STATE/build/plugins"
helpers/provision-geodata.sh "$STATE/build/geodata"
# The image ships the core plugin at /build/plugins/immich-plugin-core (manifest + dist).
helpers/build-core-plugin.sh
ln -sfn "$PWD/packages/plugin-core" "$STATE/build/plugins/immich-plugin-core"

# The image's node and sharp (libvips with HEIC, JXL and RAW): helpers/server-image.sh.
# Set last: the builds above run on the dev profile's node.
image=$(helpers/server-image.sh)
IMMICH_SHARP_PATH=${image#*$'\n'}
NODE_OPTIONS="--require $PWD/helpers/server-image.cjs${NODE_OPTIONS:+ $NODE_OPTIONS}"
PATH="${image%%$'\n'*}:$PATH"
export IMMICH_SHARP_PATH NODE_OPTIONS PATH
# `docker exec` (helpers/container/path/docker) runs with the container's environment.
env -0 > "$STATE/env"

exec helpers/container/view.sh "$NAME" server/bin/start.sh
