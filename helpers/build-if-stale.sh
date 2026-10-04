#!/usr/bin/env bash
# ==============================================================================
# build-if-stale.sh - Builds a pnpm filter unless its output was built from these sources
# ==============================================================================
# Usage: build-if-stale.sh <pnpm filter> <output dir> [extra input path...]
#
# The output's stamp hashes the working tree of the filter's workspace packages (`pnpm
# list`), the extra paths (inputs outside any package, e.g. web's `../i18n`),
# pnpm-lock.yaml and the node version. Files git tracks or would track: build outputs are
# not inputs, uncommitted edits are. A missing or different stamp rebuilds.
#
# "Build when the output is missing" ran stale code twice: a lockfile-keyed CI cache
# restored the base branch's server/dist into a PR, and a local checkout kept a server/dist
# built before its sources changed.
set -euo pipefail

filter=$1
output=$2
shift 2

cd "$(git rev-parse --show-toplevel)"
mapfile -t packages < <(pnpm --filter "$filter" list --depth -1 --parseable)

# Paths, then their blob hashes in the same order: `git hash-object` reads each once.
mapfile -t files < <(
  git ls-files -co --exclude-standard -- "${packages[@]}" "$@" pnpm-lock.yaml |
    LC_ALL=C sort -u |
    while IFS= read -r file; do [ -f "$file" ] && printf '%s\n' "$file"; done
)
stamp=$(
  {
    node --version
    paste <(printf '%s\n' "${files[@]}") <(printf '%s\n' "${files[@]}" | git hash-object --stdin-paths)
  } | sha256sum | cut -d' ' -f1
)

if [ "$(cat "$output/.build-stamp" 2>/dev/null)" = "$stamp" ]; then
  echo "✓ [build-if-stale] $output is current ($filter)"
  exit 0
fi
echo "🔨 [build-if-stale] building $output ($filter)..."
pnpm --filter "$filter" run build
echo "$stamp" > "$output/.build-stamp"
