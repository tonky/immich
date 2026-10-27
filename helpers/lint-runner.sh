#!/usr/bin/env bash
# ==============================================================================
# lint-runner.sh <file...> - upstream's lint and format checks of a package, on its files
# ==============================================================================
# Runs from the component's directory on the files given (relative to it), each through
# what upstream checks it with in the package holding it (the nearest package.json: the
# root's for i18n/):
#   - ESLint, on the files the package's `lint` script names (`eslint "src/**/*.ts"`, or `.`),
#     when the package has an ESLint config;
#   - Prettier (`--check`, under the package's .prettierignore), on the files its `format`
#     script names (`prettier --check .`, the root's `i18n/`);
#   - ShellCheck, on shell scripts.
# A file none of them checks fails the run, as does an empty file list: a lint that passed
# having checked nothing would read as clean. Narrow the job's filter instead.
# Another component's file (`../…`, a dependency's change) and a deleted one are left out;
# given only such files, it fails too.
set -euo pipefail

REPO_ROOT="$PWD"
while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/pnpm-lock.yaml" ]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

if [ $# -eq 0 ]; then
  echo "❌ [lint] no files given: lint-runner.sh lints the files it is given" >&2
  exit 2
fi

# The files that are this component's and still there. Another component's file (`../…`)
# is its own component's to lint, under its own config.
files=()
for f in "$@"; do
  f="${f#./}"
  [[ "$f" == ../* ]] && { echo "· [lint] $f: another component's"; continue; }
  [ -f "$f" ] || { echo "· [lint] $f: deleted"; continue; }
  files+=("$f")
done

# The package whose scripts check them: the nearest directory with a package.json (i18n/
# has none: the root's `format` checks it). The checks run there, on paths relative to it.
prefix=""
while [ ! -f package.json ] && [ "$PWD" != "$REPO_ROOT" ] && [ "$PWD" != / ]; do
  prefix="$(basename "$PWD")/$prefix"
  cd ..
done

# script_paths <script> <tool>: the paths the package.json script running <tool> names, one
# per line; nothing when there is no such script.
script_paths() {
  [ -f package.json ] || return 0
  node -e '
    const [script, tool] = process.argv.slice(1);
    const command = (require("./package.json").scripts || {})[script] || "";
    const words = command.split(/\s+/).map((w) => w.replace(/^["\x27]|["\x27]$/g, ""));
    const at = words.indexOf(tool);
    if (at >= 0) for (const w of words.slice(at + 1)) if (w && !w.startsWith("-")) console.log(w);
  ' "$1" "$2"
}

# covered <file> <path...>: whether a script's paths name <file> (`.`, a directory, a glob).
covered() {
  local file="$1" path
  shift
  for path in "$@"; do
    path="${path#./}"
    case "$path" in
      . | "") return 0 ;;
      *'*'*) [[ "$file" == ${path//\*\*\//} ]] && return 0 ;;
      *) [[ "$file" == "${path%/}" || "$file" == "${path%/}"/* ]] && return 0 ;;
    esac
  done
  return 1
}

has_eslint_config=false
for cfg in eslint.config.js eslint.config.mjs eslint.config.cjs .eslintrc.js .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
  if [ -f "$cfg" ]; then
    has_eslint_config=true
    break
  fi
done
lint_paths=()
if [ "$has_eslint_config" = true ]; then
  while IFS= read -r p; do lint_paths+=("$p"); done < <(script_paths lint eslint)
fi
format_paths=()
while IFS= read -r p; do format_paths+=("$p"); done < <(script_paths format prettier)

eslint_files=()
prettier_files=()
sh_files=()
unchecked=()
for f in ${files[@]+"${files[@]}"}; do
  f="$prefix$f"
  checked=false
  case "$f" in
    *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs | *.svelte)
      if [ ${#lint_paths[@]} -gt 0 ] && covered "$f" "${lint_paths[@]}"; then
        eslint_files+=("$f")
        checked=true
      fi
      ;;
    *.sh)
      sh_files+=("$f")
      checked=true
      ;;
  esac
  if [ ${#format_paths[@]} -gt 0 ] && covered "$f" "${format_paths[@]}"; then
    prettier_files+=("$f")
    checked=true
  fi
  [ "$checked" = true ] || unchecked+=("$f")
done

if [ ${#unchecked[@]} -gt 0 ]; then
  echo "❌ [lint] upstream's lint and format scripts check none of: ${unchecked[*]} (narrow the job's filter)" >&2
  exit 1
fi
if [ $((${#eslint_files[@]} + ${#prettier_files[@]} + ${#sh_files[@]})) -eq 0 ]; then
  echo "❌ [lint] none of the $# file(s) given is this package's and still there" >&2
  exit 1
fi

# Pre-sync svelte-kit if any web files are being linted
if [ ${#eslint_files[@]} -gt 0 ] && [ -f svelte.config.js ] && [ ! -d .svelte-kit ]; then
  (./node_modules/.bin/svelte-kit sync 2>/dev/null) || true
fi

local_bin() {
  if [ -x "./node_modules/.bin/$1" ]; then
    echo "./node_modules/.bin/$1"
  elif [ -x "$REPO_ROOT/node_modules/.bin/$1" ]; then
    echo "$REPO_ROOT/node_modules/.bin/$1"
  fi
}

pids=()

# 1. ESLint, as the package's `lint` script runs it, on its files.
if [ ${#eslint_files[@]} -gt 0 ]; then
  (
    ESLINT_BIN="$(local_bin eslint)"
    if [ -z "$ESLINT_BIN" ]; then
      echo "❌ [eslint] ${#eslint_files[@]} file(s) to lint but no ESLint binary: install dependencies" >&2
      exit 1
    fi
    # Typed rules resolve workspace dependencies' types from their build.
    "$REPO_ROOT/helpers/build-workspace-deps.sh"
    echo "🔍 [eslint] Linting ${#eslint_files[@]} file(s)..."
    # A file the config ignores is upstream's choice, not a warning to fail on.
    "$ESLINT_BIN" --max-warnings 0 --no-warn-ignored "${eslint_files[@]}"
    echo "✓ [eslint] All files clean."
  ) &
  pids+=($!)
fi

# 2. Prettier, as the package's `format` script runs it, on its files.
if [ ${#prettier_files[@]} -gt 0 ]; then
  (
    PRETTIER_BIN="$(local_bin prettier)"
    if [ -z "$PRETTIER_BIN" ]; then
      echo "❌ [prettier] ${#prettier_files[@]} file(s) to check but no prettier binary: install dependencies" >&2
      exit 1
    fi
    echo "🔍 [prettier] Checking formatting on ${#prettier_files[@]} file(s)..."
    "$PRETTIER_BIN" --check --ignore-unknown "${prettier_files[@]}"
    echo "✓ [prettier] Formatting verified."
  ) &
  pids+=($!)
fi

# 3. ShellCheck on shell scripts.
if [ ${#sh_files[@]} -gt 0 ]; then
  (
    command -v shellcheck >/dev/null 2>&1 || { echo "❌ [shellcheck] not on PATH" >&2; exit 1; }
    echo "🔍 [shellcheck] Auditing ${#sh_files[@]} shell script(s)..."
    shellcheck -x "${sh_files[@]}"
    echo "✓ [shellcheck] Scripts clean."
  ) &
  pids+=($!)
fi

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "❌ One or more lint tasks reported errors."
  exit 1
fi

echo "✓ Incremental lint suite passed cleanly."
