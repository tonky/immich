#!/usr/bin/env bash
# ==============================================================================
# schema-check-runner.sh - Zero-Docker SQL Schema & Migrations Verification
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

export DB_URL="${DB_URL:-postgres://postgres@127.0.0.1:${DB_PORT}/immich}"

echo "🔍 [schema-check] Verifying migration execution order..."
(cd "$REPO_ROOT/server" && pnpm run migrations:verify-order)

"$REPO_ROOT/helpers/build-if-stale.sh" 'immich...' server/dist

echo "🔍 [schema-check] Applying migrations against zero-docker PostgreSQL..."
(cd "$REPO_ROOT/server" && pnpm run migrations:run)

echo "🔍 [schema-check] Checking for ungenerated schema migrations..."
trap 'rm -f "$REPO_ROOT/server/src"/*-TestMigration.ts' EXIT
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
