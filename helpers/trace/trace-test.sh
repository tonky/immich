#!/usr/bin/env bash
# ==============================================================================
# trace-test.sh <map> <spec> - Traces one spec into <map> (an enact reach map, JSON)
# ==============================================================================
# The per-spec way a spec is traced: generate-reach-map.sh calls it for every spec it
# traces, while footprints.sh uses trace-files.sh to trace a shard's specs in one batch with
# `--attribution` during `enact run` and `enact trace record`.
#
# `enact trace run` records the files the process tree opens while the spec runs as its
# test job runs it: from its package's directory, through vitest-runner.sh in the
# repository's environment (vitest-runner.sh picks the config and database). The services
# a spec uses are recorded as its own (`--service-dep`), so a change to them reaches it.
# Exits as the spec did; a spec that fails is recorded incomplete.
#
# Env: ENACT_EXE (the enact running the task, which sets it), else ENACT_BIN (default: enact on
#      PATH)
set -euo pipefail

MAP=$1
SPEC=$2
ROOT=$(git rev-parse --show-toplevel)
ENACT=${ENACT_EXE:-${ENACT_BIN:-$(command -v enact || true)}}
[ -n "$ENACT" ] || { echo "trace-test.sh: no enact on PATH: put it there or set ENACT_BIN" >&2; exit 2; }

# The package the spec belongs to: the nearest directory with a package.json or pyproject.toml.
DIR=$(dirname "$SPEC")
while [ "$DIR" != . ] && [ ! -f "$ROOT/$DIR/package.json" ] && [ ! -f "$ROOT/$DIR/pyproject.toml" ]; do
  DIR=$(dirname "$DIR")
done

# The services the spec's suite runs against, as their jobs declare them: the medium specs
# clone the `mich` template database; the e2e specs drive the real server and sign in at
# e2e-auth-server, one after another in the TMPDIR they share (cli/login expects
# /tmp/immich/auth.yml where the cli writes under os.tmpdir()).
FLAGS=()
RUNNER="$ROOT/helpers/vitest-runner.sh"
case "$SPEC" in
  machine-learning/*) RUNNER="$ROOT/helpers/pytest-runner.sh" ;;
  server/test/medium/*) FLAGS=(--service-dep postgres) ;;
  e2e/*)
    FLAGS=(--shared-tmpdir)
    for service in immich-server e2e-auth-server postgres valkey; do FLAGS+=(--service-dep "$service"); done
    ;;
esac

cd "$ROOT/$DIR"
exec "$ENACT" trace run --no-fingerprint --node-functions --reach-file "$MAP" -t "$SPEC" "${FLAGS[@]}" -- \
  enve run --locked -q -f "$ROOT/enve.cue" -- "$RUNNER" "${SPEC#"$DIR"/}"
