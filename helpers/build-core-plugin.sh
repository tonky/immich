#!/usr/bin/env bash
# ==============================================================================
# build-core-plugin.sh - Builds packages/plugin-core's wasm, as upstream's ci-medium
# ==============================================================================
# The workflow medium specs load the core plugin (packages/plugin-core/manifest.json ->
# dist/plugin.wasm). Upstream's `ci-medium` builds it (`//packages/plugin-core:build`) with
# its pinned extism-js, which runs binaryen's wasm-merge/wasm-opt (tools.lock).
#
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it, as build-workspace-deps.sh: the reach-map
# generator builds it once up front.
set -euo pipefail
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="$("$REPO_ROOT/helpers/pinned-tool.sh" extism-js):$("$REPO_ROOT/helpers/pinned-tool.sh" binaryen):$PATH"
export PATH
mkdir -p "$REPO_ROOT/node_modules"
cd "$REPO_ROOT"
# Its build runs `plugin-sdk prepareBuild`: plugin-sdk first. Jobs sharing a checkout take
# turns, as build-workspace-deps.sh.
exec flock "$REPO_ROOT/node_modules/.enact-build-deps.lock" \
  pnpm --filter '@immich/plugin-core...' run build >&2
