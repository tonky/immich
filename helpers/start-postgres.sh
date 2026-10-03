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
# Upstream's postgres image sorts with en_US.UTF-8; suggestion endpoints ORDER BY text and
# the e2e suite asserts that order. ICU gives it without depending on host locale archives
# (ka-shifted ignores punctuation like glibc does). A cluster from other options is rebuilt.
INITDB_ARGS="--encoding=UTF8 --locale=C.UTF-8 --locale-provider=icu --icu-locale=en-US-u-ka-shifted"
STAMP="$DATA_DIR/.initdb-args"
if [ ! -f "$DATA_DIR/PG_VERSION" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$INITDB_ARGS" ]; then
  rm -rf "$DATA_DIR"
  mkdir -p "$DATA_DIR"
  # shellcheck disable=SC2086 # INITDB_ARGS is a list of flags
  initdb -D "$DATA_DIR" -U postgres --auth=trust $INITDB_ARGS >/dev/null
  printf '%s' "$INITDB_ARGS" > "$STAMP"
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
