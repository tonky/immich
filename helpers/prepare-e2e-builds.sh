#!/usr/bin/env bash
# Build the server and browser inputs before the run starts its traced services.
set -euo pipefail

# A producer always uses the helpers' source/output validation, even when called by
# an older recording helper that already built other workspace packages.
unset IMMICH_WORKSPACE_DEPS_BUILT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# An entrypoint can be missing while its output directory and old helper stamp remain.
# Forget that build so the normal helper really recompiles it.
forget_if_missing() {
  local stamp=$1
  shift
  for output in "$@"; do
    [ -e "$output" ] || { rm -f "$stamp"; return; }
  done
}
forget_if_missing server/dist/.build-stamp server/dist/main.js packages/sdk/build/index.js packages/plugin-sdk/dist/index.js
forget_if_missing web/build/.build-stamp web/build/index.html packages/sdk/build/index.js
forget_if_missing packages/plugin-core/dist/.build-stamp packages/plugin-core/dist/plugin.wasm
forget_if_missing e2e/node_modules/.enact-deps-stamp packages/cli/dist/index.js packages/sdk/build/index.js packages/plugin-sdk/dist/index.js

helpers/build-if-stale.sh "immich..." server/dist
helpers/build-if-stale.sh "immich-web..." web/build i18n
helpers/build-core-plugin.sh --producer
(cd e2e && ../helpers/build-workspace-deps.sh)
# Materialize the separately locked image environment before service capture too.
# The launcher still resolves it normally, including on a cold consumer machine.
helpers/server-image.sh >/dev/null
