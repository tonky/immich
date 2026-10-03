#!/usr/bin/env bash
# ==============================================================================
# start-postgres.sh - Hermetic Rootless PostgreSQL Daemon with pgvector
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

DATA_DIR="${DATA_DIR:-/tmp/immich-postgres-data}"
if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
  mkdir -p "$DATA_DIR"
  initdb -D "$DATA_DIR" -U postgres --auth=trust >/dev/null 2>&1
fi

# Configure extension paths for user-space pgvector
PG_CONF="$DATA_DIR/postgresql.conf"
sed -i '/extension_control_path/d' "$PG_CONF" 2>/dev/null || true
sed -i '/dynamic_library_path/d' "$PG_CONF" 2>/dev/null || true

cat << PGCONF >> "$PG_CONF"
listen_addresses = '127.0.0.1'
port = 5432
fsync = off
synchronous_commit = off
shared_buffers = 64MB
work_mem = 16MB
max_connections = 50
extension_control_path = '$REPO_ROOT/helpers/pgvector/share:\$system'
dynamic_library_path = '\$libdir:$REPO_ROOT/helpers/pgvector/lib'
PGCONF

exec postgres -D "$DATA_DIR" -k /tmp
