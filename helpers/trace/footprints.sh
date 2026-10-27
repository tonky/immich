#!/usr/bin/env bash
# ==============================================================================
# footprints.sh <runner> <target...> - Runs a test job's targets, recording footprints
# ==============================================================================
# Recording while running: enact sets ENACT_FOOTPRINT_DIR in a shard's
# task when it wants footprints from it (`enact run`: the tests its map lacks, holds aged
# or failing, or the change reaches, listed in ENACT_FOOTPRINT_TARGETS; `enact trace
# record`: every test, no list). vitest-runner.sh hands such a task's targets here, and the
# shard runs once, traced (trace-files.sh): one vitest run, a forked worker per spec, each
# spec's footprint attributed from its worker's reads, the modules vitest loaded for it and
# the run's shared reads (`enact trace run --attribution`). The wanted specs' footprints go
# to ENACT_FOOTPRINT_DIR, each with its outcome (`"outcomes": true`; a failed or cut-short
# spec is incomplete), so the passing specs of a failed shard still land.
# The shared start-up (the workspace builds the specs import) runs once, untraced, first,
# as generate-reach-map.sh builds before it traces: the footprints hold what the specs
# read, not a build.
#
# Not recorded here: the e2e specs, which enact traces itself one by one (their job's
# `recorder: "trace"`), and anything off Linux: `enact trace run` traces with seccomp, and
# off Linux it fails (there is no file tracer), so the specs run untraced.
# A run the tracer couldn't start (no map written) runs untraced.
#
# Env: ENACT_FOOTPRINT_DIR · ENACT_FOOTPRINT_TARGETS · ENACT_EXE, ENACT_BIN (as trace-files.sh)
set -uo pipefail

RUNNER=$1
shift
OUT=${ENACT_FOOTPRINT_DIR:?}
LISTED=${ENACT_FOOTPRINT_TARGETS:-}
unset ENACT_FOOTPRINT_DIR ENACT_FOOTPRINT_TARGETS

if [ "$(uname -s)" != Linux ]; then
  exec "$RUNNER" "$@"
fi

ROOT=$(git rev-parse --show-toplevel)
ENACT=${ENACT_EXE:-${ENACT_BIN:-$(command -v enact || true)}}
[ -n "$ENACT" ] || { echo "footprints.sh: no enact on PATH: put it there or set ENACT_BIN" >&2; exit 2; }
export ROOT ENACT

PKG=$(realpath -m --relative-to="$ROOT" "$PWD")
[ "$PKG" = . ] && PKG= || PKG=$PKG/

# Whether enact wants a footprint of any spec this run runs: a listed one under this
# package (no list: every spec). The e2e package isn't recorded.
WANTED=0
MEDIUM=0
if [ "$PKG" != e2e/ ]; then
  if [ -z "$LISTED" ]; then
    WANTED=1
  elif [ $# -eq 0 ]; then
    awk -v p="$PKG" 'index($0, p) == 1 { found = 1; exit } END { exit !found }' "$LISTED" && WANTED=1
  else
    for target in "$@"; do
      spec=$(realpath -m --relative-to="$ROOT" "$PWD/${target%%::*}")
      if awk -v t="$spec" '$0 == t || index($0, t "::") == 1 || index($0, t "/") == 1 { found = 1; exit } END { exit !found }' "$LISTED"; then
        WANTED=1
      fi
    done
  fi
fi
if [ "$WANTED" = 0 ]; then
  exec "$RUNNER" "$@"
fi
for target in "$@"; do
  [[ $(realpath -m --relative-to="$ROOT" "$PWD/$target") != server/test/medium* ]] || MEDIUM=1
done
# The whole server suite runs its medium specs too.
[ $# -gt 0 ] || [ "$PKG" != server/ ] || MEDIUM=1

# The shared start-up, once: the workspace packages the specs import and, for the medium
# specs, the core plugin. The traced run then skips their builds.
"$ROOT/helpers/build-workspace-deps.sh" || exit
if [ "$MEDIUM" = 1 ]; then
  "$ROOT/helpers/build-core-plugin.sh" || exit
fi
export IMMICH_WORKSPACE_DEPS_BUILT=1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/enact-footprints.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo "🎙️  [footprints] tracing the shard's specs for enact's reach map, with $ENACT"
status=0
# The medium specs clone the shared `mich` template database: their footprints hold it.
SERVICE_DEPS=$([ "$MEDIUM" = 1 ] && echo postgres) \
  "$ROOT/helpers/trace/trace-files.sh" "$WORK/shard.json" "$@" || status=$?
if [ ! -s "$WORK/shard.json" ]; then
  echo "⚠️  [footprints] the shard wasn't traced: it runs untraced" >&2
  exec "$RUNNER" "$@"
fi

# Hands enact the wanted specs' footprints: postgres only for the medium specs, each with
# its outcome.
node -e '
  const fs = require("fs");
  const [from, to, listed] = process.argv.slice(1);
  const map = JSON.parse(fs.readFileSync(from, "utf8"));
  const list = listed ? fs.readFileSync(listed, "utf8").split("\n").filter(Boolean) : null;
  const wanted = (t) => !list || list.some((l) => l === t || l.startsWith(t + "::") || l.startsWith(t + "/"));
  for (const target of Object.keys(map.targets || {})) {
    if (!wanted(target) || target.startsWith("e2e/")) {
      delete map.targets[target];
      if (map.target_service_deps) delete map.target_service_deps[target];
    }
  }
  for (const target of Object.keys(map.target_service_deps || {})) {
    if (!target.startsWith("server/test/medium/")) delete map.target_service_deps[target];
  }
  map.outcomes = true;
  fs.writeFileSync(to + ".part", JSON.stringify(map));
  fs.renameSync(to + ".part", to);
  for (const [target, fp] of Object.entries(map.targets || {})) {
    const complete = fp.outcome === undefined;
    console.log(`🎯 [footprints] recorded \x27${target}\x27 (${complete ? "complete" : "incomplete"})`);
  }
' "$WORK/shard.json" "$OUT/shard-${ENACT_SHARD_INDEX:-1}-$$.json" "$LISTED" || status=1
exit "$status"
