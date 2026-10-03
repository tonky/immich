#!/usr/bin/env bash
# ==============================================================================
# build-workspace-deps.sh - Builds the workspace packages the package in $PWD uses
# ==============================================================================
# Typecheck, typed lint and tests import their dependencies' build output (`@immich/sdk`
# types, `@immich/plugin-sdk` dist), as upstream's jobs build first (`//:plugins`, the sdk
# step of the cli/web/e2e jobs). A CI job starts from a clean checkout; locally another
# job's leftovers used to hide the missing build.
#
# `pnpm --filter <name>^...`: the package's workspace dependencies, transitively, in
# topological order, not the package itself. Jobs running at once in one checkout take
# turns: they write the same build directories.
#
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it: generate-reach-map.sh builds once up front, so
# the per-spec traces record what the spec reads, not a build.
set -euo pipefail
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

name=$(node -p "require('./package.json').name")
mkdir -p "$REPO_ROOT/node_modules"
exec flock "$REPO_ROOT/node_modules/.enact-build-deps.lock" \
  pnpm --filter "$name^..." --if-present run build >&2
