#!/usr/bin/env bash
# ==============================================================================
# build-core-plugin.sh - Builds packages/plugin-core's wasm, as upstream's ci-medium
# ==============================================================================
# The workflow medium specs load the core plugin (packages/plugin-core/manifest.json ->
# dist/plugin.wasm). Upstream's `ci-medium` builds it (`//packages/plugin-core:build`) with
# its pinned extism-js, which runs binaryen's wasm-merge/wasm-opt (both in enve.cue).
#
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it, as build-workspace-deps.sh: the reach-map
# generator builds it once up front.
set -euo pipefail
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO_ROOT/node_modules"
cd "$REPO_ROOT"
# Its build runs `plugin-sdk prepareBuild`: plugin-sdk first. Jobs sharing a checkout take
# turns, as build-workspace-deps.sh. Only when its sources or pinned tools changed:
# extism-js never builds the same wasm twice, and every rebuild changed the footprint of
# each spec loading it (the reach-map recorder traced them again on every run).
exec flock -o "$REPO_ROOT/node_modules/.enact-build-deps.lock" \
  "$REPO_ROOT/helpers/build-if-stale.sh" '@immich/plugin-core...' packages/plugin-core/dist enve.lock >&2
