#!/usr/bin/env bash
# ==============================================================================
# playwright-runner.sh - Hermetic Playwright Runner for Immich Web E2E Tests
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

TARGETS=("$@")

PATH="$PWD/node_modules/.bin:$REPO_ROOT/node_modules/.bin:$REPO_ROOT/helpers/container/path:$PATH"
export PATH

PW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/immich-e2e-pw.XXXXXX")"
TMPDIR="$PW_TMP"
export TMPDIR
trap 'rm -rf "$PW_TMP"' EXIT

export PLAYWRIGHT_DISABLE_WEBSERVER=true
export PLAYWRIGHT_HTML_OPEN=never

PLAYWRIGHT_CMD=()
if [ -x "./node_modules/.bin/playwright" ]; then
  PLAYWRIGHT_CMD=("./node_modules/.bin/playwright")
elif [ -x "$REPO_ROOT/node_modules/.bin/playwright" ]; then
  PLAYWRIGHT_CMD=("$REPO_ROOT/node_modules/.bin/playwright")
elif [ -x "../../node_modules/.bin/playwright" ]; then
  PLAYWRIGHT_CMD=("../../node_modules/.bin/playwright")
elif command -v playwright >/dev/null 2>&1; then
  PLAYWRIGHT_CMD=("playwright")
elif [ -d "node_modules" ] || [ -d "$REPO_ROOT/node_modules" ]; then
  PLAYWRIGHT_CMD=("pnpm" "exec" "playwright")
fi

if [ ${#PLAYWRIGHT_CMD[@]} -eq 0 ]; then
  echo "❌ [playwright-runner] Fatal: Playwright test runner not found (node_modules or playwright missing)." >&2
  exit 1
fi

# The specs import the built workspace dependencies (sdk, plugin-sdk, cli).
"$REPO_ROOT/helpers/build-workspace-deps.sh"

SHARD_ARGS=()
if [ ${#TARGETS[@]} -eq 0 ] && [ "${ENACT_SHARD_TOTAL:-1}" -gt 1 ]; then
  SHARD_ARGS=("--shard=${ENACT_SHARD_INDEX:?}/${ENACT_SHARD_TOTAL}")
  [ "$ENACT_SHARD_INDEX" -le 1 ] || SHARD_ARGS+=(--pass-with-no-tests)
fi

playwright_run() {
  "${PLAYWRIGHT_CMD[@]}" test --reporter=list --output="$PW_TMP/test-results" "${SHARD_ARGS[@]}" "$@"
}

if [ ${#TARGETS[@]} -eq 0 ]; then
  playwright_run --project=web
  playwright_run --project=ui
  playwright_run --project=maintenance
  exit 0
fi

web_targets=()
ui_targets=()
maintenance_targets=()
other_targets=()
for t in "${TARGETS[@]}"; do
  rel="${t#./}"
  rel="${rel#e2e/}"
  case "$rel" in
    src/specs/web/*) web_targets+=("$rel") ;;
    src/ui/specs/*) ui_targets+=("$rel") ;;
    src/specs/maintenance/web/*) maintenance_targets+=("$rel") ;;
    *) other_targets+=("$t") ;;
  esac
done

if [ ${#web_targets[@]} -gt 0 ]; then
  playwright_run --project=web "${web_targets[@]}"
fi
if [ ${#ui_targets[@]} -gt 0 ]; then
  playwright_run --project=ui "${ui_targets[@]}"
fi
if [ ${#maintenance_targets[@]} -gt 0 ]; then
  playwright_run --project=maintenance "${maintenance_targets[@]}"
fi
if [ ${#other_targets[@]} -gt 0 ]; then
  playwright_run --project=web "${other_targets[@]}"
fi
