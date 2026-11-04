#!/usr/bin/env bash
# ==============================================================================
# build-if-stale.sh - Builds a pnpm filter unless its output was built from these sources
# ==============================================================================
# Usage: build-if-stale.sh <pnpm filter> <output dir> [extra input path...]
#        build-if-stale.sh --deps-of <package dir>
#
# Delegates input hashing, installed-store discovery, output verification, and host-scoped
# locking to `enact helper build-once`.
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it when a caller already materialized workspace builds.
set -euo pipefail
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

root="$(git rev-parse --show-toplevel)"
enact="${ENACT_EXE:-${ENACT_BIN:-$(command -v enact || true)}}"
[ -n "$enact" ] || { echo "build-if-stale.sh: enact not found (set ENACT_EXE, ENACT_BIN, or put enact on PATH)" >&2; exit 2; }

if [ "$1" = --deps-of ]; then
  dir="$(cd "$2" && pwd)"
  cd "$root"
  exec "$enact" helper build-once \
    --name build-deps \
    --stamp "$dir/node_modules/.enact-deps-stamp" \
    --pnpm-deps-of "$dir"
fi

filter="$1"
output="$2"
shift 2
cd "$root"
inputs=()
[ "$#" -eq 0 ] || inputs=(--inputs "$@")
exec "$enact" helper build-once \
  --name build-deps \
  --stamp "$root/$output/.build-stamp" \
  --output "$output" \
  --pnpm-filter "$filter" \
  ${inputs[@]+"${inputs[@]}"}
