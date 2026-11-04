#!/usr/bin/env bash
# ==============================================================================
# schema-check-runner.sh - Zero-Docker SQL Schema & Migrations Verification
# ==============================================================================
set -euo pipefail

ORDER_ONLY=0
if [ "${1:-}" = "--order-only" ]; then
  ORDER_ONLY=1
  shift
fi

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

baseline_order=""
cleanup() {
  if [ -n "$baseline_order" ]; then
    rm -f "$baseline_order"
  fi
  rm -f "$REPO_ROOT/server/src"/*-TestMigration.ts
}
trap cleanup EXIT

echo "🔍 [schema-check] Verifying migration execution order..."
if [ -n "${IMMICH_BASELINE_ORDER:-}" ] && [ -f "$IMMICH_BASELINE_ORDER" ]; then
  (cd "$REPO_ROOT/server" && pnpm run migrations:verify-order --append-only-from "$IMMICH_BASELINE_ORDER")
elif git -C "$REPO_ROOT" rev-parse --verify "${IMMICH_BASE_REF:-HEAD~1}:server/src/schema/migrations/ORDER" >/dev/null 2>&1; then
  baseline_order="$(mktemp "${TMPDIR:-/tmp}/immich-baseline-order.XXXXXX")"
  git -C "$REPO_ROOT" show "${IMMICH_BASE_REF:-HEAD~1}:server/src/schema/migrations/ORDER" >"$baseline_order"
  (cd "$REPO_ROOT/server" && pnpm run migrations:verify-order --append-only-from "$baseline_order")
else
  (cd "$REPO_ROOT/server" && pnpm run migrations:verify-order)
fi

if [ "$ORDER_ONLY" -eq 1 ]; then
  echo "✓ Migration execution order verified."
  exit 0
fi

export DB_URL="${DB_URL:-postgres://postgres@127.0.0.1:${DB_PORT}/immich}"

"$REPO_ROOT/helpers/build-if-stale.sh" 'immich...' server/dist

echo "🔍 [schema-check] Applying migrations against zero-docker PostgreSQL..."
(cd "$REPO_ROOT/server" && pnpm run migrations:run)

echo "🔍 [schema-check] Checking for ungenerated schema migrations..."
rm -f "$REPO_ROOT/server/src"/*-TestMigration.ts
(cd "$REPO_ROOT/server" && pnpm run migrations:generate src/TestMigration)
shopt -s nullglob
generated=("$REPO_ROOT/server/src"/*-TestMigration.ts)
if [ "${#generated[@]}" -gt 0 ]; then
  echo "❌ [schema-check] Generated migration files not up to date: ${generated[*]}" >&2
  cat "${generated[@]}" >&2
  exit 1
fi

echo "✓ SQL schema and migrations verified."
