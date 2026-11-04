#!/usr/bin/env bash
# ==============================================================================
# openapi-drift-runner.sh - Server OpenAPI Spec & TypeScript SDK Drift Check
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

"$REPO_ROOT/helpers/build-if-stale.sh" 'immich...' server/dist

echo "🔍 [openapi-drift] Regenerating OpenAPI spec from server..."
(cd "$REPO_ROOT/server" && node ./dist/bin/sync-open-api.js)
if ! git -C "$REPO_ROOT" diff --exit-code -- open-api/immich-openapi-specs.json; then
  echo "❌ [openapi-drift] open-api/immich-openapi-specs.json is out of sync with the server." >&2
  exit 1
fi

echo "🔍 [openapi-drift] Regenerating TypeScript SDK client from OpenAPI spec..."
(
  cd "$REPO_ROOT/open-api"
  pnpm dlx oazapfts@7.5.0 \
    --optimistic \
    --argumentStyle=object \
    --useEnumType \
    --allSchemas \
    immich-openapi-specs.json \
    ../packages/sdk/src/fetch-client.ts
)
if ! git -C "$REPO_ROOT" diff --exit-code -- packages/sdk/src/fetch-client.ts; then
  echo "❌ [openapi-drift] packages/sdk/src/fetch-client.ts is out of sync with open-api/immich-openapi-specs.json." >&2
  exit 1
fi

echo "✓ OpenAPI spec and TypeScript SDK client verified."
