#!/usr/bin/env bash
# ==============================================================================
# provision-geodata.sh - Reverse-geocoding data for the Immich server
# ==============================================================================
# Immich's server image ships GeoNames and Natural Earth data under
# $IMMICH_BUILD_DATA/geodata; city/state/country search reads it. This fetches the
# same files once into a cache directory (CI caches it) and links them into place.
#
# Usage: provision-geodata.sh <geodata-dir>
set -euo pipefail

TARGET="${1:?usage: provision-geodata.sh <geodata-dir>}"
CACHE="${IMMICH_GEODATA_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/immich-geodata}"
NATURAL_EARTH="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson"
GEONAMES="https://download.geonames.org/export/dump"

fetch() {
  local url="$1" out="$2"
  [ -s "$out" ] && return 0
  echo "🌍 [geodata] downloading $url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$out.part" "$url"
  mv "$out.part" "$out"
}

mkdir -p "$CACHE" "$TARGET"
CACHE="$(cd "$CACHE" && pwd)" # the links below must not be relative
fetch "$GEONAMES/admin1CodesASCII.txt" "$CACHE/admin1CodesASCII.txt"
fetch "$GEONAMES/admin2Codes.txt" "$CACHE/admin2Codes.txt"
fetch "$NATURAL_EARTH" "$CACHE/ne_10m_admin_0_countries.geojson"
if [ ! -s "$CACHE/cities500.txt" ]; then
  fetch "$GEONAMES/cities500.zip" "$CACHE/cities500.zip"
  python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("cities500.txt", sys.argv[2])' \
    "$CACHE/cities500.zip" "$CACHE"
  rm -f "$CACHE/cities500.zip"
fi
# The server re-imports geodata whenever this stamp differs from the one it recorded.
[ -s "$CACHE/geodata-date.txt" ] || date -u +%Y-%m-%dT%H:%M:%S%z | tr -d '\n' > "$CACHE/geodata-date.txt"

for f in admin1CodesASCII.txt admin2Codes.txt cities500.txt ne_10m_admin_0_countries.geojson geodata-date.txt; do
  ln -sf "$CACHE/$f" "$TARGET/$f"
done
echo "✓ [geodata] ready in $TARGET"
