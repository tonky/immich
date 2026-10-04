#!/usr/bin/env bash
# ==============================================================================
# generate-reach-map.sh - Records .enact/trace-reach.bin, one trace per spec file
# ==============================================================================
# enact prunes a suite only when the map traced every one of its specs
# (`target_scope.tests`), so every suite is traced whole:
#   unit    server, web and cli specs: `enact trace run` records the files the vitest
#           process tree opens (JOBS at a time)
#   medium  the same, one at a time: the specs clone the shared `mich` template database
#   e2e     the same process trace, plus the server sources the real server ran while
#           the spec did: the specs reach it over HTTP, outside the traced tree, so the
#           server records V8 coverage windows (coverage-hook.cjs, reach-map.mjs)
#
# Usage: helpers/trace/generate-reach-map.sh [unit] [medium] [e2e]   (default: all, from
#        scratch; named phases re-record their specs into the last run's maps)
# Env:   JOBS (parallel unit specs, default 4) · ENACT (default bin/enact) · SETTLE (seconds
#        the server gets to finish a spec's queued jobs, default 2) · ONLY (regex: trace
#        only the matching specs, for a quick check)
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
TRACE=helpers/trace
# The checkout's own enact (the one CI runs), not whichever is on PATH: an older one
# records traces without the current map's fields.
ENACT=${ENACT:-$ROOT/bin/enact}
JOBS=${JOBS:-4}
SETTLE=${SETTLE:-2}
WORK=$ROOT/.enact/cache/trace-work
read -r -a PHASES <<<"${*:-unit medium e2e}"
export ROOT ENACT WORK

# Suites: directory · spec glob (as `target_scope.tests` names them).
SERVER_UNIT=(server 'server/src/**/*.spec.ts')
SERVER_MEDIUM=(server 'server/test/medium/**/*.spec.ts')
WEB=(web 'web/src/**/*.spec.ts')
CLI=(packages/cli 'packages/cli/src/**/*.spec.ts')
E2E=(e2e 'e2e/src/specs/server/**/*.e2e-spec.ts')

# specs <glob>: tracked spec files; ONLY (a regex) narrows them, for a quick check.
specs() {
  local spec
  git ls-files -- ":(glob)$1" | while read -r spec; do
    [[ $spec =~ ${ONLY:-.} ]] || continue
    echo "$spec"
  done
}

# trace_spec <dir> <spec>: one spec into its own map (specs trace in parallel), run as
# the test jobs run it (vitest-runner.sh picks the config and database).
trace_spec() {
  local dir=$1 spec=$2
  local name=${spec//\//__}
  if (cd "$dir" && "$ENACT" trace run --reach-file "$WORK/maps/$name.json" -t "$spec" -- \
    enve run --locked -q -f "$ROOT/enve.cue" -- "$ROOT/helpers/vitest-runner.sh" "${spec#"$dir"/}") \
    >"$WORK/logs/$name.log" 2>&1; then
    echo "  ✓ $spec"
  else
    echo "  ⚠️  $spec failed, its trace is kept: $WORK/logs/$name.log"
  fi
}
export -f trace_spec

# trace_suite <jobs> <dir> <glob>
trace_suite() {
  local jobs=$1 dir=$2 glob=$3
  echo "🔍 $glob ($(specs "$glob" | wc -l) specs, $jobs at a time)"
  specs "$glob" | xargs -P "$jobs" -I{} bash -c 'trace_spec "$@"' _ "$dir" {}
}

# services_up <service...>: starts them and their dependencies in the background.
services_up() {
  enve up --locked -q "$@" >"$WORK/logs/services-$1.log" 2>&1 &
  SERVICES=$!
  trap services_down EXIT
}

services_down() {
  [ -n "${SERVICES:-}" ] || return 0
  kill -INT "$SERVICES" 2>/dev/null || true
  wait "$SERVICES" 2>/dev/null || true
  SERVICES=
}

# await <what> <command...>: polls the command for up to 4 minutes.
await() {
  local what=$1
  shift
  for _ in $(seq 240); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "❌ $what not ready: $WORK/logs/" >&2
  exit 1
}

phase_unit() {
  trace_suite "$JOBS" "${SERVER_UNIT[@]}"
  trace_suite "$JOBS" "${WEB[@]}"
  trace_suite "$JOBS" "${CLI[@]}"
}

phase_medium() {
  services_up postgres
  await postgres enve run --locked -q -- pg_isready -h 127.0.0.1 -p 5435
  trace_suite 1 "${SERVER_MEDIUM[@]}"
  services_down
}

# Server processes: the main one and its forked api worker, by the process.title they
# set (never bubblewrap's pid, whose command line names the server too).
server_pids() { pgrep -x 'immich|immich-api'; }

# coverage_files <dir>: how many coverage files it holds.
coverage_files() {
  local files=("$1"/*.json)
  [ -e "${files[0]}" ] && echo "${#files[@]}" || echo 0
}

# take_window <name> [target]: ends a coverage window; every server thread writes one file.
take_window() {
  local dir=$WORK/windows/$1 before
  before=$(coverage_files "$COVERAGE")
  mkdir -p "$dir"
  local pids
  pids=$(server_pids) || {
    echo "❌ no server process to take coverage from" >&2
    exit 1
  }
  # shellcheck disable=SC2086 # one pid per word
  kill -USR2 $pids
  for _ in $(seq 100); do
    [ "$(coverage_files "$COVERAGE")" -ge "$((before + ${THREADS:-1}))" ] && break
    sleep 0.2
  done
  sleep 0.5 # the last file is written fully
  mv "$COVERAGE"/*.json "$dir/"
  [ $# -lt 2 ] || echo "$2" >"$dir/target"
}

phase_e2e() {
  echo "🔨 building the server, sdk and cli (the server's coverage maps to their sources)"
  enve run --locked -q -- pnpm --filter 'immich...' --filter @immich/cli run build >"$WORK/logs/build.log" 2>&1
  COVERAGE=$WORK/coverage
  rm -rf "$COVERAGE" "$WORK/windows"
  mkdir -p "$COVERAGE"
  # The e2e job's services: the oauth specs sign in at e2e-auth-server. Only the server's
  # processes get SIGUSR2; the provider writes its coverage at exit, after the last window.
  NODE_V8_COVERAGE=$COVERAGE NODE_OPTIONS="--require $ROOT/$TRACE/coverage-hook.cjs" \
    services_up immich-server e2e-auth-server
  await immich-server curl -sf http://127.0.0.1:2285/api/server/ping
  await e2e-auth-server bash -c 'exec 3<>/dev/tcp/127.0.0.1/2286'
  # Files written before the first SIGUSR2 came from processes and threads that exited
  # during start-up (build checks, boot-time workers): start-up coverage, kept in the boot
  # window, but not threads that answer the signal.
  local exited
  exited=$(coverage_files "$COVERAGE")
  take_window 000-boot
  THREADS=$(($(coverage_files "$WORK/windows/000-boot") - exited))
  echo "📡 server ready: $THREADS coverage threads"

  local i=0 spec
  while read -r spec; do
    i=$((i + 1))
    trace_spec "${E2E[0]}" "$spec"
    sleep "$SETTLE"
    take_window "$(printf %03d "$i")" "$spec"
  done < <(specs "${E2E[1]}")
  services_down
}

# A full run starts clean; a single phase replaces only its own specs' maps.
[ $# -gt 0 ] || rm -rf "$WORK/maps" "$WORK/windows"
rm -rf "$WORK/logs"
mkdir -p "$WORK/maps" "$WORK/logs"

# The specs import the built workspace packages: build them once, not in every traced run.
echo "🔨 building the workspace packages the suites import"
enve run --locked -q -- pnpm --filter 'immich^...' --filter 'immich-web^...' --filter 'immich-e2e^...' \
  --if-present run build >"$WORK/logs/build-deps.log" 2>&1
enve run --locked -q -- helpers/build-core-plugin.sh >>"$WORK/logs/build-deps.log" 2>&1
export IMMICH_WORKSPACE_DEPS_BUILT=1

for phase in "${PHASES[@]}"; do
  "phase_$phase"
done

MAP=$WORK/trace-reach.json
"$ENACT" trace pack "$WORK"/maps/*.json -o "$MAP"
if [ -d "$WORK/windows" ]; then
  enve run --locked -q -- node "$TRACE/reach-map.mjs" coverage "$MAP" "$WORK/windows"
fi
"$ENACT" trace pack "$MAP" -o .enact/trace-reach.bin
