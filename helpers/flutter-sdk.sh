#!/usr/bin/env bash
# ==============================================================================
# flutter-sdk.sh - Runs a command with a writable Flutter SDK first on PATH
# ==============================================================================
# Flutter keeps its state inside its own root: each command stamps bin/cache
# (libimobiledevice.stamp, flutter.version.json, the lockfile) and no variable moves it.
# The environment's SDK is a read-only store path (a CI runner's host store), so this
# lays a tree of links to it once per store path in the checkout's state: directories
# and the small files Flutter rewrites are its own, everything else links to the store.
# bin/flutter is a copy too: it takes FLUTTER_ROOT from where it lies.
#
# Usage: helpers/flutter-sdk.sh <command> [args...]   (dart, flutter, dcm, a script)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

flutter="$(command -v flutter)" || {
  echo "❌ [flutter-sdk] no flutter on PATH: is it in enve.cue's profile for $(uname -m)?" >&2
  exit 1
}
store="$(cd "$(dirname "$(readlink -f "$flutter")")/.." && pwd -P)"
root="$REPO_ROOT/.enact/state/cache/flutter-sdk/${store##*/}"

if [ ! -f "$root/.enact-ready" ]; then
  mkdir -p "$REPO_ROOT/.enact/state/locks" "${root%/*}"
  exec 9>"$REPO_ROOT/.enact/state/locks/flutter-sdk.lock"
  flock 9
  if [ ! -f "$root/.enact-ready" ]; then
    rm -rf "$root" "$root.tmp"
    cp -Rs "$store/." "$root.tmp/"
    chmod -R u+w "$root.tmp"
    # Copies of what Flutter writes or resolves its root from: bin/'s scripts, and
    # bin/cache's own files (stamps, lockfile, version json) but the tool snapshot.
    find "$root.tmp/bin" "$root.tmp/bin/internal" "$root.tmp/bin/cache" -maxdepth 1 -type l \
      ! -name flutter_tools.snapshot -print0 |
      while IFS= read -r -d '' link; do
        target="$(readlink "$link")"
        [ -f "$target" ] || continue
        rm "$link"
        cp "$target" "$link"
        chmod u+w "$link"
      done
    touch "$root.tmp/.enact-ready"
    mv "$root.tmp" "$root"
  fi
  exec 9>&-
fi

export FLUTTER_ROOT="$root"
# native_core's build hook drives cargo only through rustup: helpers/rustup-shim answers
# with the env's toolchain.
export PATH="$REPO_ROOT/helpers/rustup-shim:$root/bin:$PATH"
exec "$@"
