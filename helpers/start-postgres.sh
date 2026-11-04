#!/usr/bin/env bash
# ==============================================================================
# start-postgres.sh - Rootless PostgreSQL as upstream's test image
# ==============================================================================
# Upstream tests against `ghcr.io/immich-app/postgres:14-vectorchord0.4.3`: PostgreSQL 14,
# pgvector 0.8.1, VectorChord 0.4.3 preloaded, en_US.utf8. The `postgres` on PATH is the
# server joined with both extensions (enve.cue's service `extensions`).
set -euo pipefail

DATA_DIR="${DATA_DIR:?enve sets the service data dir}"
# The image's locale (LANG=en_US.utf8): suggestion endpoints ORDER BY text and the e2e
# suite asserts that order. A cluster from another server or other options is rebuilt.
INITDB_ARGS="--encoding=UTF8 --locale=en_US.UTF-8"
STAMP="$DATA_DIR/.initdb-args"
if [ ! -f "$DATA_DIR/PG_VERSION" ] || [ "$(cat "$DATA_DIR/PG_VERSION")" != 14 ] \
  || [ "$(cat "$STAMP" 2>/dev/null)" != "$INITDB_ARGS" ]; then
  rm -rf "$DATA_DIR"
  mkdir -p "$DATA_DIR"
  # shellcheck disable=SC2086 # INITDB_ARGS is a list of flags
  initdb -D "$DATA_DIR" -U postgres --auth=trust $INITDB_ARGS >/dev/null
  echo "include 'enact.conf'" >> "$DATA_DIR/postgresql.conf"
  printf '%s' "$INITDB_ARGS" > "$STAMP"
fi

# The instance's port (enve's PORT: 5435 in the default instance, where upstream's e2e
# compose publishes it). As the command of upstream's medium globalSetup; the rest
# (max_connections = 100) is initdb's default, as the image's postgresql.conf.
cat << PGCONF > "$DATA_DIR/enact.conf"
listen_addresses = '127.0.0.1'
port = $PORT
shared_preload_libraries = 'vchord.so'
max_wal_size = 2GB
shared_buffers = 512MB
fsync = off
full_page_writes = off
synchronous_commit = off
PGCONF

exec postgres -D "$DATA_DIR" -k /tmp
