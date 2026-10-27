#!/usr/bin/env bash
# ==============================================================================
# generate-reach-map.sh - Records the reach map into the reach store, one trace per spec file
# ==============================================================================
# enact prunes a suite only when the map traced every one of its specs
# (`target_scope.tests`), so every suite is traced whole:
#   unit    server, web and cli specs: `enact trace run` records the files the vitest
#           process tree opens (JOBS at a time)
#   medium  the same, one at a time: the specs clone the shared `mich` template database
#   e2e     the same process trace, plus the server sources the real server ran while
#           the spec did: the specs reach it over HTTP, outside the traced tree, so the
#           server records V8 coverage windows (coverage-hook.cjs, reach-map.mjs)
# The services the medium and e2e specs run are traced too (`enact trace service`): what
# they read at start-up and outside the coverage windows (their launchers, the environment),
# and each spec records them as its services, so a change to those reaches it.
#
# Incremental: over the stored map at HEAD (or an ancestor), only the specs `enact trace stale`
# lists are traced (untraced, failed, or a file, directory or service they used changed
# since), and their traces replace theirs in it; a phase with none starts nothing.
# A phase's traces are fingerprinted once all of them finished: parallel web specs each
# regenerate web/.svelte-kit, which they read, so a digest taken as one spec ended could
# catch a sibling's half-written file.
#
# Usage: helpers/trace/generate-reach-map.sh [unit] [medium] [e2e]   (default: all)
# Env:   JOBS (parallel unit specs, default 4) · ENACT_EXE (set in enact tasks), else ENACT_BIN (default: enact on PATH) · SETTLE (seconds
#        the server gets to finish a spec's queued jobs, default 2) · ONLY (regex: trace
#        only the matching specs, for a quick check) · FULL=1 (trace every spec, from
#        scratch: a map of only what this run traced)
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
TRACE=helpers/trace
# The checkout's own enact (the one CI runs), not whichever is on PATH: an older one
# records traces without the current map's fields.
ENACT=${ENACT_EXE:-${ENACT_BIN:-$(command -v enact || true)}}
[ -n "$ENACT" ] || { echo "generate-reach-map.sh: no enact on PATH: put it there or set ENACT_BIN" >&2; exit 2; }
JOBS=${JOBS:-4}
SETTLE=${SETTLE:-2}
WORK=$ROOT/.enact/state/cache/trace-work
# The map is recorded into the reach store (`enact trace store where`), over the stored
# map selected at HEAD unless FULL.
BASE=
[ -n "${FULL:-}" ] || BASE=$("$ENACT" trace store where --path)
read -r -a PHASES <<<"${*:-unit medium e2e}"
ENACT_BIN=$ENACT
export ROOT ENACT ENACT_BIN WORK TRACE
# shellcheck source=own-pids.sh
. "$TRACE/own-pids.sh"

# Suites: directory · spec glob (as `target_scope.tests` names them).
SERVER_UNIT=(server 'server/src/**/*.spec.ts')
SERVER_MEDIUM=(server 'server/test/medium/**/*.spec.ts')
WEB=(web 'web/src/**/*.spec.ts')
CLI=(packages/cli 'packages/cli/src/**/*.spec.ts')
SCRIPTS=(packages/scripts 'packages/scripts/src/**/*.spec.ts')
ML=(machine-learning 'machine-learning/test_*.py')
E2E=(e2e 'e2e/src/specs/server/**/*.e2e-spec.ts')

# specs <glob>: tracked spec files; ONLY (a regex) narrows them, for a quick check.
specs() {
  local spec
  git ls-files -- ":(glob)$1" | while read -r spec; do
    [[ $spec =~ ${ONLY:-.} ]] || continue
    echo "$spec"
  done
}

lines() { if [ -n "$1" ]; then wc -l <<<"$1" | tr -d ' '; else echo 0; fi; }

# to_trace <glob>: the specs to trace (every one, or the stale ones over BASE), counted
# on stderr. Run after the builds the specs read: their outputs are in the footprints.
# Fails when `enact trace stale` does (its reasons go to the log): an error must not read
# as nothing to trace.
to_trace() {
  local all stale
  all=$(specs "$1")
  stale=$all
  if [ -n "$BASE" ] && [ -n "$all" ]; then
    if ! stale=$(xargs "$ENACT" trace stale --reach-file "$BASE" <<<"$all" 2>>"$WORK/logs/stale.log"); then
      echo "❌ enact trace stale failed for $1: $WORK/logs/stale.log" >&2
      return 1
    fi
  fi
  echo "🔍 $1: $(lines "$stale") of $(lines "$all") specs to trace" >&2
  [ -z "$stale" ] || echo "$stale"
}

# trace_spec <spec>: one spec into its own map in the phase's MAPS (specs trace in
# parallel, fingerprinted with the phase), running it as its test job does
# (trace-test.sh: its package's directory, vitest-runner.sh, its suite's services).
trace_spec() {
  local spec=$1
  local name=${spec//\//__}
  if "$ROOT/$TRACE/trace-test.sh" "$MAPS/$name.json" "$spec" >"$WORK/logs/$name.log" 2>&1; then
    echo "  ✓ $spec"
  else
    echo "  ⚠️  $spec failed, its trace is kept: $WORK/logs/$name.log"
  fi
}
export -f trace_spec

# trace_specs <jobs> <specs>: the specs (one per line), jobs at a time.
trace_specs() {
  [ -n "$2" ] || return 0
  xargs -P "$1" -I{} bash -c 'trace_spec "$@"' _ {} <<<"$2"
}

# services_up <service...>: starts them and their dependencies in the background, traced
# as SERVICE_DEPS (the services the specs run, dependencies included), and waits until
# enve says every one is ready (its probes and postStart hooks: immich-server's waits for
# the geodata import). Stopping enact stops them, and it records what they read once they
# exit. Stopped before enve's ready, `enve up` exits 1 (an interrupted start) and their
# traces are incomplete: a port answering is not enough.
services_up() {
  local log=$WORK/logs/services-$1.log
  # shellcheck disable=SC2086 # a list of names
  "$ENACT" trace service ${SERVICE_DEPS:?} --reach-file "$MAPS/services-$1.json" -- \
    enve up --locked "$@" >"$log" 2>&1 &
  SERVICES=$!
  trap services_down EXIT
  for _ in $(seq 300); do
    grep -q "services are running and ready" "$log" && return 0
    kill -0 "$SERVICES" 2>/dev/null || break
    sleep 1
  done
  echo "❌ $* not ready: $log" >&2
  exit 1
}

# services_down: stops them; a trace that didn't end on that stop (incomplete) fails the run.
services_down() {
  [ -n "${SERVICES:-}" ] || return 0
  local status=0
  kill -INT "$SERVICES" 2>/dev/null || true
  wait "$SERVICES" 2>/dev/null || status=$?
  SERVICES=
  [ "$status" = 0 ] || { echo "❌ the services' trace is incomplete (exit $status): $WORK/logs/" >&2; exit 1; }
}

phase_unit() {
  local suite stale
  for suite in "${SERVER_UNIT[1]}" "${WEB[1]}" "${CLI[1]}" "${SCRIPTS[1]}" "${ML[1]}"; do
    stale=$(to_trace "$suite") || exit 1
    trace_specs "$JOBS" "$stale"
  done
}

phase_medium() {
  local stale
  stale=$(to_trace "${SERVER_MEDIUM[1]}") || exit 1
  [ -n "$stale" ] || return 0
  export SERVICE_DEPS=postgres
  services_up postgres
  trace_specs 1 "$stale"
  services_down
  unset SERVICE_DEPS
}

# This run's server processes: the main one and its forked api worker, by the
# process.title they set (never bubblewrap's pid, whose command line names the server
# too), under this run's services only: another checkout's server would die of SIGUSR2.
server_pids() { own_pids "${SERVICES:?}" immich immich-api; }

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
  # Built here, untraced: under IMMICH_WORKSPACE_DEPS_BUILT the server's launcher skips
  # its staleness checks, which hash every source the builds read, so the traced service
  # records what the server reads to run. The coverage windows map what it ran to sources.
  echo "🔨 building the server, web, sdk and cli (the server's coverage maps to their sources)"
  {
    env -u IMMICH_WORKSPACE_DEPS_BUILT enve run --locked -q -- helpers/build-if-stale.sh 'immich...' server/dist
    env -u IMMICH_WORKSPACE_DEPS_BUILT enve run --locked -q -- helpers/build-if-stale.sh 'immich-web...' web/build i18n
    enve run --locked -q -- pnpm --filter @immich/cli run build
  } >"$WORK/logs/build.log" 2>&1
  local stale
  stale=$(to_trace "${E2E[1]}") || exit 1
  [ -n "$stale" ] || return 0
  COVERAGE=$WORK/coverage
  rm -rf "$COVERAGE" "$WORK/windows"
  mkdir -p "$COVERAGE"
  # The e2e job's services: the oauth specs sign in at e2e-auth-server. Only the server's
  # processes get SIGUSR2; the provider writes its coverage at exit, after the last window.
  export SERVICE_DEPS="immich-server e2e-auth-server postgres valkey"
  NODE_V8_COVERAGE=$COVERAGE NODE_OPTIONS="--require $ROOT/$TRACE/coverage-hook.cjs" \
    services_up immich-server e2e-auth-server
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
    trace_spec "$spec"
    sleep "$SETTLE"
    take_window "$(printf %03d "$i")" "$spec"
  done <<<"$stale"
  services_down
  unset SERVICE_DEPS
}

# This run's traces only: they are laid over BASE.
rm -rf "$WORK/maps" "$WORK/windows" "$WORK/logs"
mkdir -p "$WORK/maps" "$WORK/logs"

# The specs import the built workspace packages: build them once, not in every traced run.
echo "🔨 building the workspace packages the suites import"
enve run --locked -q -- pnpm --filter 'immich^...' --filter 'immich-web^...' --filter 'immich-e2e^...' \
  --if-present run build >"$WORK/logs/build-deps.log" 2>&1
enve run --locked -q -- helpers/build-core-plugin.sh >>"$WORK/logs/build-deps.log" 2>&1
export IMMICH_WORKSPACE_DEPS_BUILT=1

for phase in "${PHASES[@]}"; do
  export MAPS=$WORK/maps/$phase
  mkdir -p "$MAPS"
  "phase_$phase"
  phase_maps=("$MAPS"/*.json)
  if [ -e "${phase_maps[0]}" ]; then
    "$ENACT" trace pack --fingerprint "${phase_maps[@]}" -o "$WORK/maps/$phase.json" >/dev/null
  fi
done

maps=("$WORK"/maps/*.json)
if [ ! -e "${maps[0]}" ]; then
  echo "✅ every spec's trace is current: the stored map is unchanged"
  exit 0
fi
MAP=$WORK/trace-reach.json
"$ENACT" trace pack "${maps[@]}" -o "$MAP"
if [ -d "$WORK/windows" ]; then
  enve run --locked -q -- node "$TRACE/reach-map.mjs" coverage "$MAP" "$WORK/windows"
fi
# The traces the coverage step extended (and the services two phases traced) get their
# digest here, then they replace theirs in BASE.
"$ENACT" trace pack --fingerprint ${BASE:+--base "$BASE"} "$MAP" -o "$WORK/reach.bin"
"$ENACT" trace store put "$WORK/reach.bin"
