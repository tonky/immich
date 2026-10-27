#!/usr/bin/env bash
# ==============================================================================
# build-if-stale.sh - Builds a pnpm filter unless its output was built from these sources
# ==============================================================================
# Usage: build-if-stale.sh <pnpm filter> <output dir> [extra input path...]
#        build-if-stale.sh --deps-of <package dir>
#
# The output's stamp hashes the working tree of the filter's workspace packages (`pnpm
# list`), the extra paths (inputs outside any package, e.g. web's `../i18n`),
# pnpm-lock.yaml and the node version. Files git tracks or would track: build outputs are
# not inputs, uncommitted edits are. A missing or different stamp rebuilds.
#
# `--deps-of <dir>`: the workspace packages the package in <dir> depends on, transitively
# (`<name>^...`), as its tests, lint and typecheck import their builds. They are read from
# the package's `node_modules` links (pnpm links each `workspace:` dependency to its
# directory): no `pnpm list`, whose start cost as much as the build it saved. Their outputs
# are several directories (sdk's build/, plugin-sdk's dist/): the stamp is the package's
# `node_modules/.enact-deps-stamp`, naming the outputs the build left (what git ignores in
# those packages, besides node_modules), and a missing one rebuilds too.
#
# "Build when the output is missing" ran stale code twice: a lockfile-keyed CI cache
# restored the base branch's server/dist into a PR, and a local checkout kept a server/dist
# built before its sources changed.
#
# IMMICH_WORKSPACE_DEPS_BUILT=1 skips it, as build-workspace-deps.sh: generate-reach-map.sh
# builds up front, so the traced server records what it reads to run, not the hashing.
set -euo pipefail
[ "${IMMICH_WORKSPACE_DEPS_BUILT:-}" = 1 ] && exit 0

root="$(git rev-parse --show-toplevel)"
if [ "$1" = --deps-of ]; then
  dir="$(cd "$2" && pwd)"
  # Its name, then the directories of its workspace dependencies, relative to the root.
  listed="$(node - "$dir" "$root" <<'JS'
const fs = require("fs"), path = require("path");
const [dir, root] = process.argv.slice(2);
const manifest = (d) => JSON.parse(fs.readFileSync(path.join(d, "package.json"), "utf8"));
const seen = new Set();
const walk = (d) => {
  const m = manifest(d);
  for (const kind of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]) {
    for (const [name, spec] of Object.entries(m[kind] || {})) {
      if (!String(spec).startsWith("workspace:")) continue;
      const dep = fs.realpathSync(path.join(d, "node_modules", name));
      if (!seen.has(dep)) { seen.add(dep); walk(dep); }
    }
  }
};
walk(dir);
console.log(manifest(dir).name);
for (const dep of seen) console.log(path.relative(root, dep));
JS
  )" || {
    # A dependency not linked (not installed): build them all, vouching for nothing.
    echo "🔨 [build-if-stale] $dir's workspace dependencies aren't linked: building them" >&2
    rm -f "$dir/node_modules/.enact-deps-stamp"
    cd "$dir"
    exec pnpm --filter "$(node -p "require('./package.json').name")^..." --if-present run build
  }
  mapfile -t deps <<<"$listed"
  [ ${#deps[@]} -gt 1 ] || exit 0
  filter="${deps[0]}^..."
  packages=("${deps[@]:1}")
  stamp_file="$dir/node_modules/.enact-deps-stamp"
  shift 2
else
  filter=$1
  output=$2
  shift 2
  stamp_file="$root/$output/.build-stamp"
  mapfile -t packages < <(cd "$root" && pnpm --filter "$filter" list --depth -1 --parseable)
fi
cd "$root"

# Paths, then their blob ids in the same order: the index's for a file git sees unchanged,
# `git hash-object` (reading it) for the rest, edited or untracked. A traced server start
# then records what the server runs (server/dist, which planning derives from server/src),
# not the hashing: reading every server/src file put them in immich-server's footprint, so
# a recording made any server change reach every e2e spec.
mapfile -t files < <(
  git ls-files -co --exclude-standard -- "${packages[@]}" "$@" pnpm-lock.yaml |
    LC_ALL=C sort -u |
    while IFS= read -r file; do [ -f "$file" ] && printf '%s\n' "$file"; done
)
declare -A oid=() edited=()
while IFS=$'\t' read -r -d '' meta file; do
  meta="${meta#* }"
  oid["$file"]="${meta%% *}"
done < <(git ls-files -s -z -- "${packages[@]}" "$@" pnpm-lock.yaml)
while IFS= read -r -d '' file; do edited["$file"]=1; done < <(git diff -z --name-only -- "${packages[@]}" "$@" pnpm-lock.yaml)
read_files=()
for file in "${files[@]}"; do
  [ -n "${oid[$file]:-}" ] && [ -z "${edited[$file]:-}" ] || read_files+=("$file")
done
if [ ${#read_files[@]} -gt 0 ]; then
  mapfile -t read_oids < <(printf '%s\n' "${read_files[@]}" | git hash-object --stdin-paths)
  for i in "${!read_files[@]}"; do oid["${read_files[$i]}"]="${read_oids[$i]}"; done
fi
stamp=$(
  {
    node --version
    for file in "${files[@]}"; do printf '%s\t%s\n' "$file" "${oid[$file]}"; done
  } | sha256sum | cut -d' ' -f1
)

# The stamp, then the outputs it vouches for (--deps-of), each of which must be there.
current() {
  local line
  [ -f "$stamp_file" ] || return 1
  { read -r line && [ "$line" = "$stamp" ] || return 1
    while read -r line; do [ -e "$line" ] || return 1; done; } <"$stamp_file"
}
if current; then
  echo "✓ [build-if-stale] ${output:-the builds} current ($filter)"
  exit 0
fi
echo "🔨 [build-if-stale] building ${output:-them} ($filter)..."
if [ -n "${output:-}" ]; then
  pnpm --filter "$filter" run build
  echo "$stamp" >"$stamp_file"
else
  pnpm --filter "$filter" --if-present run build
  mkdir -p "$(dirname "$stamp_file")"
  {
    echo "$stamp"
    git ls-files -oi --exclude-standard --directory -- "${packages[@]}" |
      while IFS= read -r out; do case "$out" in *node_modules/*) ;; *) printf '%s\n' "$out" ;; esac; done
  } >"$stamp_file"
fi
