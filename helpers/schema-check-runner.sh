#!/usr/bin/env bash
# ==============================================================================
# schema-check-runner.sh - Zero-Docker SQL Schema & Migrations Verification
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

export DB_URL="${DB_URL:-postgres://postgres@127.0.0.1:5432/immich}"

echo "🔍 [schema-check] Verifying migration execution order..."
(cd "$REPO_ROOT/server" && pnpm run migrations:verify-order)

echo "🔍 [schema-check] Applying migrations against zero-docker PostgreSQL..."
(cd "$REPO_ROOT/server" && pnpm run migrations:run)

echo "✓ SQL schema and migrations verified."
