#!/usr/bin/env bash
# ==============================================================================
# view.sh - Runs a command in a container's filesystem view, without containers
# ==============================================================================
# The host's root (every top-level directory bound in place) plus the container's own
# paths from helpers/container/<name>.mounts and its network's names from <name>.hosts,
# under bubblewrap: the server sees
# /test-assets and /data as in upstream's compose, and `docker exec`/`docker cp`
# (path/docker) reach the same files. Network, processes and user stay the host's.
#
# The same on GitHub's runners: the repository's bin/bwrap is on PATH and the CI setup
# lifts their AppArmor restriction on user namespaces.
#
# Usage: helpers/container/view.sh <container> <command> [args...]
set -euo pipefail

name="${1:?usage: view.sh <container> <command> [args...]}"
shift
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="$REPO_ROOT/.enve/containers/$name"
MOUNTS="$REPO_ROOT/helpers/container/$name.mounts"
HOSTS="$REPO_ROOT/helpers/container/$name.hosts"
[ -f "$MOUNTS" ] || { echo "❌ [container] no mounts for $name ($MOUNTS)" >&2; exit 1; }

# entries <file>: its lines without comments and blank lines.
entries() {
  local line
  while read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    echo "$line"
  done < "$1"
}

# The mounts file, as host/container path pairs.
mounts=()
while read -r host path; do
  case "$host" in
    state/*) host="$STATE/${host#state/}" ;;
    *) host="$REPO_ROOT/$host" ;;
  esac
  mkdir -p "$host"
  mounts+=("$host" "$path")
done < <(entries "$MOUNTS")

hosts=()
[ ! -f "$HOSTS" ] || mapfile -t hosts < <(entries "$HOSTS")

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
for ((i = 0; i < ${#mounts[@]}; i += 2)); do
  args+=(--bind "${mounts[i]}" "${mounts[i + 1]}")
done
if [ ${#hosts[@]} -gt 0 ]; then
  { cat /etc/hosts; printf '%s\n' "${hosts[@]}"; } > "$STATE/hosts"
  args+=(--ro-bind "$STATE/hosts" /etc/hosts)
fi

exec bwrap "${args[@]}" --die-with-parent --chdir "$PWD" -- "$@"
