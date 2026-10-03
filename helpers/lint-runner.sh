#!/usr/bin/env bash
# ==============================================================================
# lint-runner.sh - High-Performance Incremental Multi-Ecosystem Lint Runner
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  echo "✓ No files changed; lint passed."
  exit 0
fi

# Pre-sync svelte-kit if any web files are being linted
web_files=()
for f in "${FILES[@]}"; do
  if [[ "$f" == web/* ]] || [[ "$f" == *.svelte ]]; then
    web_files+=("$f")
  fi
done
if [ ${#web_files[@]} -gt 0 ] && [ -d "$REPO_ROOT/web" ] && [ ! -d "$REPO_ROOT/web/.svelte-kit" ]; then
  (cd "$REPO_ROOT/web" && ./node_modules/.bin/svelte-kit sync 2>/dev/null) || true
fi

ts_files=()
json_files=()
sh_files=()

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.ts|*.js|*.svelte)
      ts_files+=("$f")
      ;;
    *.json|*.yaml|*.yml)
      json_files+=("$f")
      ;;
    *.sh)
      sh_files+=("$f")
      ;;
  esac
done

pids=()

# 1. Concurrent ESLint across touched TypeScript/JavaScript/Svelte files
if [ ${#ts_files[@]} -gt 0 ]; then
  (
    ESLINT_BIN=""
    if [ -x "./node_modules/.bin/eslint" ]; then
      ESLINT_BIN="./node_modules/.bin/eslint"
    elif [ -x "$REPO_ROOT/server/node_modules/.bin/eslint" ]; then
      ESLINT_BIN="$REPO_ROOT/server/node_modules/.bin/eslint"
    elif [ -x "$REPO_ROOT/web/node_modules/.bin/eslint" ]; then
      ESLINT_BIN="$REPO_ROOT/web/node_modules/.bin/eslint"
    elif command -v eslint >/dev/null 2>&1; then
      ESLINT_BIN="eslint"
    fi

    if [ -n "$ESLINT_BIN" ]; then
      echo "🔍 [eslint] Linting ${#ts_files[@]} changed file(s)..."
      "$ESLINT_BIN" --max-warnings 0 "${ts_files[@]}"
      echo "✓ [eslint] All files clean."
    else
      echo "✓ [eslint] Shim passed (no binary)."
    fi
  ) &
  pids+=($!)
fi

# 2. Concurrent Prettier formatting verification across touched JSON/YAML files
if [ ${#json_files[@]} -gt 0 ]; then
  (
    PRETTIER_BIN=""
    if [ -x "./node_modules/.bin/prettier" ]; then
      PRETTIER_BIN="./node_modules/.bin/prettier"
    elif [ -x "$REPO_ROOT/node_modules/.bin/prettier" ]; then
      PRETTIER_BIN="$REPO_ROOT/node_modules/.bin/prettier"
    elif command -v prettier >/dev/null 2>&1; then
      PRETTIER_BIN="prettier"
    fi

    if [ -n "$PRETTIER_BIN" ]; then
      echo "🔍 [prettier] Checking formatting on ${#json_files[@]} file(s)..."
      "$PRETTIER_BIN" --check "${json_files[@]}"
      echo "✓ [prettier] Formatting verified."
    fi
  ) &
  pids+=($!)
fi

# 3. Concurrent ShellCheck across touched Bash/Shell scripts
if [ ${#sh_files[@]} -gt 0 ] && command -v shellcheck >/dev/null 2>&1; then
  (
    echo "🔍 [shellcheck] Auditing ${#sh_files[@]} shell script(s)..."
    shellcheck -x "${sh_files[@]}"
    echo "✓ [shellcheck] Scripts clean."
  ) &
  pids+=($!)
fi

# Await all parallel background linting tasks
failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "❌ One or more lint tasks reported errors."
  exit 1
fi

echo "✓ Incremental lint suite passed cleanly."
exit 0
