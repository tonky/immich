#!/usr/bin/env bash
# ==============================================================================
# pinned-tool.sh - Prints the bin directory of a tool pinned in tools.lock
# ==============================================================================
# For upstream versions nixpkgs never shipped (enve installs nixpkgs only). Downloads the
# host platform's archive once, checks its sha256 and unpacks it under
# .enact/cache/tools/<name>-<version>/. Never substitutes another version or platform.
#
# Usage: helpers/pinned-tool.sh <name>
set -euo pipefail

name="${1:?usage: pinned-tool.sh <name>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -m)-$(uname -s)" in
  x86_64-Linux) platform=x86_64-linux ;;
  aarch64-Linux | arm64-Linux) platform=aarch64-linux ;;
  x86_64-Darwin) platform=x86_64-darwin ;;
  arm64-Darwin | aarch64-Darwin) platform=aarch64-darwin ;;
  *) echo "❌ [pinned-tool] unsupported platform $(uname -m)-$(uname -s)" >&2; exit 1 ;;
esac

read -r version sha256 url bin < <(awk -v n="$name" -v p="$platform" \
  '$1 == n && $3 == p { print $2, $4, $5, $6 }' "$REPO_ROOT/tools.lock") || true
if [ -z "${bin:-}" ]; then
  echo "❌ [pinned-tool] tools.lock has no $name for $platform" >&2
  exit 1
fi

dir="$REPO_ROOT/.enact/cache/tools/$name-$version"
bin_dir="$dir/$bin"
bin_dir="${bin_dir%/.}"
if [ -f "$dir/.sha256" ] && [ "$(cat "$dir/.sha256")" = "$sha256" ]; then
  echo "$bin_dir"
  exit 0
fi

mkdir -p "$REPO_ROOT/.enact/cache/tools"
exec 9>"$REPO_ROOT/.enact/cache/tools/.$name.lock"
# macOS has no flock(1); there the last unpack wins (same verified bytes).
if command -v flock >/dev/null; then flock 9; fi
# Another job may have unpacked it while this one waited for the lock.
if [ -f "$dir/.sha256" ] && [ "$(cat "$dir/.sha256")" = "$sha256" ]; then
  echo "$bin_dir"
  exit 0
fi

work="$(mktemp -d "$REPO_ROOT/.enact/cache/tools/.$name.XXXXXX")"
trap 'rm -rf "$work"' EXIT
archive="$work/${url##*/}"
echo "📥 [pinned-tool] $name $version ($platform)" >&2
curl -fsSL --retry 3 -o "$archive" "$url"
actual="$( (sha256sum "$archive" 2>/dev/null || shasum -a 256 "$archive") | cut -d' ' -f1)"
if [ "$actual" != "$sha256" ]; then
  echo "❌ [pinned-tool] $name: sha256 $actual, tools.lock pins $sha256" >&2
  exit 1
fi

mkdir "$work/out"
case "$archive" in
  *.tar.xz | *.tar.gz | *.tgz) tar -xf "$archive" -C "$work/out" ;;
  *.zip) unzip -q "$archive" -d "$work/out" ;;
  # A single gzipped executable (extism-js), named as the tool.
  *.gz) gunzip -c "$archive" > "$work/out/$name" && chmod +x "$work/out/$name" ;;
  # A Debian package: its files are in the data member.
  *.deb) (cd "$work" && ar x "$archive" && tar -xf data.tar.* -C out) ;;
  *) echo "❌ [pinned-tool] $name: unknown archive type ${archive##*/}" >&2; exit 1 ;;
esac
printf '%s' "$sha256" > "$work/out/.sha256"
rm -rf "$dir"
mv "$work/out" "$dir"
echo "$bin_dir"
