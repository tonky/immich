#!/usr/bin/env bash
# ==============================================================================
# build-core-plugin.sh - Builds packages/plugin-core's wasm, as upstream's ci-medium
# ==============================================================================
# Standalone callers materialize `@immich/plugin-core:build` via `enact helper ensure-outputs`;
# the producer job itself (`--producer`) delegates to `helpers/build-if-stale.sh`.
set -euo pipefail
if [ "${1:-}" = --producer ]; then
  unset IMMICH_WORKSPACE_DEPS_BUILT
fi
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
enact="${ENACT_EXE:-${ENACT_BIN:-$(command -v enact || true)}}"
if [ "${1:-}" != --producer ] && [ -n "$enact" ] && [ -d "$REPO_ROOT/.enact" ]; then
  exec "$enact" helper ensure-outputs @immich/plugin-core:build >&2
fi
[ -e packages/plugin-core/dist/plugin.wasm ] || rm -f packages/plugin-core/dist/.build-stamp
exec "$REPO_ROOT/helpers/build-if-stale.sh" '@immich/plugin-core...' packages/plugin-core/dist enve.lock >&2
