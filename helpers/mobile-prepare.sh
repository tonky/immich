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
  && [ -f "$REPO_ROOT/native/native_core/lib/src/bindings.g.dart" ]; then
  exit 0
fi

SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/openapi-generator-cli" << 'EOF'
#!/usr/bin/env bash
exec pnpm dlx @openapitools/openapi-generator-cli@2.41.0 "$@"
EOF
chmod +x "$SHIM_DIR/openapi-generator-cli"
# ffigen finds libclang at the host's LLVM paths, else asks `clang -print-file-name`: the
# env has libclang (enve.cue's libclang.lib) on its library path but no clang, so answer
# that one question with it. macOS's Xcode libclang is found as before.
if ! command -v clang >/dev/null 2>&1; then
  libclang=
  IFS=: read -r -a lib_dirs <<< "${LIBRARY_PATH:-}:${LD_LIBRARY_PATH:-}"
  for dir in "${lib_dirs[@]}"; do
    for name in libclang.so libclang.dylib; do
      [ -n "$dir" ] && [ -e "$dir/$name" ] && { libclang="$dir/$name"; break 2; }
    done
  done
  if [ -n "$libclang" ]; then
    printf '#!/usr/bin/env bash\ncase "$1" in -print-file-name=libclang.*) echo %q ;; *) exit 1 ;; esac\n' \
      "$libclang" > "$SHIM_DIR/clang"
    chmod +x "$SHIM_DIR/clang"
  fi
fi
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
  # libclang has its resource headers but no libc ones on Linux: enve.cue's
  # ffigenLibcHeaders exports glibc's for ffigen alone, after the resource dir as a
  # system include would be. macOS's Xcode libclang finds its SDK as before.
  ffigen_opts=()
  if [ -n "${ENACT_FFIGEN_LIBC_INCLUDE:-}" ]; then
    ffigen_opts=(--compiler-opts "-idirafter $ENACT_FFIGEN_LIBC_INCLUDE")
  fi
  dart run ffigen --config ffigen.yaml "${ffigen_opts[@]}"
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
