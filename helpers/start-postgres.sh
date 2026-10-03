#!/usr/bin/env bash
# ==============================================================================
# start-postgres.sh - Rootless PostgreSQL as upstream's test image
# ==============================================================================
# Upstream tests against `ghcr.io/immich-app/postgres:14-vectorchord0.4.3`: PostgreSQL 14,
# pgvector 0.8.1, VectorChord 0.4.3 preloaded, en_US.utf8. PostgreSQL 14 reads extensions
# from its own share/ and lib/ only (no extension_control_path before 18), so this builds
# a prefix as nixpkgs' withPackages does: the server's tree as symlinks (postgres finds
# share/ from the path it runs as) plus the pinned extensions (tools.lock).
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

PG_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v postgres)")")")"
PGVECTOR="$("$REPO_ROOT/helpers/pinned-tool.sh" pgvector)"
VCHORD="$("$REPO_ROOT/helpers/pinned-tool.sh" vchord)"
PREFIX="$REPO_ROOT/.enact/cache/postgres-prefix"
PREFIX_STAMP="$PG_HOME $PGVECTOR $VCHORD"
if [ "$(cat "$PREFIX/.stamp" 2>/dev/null)" != "$PREFIX_STAMP" ]; then
  rm -rf "$PREFIX"
  mkdir -p "$PREFIX"
  cp -rs "$PG_HOME/." "$PREFIX/"
  chmod -R u+w "$PREFIX"
  ln -s "$PGVECTOR"/usr/lib/postgresql/14/lib/vector.so "$VCHORD"/pkglibdir/vchord.so "$PREFIX/lib/"
  ln -s "$PGVECTOR"/usr/share/postgresql/14/extension/* "$VCHORD"/sharedir/extension/* \
    "$PREFIX/share/postgresql/extension/"
  printf '%s' "$PREFIX_STAMP" > "$PREFIX/.stamp"
fi
export PATH="$PREFIX/bin:$PATH"

DATA_DIR="${DATA_DIR:-/tmp/immich-postgres-data}"
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

# As the command of upstream's medium globalSetup; the rest (max_connections = 100) is
# initdb's default, as the image's postgresql.conf.
cat << PGCONF > "$DATA_DIR/enact.conf"
listen_addresses = '127.0.0.1'
port = 5435
shared_preload_libraries = 'vchord.so'
max_wal_size = 2GB
shared_buffers = 512MB
fsync = off
full_page_writes = off
synchronous_commit = off
PGCONF

exec postgres -D "$DATA_DIR" -k /tmp
