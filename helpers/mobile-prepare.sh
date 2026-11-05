#!/usr/bin/env bash
# ==============================================================================
# mobile-prepare.sh - Idempotent @immich/mobile OpenAPI, FFI & Dart Codegen
# ==============================================================================
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

# The lock sits beside the stamp in flutter's own git-ignored tool dir, not in .enact.
mkdir -p "$REPO_ROOT/mobile/.dart_tool"
exec 9>"$REPO_ROOT/mobile/.dart_tool/.enact-prepare.lock"
flock 9

STAMP="$REPO_ROOT/mobile/.dart_tool/.enact-codegen-stamp"
if [ -f "$STAMP" ] \
  && [ -f "$REPO_ROOT/mobile/generated/openapi/pubspec.yaml" ] \
  && [ -f "$REPO_ROOT/mobile/lib/routing/router.gr.dart" ] \
  && [ -f "$REPO_ROOT/mobile/lib/data/db/main/database.steps.dart" ] \
  && [ -d "$REPO_ROOT/mobile/test/drift/main/generated" ] \
  && [ -f "$REPO_ROOT/mobile/lib/generated/codegen_loader.g.dart" ] \
  && [ -f "$REPO_ROOT/mobile/lib/generated/translations.g.dart" ] \
  && [ -f "$REPO_ROOT/native/native_core/lib/src/native_core_bindings.g.dart" ]; then
  exit 0
fi

SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/openapi-generator-cli" << 'EOF'
#!/usr/bin/env bash
exec pnpm dlx @openapitools/openapi-generator-cli@2.41.0 "$@"
EOF
chmod +x "$SHIM_DIR/openapi-generator-cli"
export PATH="$SHIM_DIR:$PATH"

(
  cd "$REPO_ROOT/open-api"
  bash ./bin/generate-dart-sdk.sh
)

(
  cd "$REPO_ROOT/mobile"
  flutter pub get --enforce-lockfile
  node ./scripts/build_runner_patch.mjs
)

(
  cd "$REPO_ROOT/native/native_core"
  cargo build -p native_core_ffi
  flutter pub get
  dart run ffigen --config ffigen.yaml
)

(
  cd "$REPO_ROOT/mobile"
  dart run drift_dev make-migrations
  dart run drift_dev schema generate --data-classes --companions drift_schemas/main/ test/drift/main/generated/
  for pigeon_file in pigeon/*.dart; do
    dart run pigeon --input "$pigeon_file"
  done
  dart format lib/platform/
  dart run easy_localization:generate -S ../i18n
  dart format lib/generated/codegen_loader.g.dart
  dart run bin/generate_keys.dart
  dart format lib/generated/translations.g.dart
  dart run build_runner build
  dart format lib/routing/router.gr.dart
)

mkdir -p "$REPO_ROOT/mobile/.dart_tool"
touch "$STAMP"
