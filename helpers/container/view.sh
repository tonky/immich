#!/usr/bin/env bash
# ==============================================================================
# view.sh - Runs a command in a container's filesystem view, without containers
# ==============================================================================
# The host's root (every top-level directory bound in place) plus the container's own
# paths from helpers/container/<name>.mounts, under bubblewrap: the server sees
# /test-assets and /data as in upstream's compose, and `docker exec`/`docker cp`
# (path/docker) reach the same files. Network, processes and user stay the host's.
#
# Usage: helpers/container/view.sh <container> <command> [args...]
set -euo pipefail

name="${1:?usage: view.sh <container> <command> [args...]}"
shift
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="$REPO_ROOT/.enve/containers/$name"
MOUNTS="$REPO_ROOT/helpers/container/$name.mounts"
[ -f "$MOUNTS" ] || { echo "❌ [container] no mounts for $name ($MOUNTS)" >&2; exit 1; }

args=(--tmpfs /)
for dir in /*; do
  case "$dir" in /proc | /dev | /tmp) continue ;; esac
  if [ -L "$dir" ]; then
    args+=(--symlink "$(readlink "$dir")" "$dir")
  else
    args+=(--bind "$dir" "$dir")
  fi
done
args+=(--dev-bind /dev /dev --proc /proc --bind /tmp /tmp)

while read -r host path; do
  case "$host" in
    '' | '#'*) continue ;;
    state/*) host="$STATE/${host#state/}" ;;
    *) host="$REPO_ROOT/$host" ;;
  esac
  mkdir -p "$host"
  args+=(--bind "$host" "$path")
done < "$MOUNTS"

exec bwrap "${args[@]}" --die-with-parent --chdir "$PWD" -- "$@"
