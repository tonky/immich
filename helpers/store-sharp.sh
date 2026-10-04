#!/usr/bin/env bash
# ==============================================================================
# store-sharp.sh - Prints nixpkgs' immich's sharp and the node that can load it
# ==============================================================================
# sharp built against nixpkgs' libvips, which decodes HEIC, JXL and RAW: why, and why an
# environment of its own, in helpers/store-sharp/enve.cue. Its locked closure is fetched
# on first use. helpers/store-sharp.cjs points the server's `require('sharp')` at it.
#
# Its libvips links a newer glibc than the dev profile's node 24.15.0, and a process loads
# one glibc: the server runs on that environment's node (same nixpkgs revision), which
# this prints first.
#
# Usage: helpers/store-sharp.sh   (prints: <node bin dir>\n<sharp dir>)
set -euo pipefail

ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/store-sharp" && pwd)"
mapfile -t found < <(enve run --locked -f "$ENV_DIR" -- sh -c \
  'readlink -f "$(command -v node)"; readlink -f "$(command -v immich-admin)"')
[ "${#found[@]}" -eq 2 ] || { echo "❌ [store-sharp] cannot resolve node and immich in $ENV_DIR" >&2; exit 1; }
node=${found[0]}
immich=${found[1]%/bin/immich-admin}
sharp="$immich/lib/node_modules/immich/node_modules/sharp"
[ -f "$sharp/package.json" ] || { echo "❌ [store-sharp] no sharp in $immich" >&2; exit 1; }
printf '%s\n' "${node%/node}" "$sharp"
