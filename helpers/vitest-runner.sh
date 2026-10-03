#!/usr/bin/env bash
# ==============================================================================
# vitest-runner.sh - Hermetic Vitest Runner for Immich Tests
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done


if [ -f "playwright.config.ts" ] || [ -d "src/specs" ]; then
  export IMMICH_TEST_POSTGRES_URL="postgres://postgres:postgres@127.0.0.1:5432/immich"
else
  export IMMICH_TEST_POSTGRES_URL="${IMMICH_TEST_POSTGRES_URL:-postgres://postgres@127.0.0.1:5432/mich}"
fi

TARGETS=("$@")

VITEST_CMD=()
if [ -x "./node_modules/.bin/vitest" ]; then
  VITEST_CMD=("./node_modules/.bin/vitest")
elif [ -x "$REPO_ROOT/node_modules/.bin/vitest" ]; then
  VITEST_CMD=("$REPO_ROOT/node_modules/.bin/vitest")
elif [ -x "../../node_modules/.bin/vitest" ]; then
  VITEST_CMD=("../../node_modules/.bin/vitest")
elif command -v vitest >/dev/null 2>&1; then
  VITEST_CMD=("vitest")
elif [ -d "node_modules" ] || [ -d "$REPO_ROOT/node_modules" ]; then
  VITEST_CMD=("pnpm" "exec" "vitest")
fi

if [ ${#VITEST_CMD[@]} -eq 0 ]; then
  echo "❌ [vitest-runner] Fatal: Vitest test runner not found (node_modules or vitest missing)." >&2
  exit 1
fi

# The specs import the built workspace dependencies (sdk, plugin-sdk, cli).
"$REPO_ROOT/helpers/build-workspace-deps.sh"

# With no targets every shard would run the whole suite: let vitest split it instead.
# (With targets, enact already handed each shard its own slice.)
SHARD_ARGS=()
if [ ${#TARGETS[@]} -eq 0 ] && [ "${ENACT_SHARD_TOTAL:-1}" -gt 1 ]; then
  # A shard may draw no files when there are fewer files than shards.
  SHARD_ARGS=("--shard=${ENACT_SHARD_INDEX:?}/${ENACT_SHARD_TOTAL}" --passWithNoTests)
fi

vitest_run() {
  "${VITEST_CMD[@]}" run "${SHARD_ARGS[@]}" "$@"
}

# The server keeps unit and medium (database) specs under separate configs.
if [ -f "test/vitest.config.mjs" ] && [ -f "test/vitest.config.medium.mjs" ]; then
  if [ ${#TARGETS[@]} -eq 0 ]; then
    vitest_run --config test/vitest.config.mjs
    vitest_run --config test/vitest.config.medium.mjs
    exit 0
  fi
  unit_targets=()
  medium_targets=()
  for t in "${TARGETS[@]}"; do
    case "$t" in
      test/medium/*) medium_targets+=("$t") ;;
      *) unit_targets+=("$t") ;;
    esac
  done
  if [ ${#unit_targets[@]} -gt 0 ]; then
    vitest_run --config test/vitest.config.mjs "${unit_targets[@]}"
  fi
  if [ ${#medium_targets[@]} -gt 0 ]; then
    vitest_run --config test/vitest.config.medium.mjs "${medium_targets[@]}"
  fi
else
  vitest_run "${TARGETS[@]}"
fi
