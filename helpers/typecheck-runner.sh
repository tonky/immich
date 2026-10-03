#!/usr/bin/env bash
# ==============================================================================
# typecheck-runner.sh - Hermetic TypeScript Check Runner for Immich
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

if [ -f "svelte.config.js" ] && [ ! -d ".svelte-kit" ]; then
  ./node_modules/.bin/svelte-kit sync 2>/dev/null || pnpm exec svelte-kit sync 2>/dev/null || true
fi

TSC_BIN=""
if [ -x "./node_modules/.bin/tsc" ]; then
  TSC_BIN="./node_modules/.bin/tsc"
elif [ -x "$REPO_ROOT/node_modules/.bin/tsc" ]; then
  TSC_BIN="$REPO_ROOT/node_modules/.bin/tsc"
elif [ -x "../../node_modules/.bin/tsc" ]; then
  TSC_BIN="../../node_modules/.bin/tsc"
elif command -v tsc >/dev/null 2>&1; then
  TSC_BIN="tsc"
elif command -v pnpm >/dev/null 2>&1 && { [ -f "$REPO_ROOT/node_modules/.bin/tsc" ] || [ -f "./node_modules/.bin/tsc" ]; }; then
  TSC_BIN="pnpm exec tsc"
fi

if [ -z "$TSC_BIN" ]; then
  echo "❌ [typecheck-runner] Fatal: TypeScript compiler (tsc) not found in node_modules." >&2
  exit 1
fi

exec $TSC_BIN --noEmit

