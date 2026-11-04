#!/usr/bin/env bash
# ==============================================================================
# build-workspace-deps.sh - Builds the workspace packages the package in $PWD uses
# ==============================================================================
# Delegates to `helpers/build-if-stale.sh` (`enact helper build-once`), which serializes
# workspace builds under a host-scoped lock and skips when inputs and outputs are current.
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it when a caller already materialized workspace builds.
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

if [ "${1:-}" = --package ]; then
  unset IMMICH_WORKSPACE_DEPS_BUILT
  entry="${2#./}"
  rel_dir="${PWD#"$REPO_ROOT"/}"
  out_dir="$rel_dir/$(dirname "$entry")"
  pkg_name="$(node -p "require('./package.json').name")"
  [ -e "$REPO_ROOT/$rel_dir/$entry" ] || rm -f "$REPO_ROOT/$out_dir/.build-stamp"
  exec "$REPO_ROOT/helpers/build-if-stale.sh" "${pkg_name}..." "$out_dir" >&2
fi

[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0
exec "$REPO_ROOT/helpers/build-if-stale.sh" --deps-of "$PWD" >&2
