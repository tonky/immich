#!/usr/bin/env bash
# ==============================================================================
# server-image.sh - Prints the e2e server's node and sharp, as upstream's image has them
# ==============================================================================
# node 24.18.0 and sharp built on libvips with upstream's loaders (HEIC, JXL, RAW): what,
# and why an environment of its own, in helpers/server-image/enve.cue. Its locked closure
# is fetched or built on first use. helpers/server-image.cjs points the server's
# `require('sharp')` at it; the server runs on that environment's node, which loads it.
#
# Usage: helpers/server-image.sh   (prints: <node bin dir>\n<sharp dir>)
set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/server-image" && pwd)"
mapfile -t found < <(enve run --locked -f "$ENV_DIR" -- sh -c \
  'dirname "$(readlink -f "$(command -v node)")"; echo "$IMMICH_SHARP_PATH"')
[ "${#found[@]}" -eq 2 ] && [ -f "${found[1]}/package.json" ] || {
  echo "❌ [server-image] cannot resolve node and sharp in $ENV_DIR" >&2
  exit 1
}
printf '%s\n' "${found[@]}"
