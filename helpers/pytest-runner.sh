#!/usr/bin/env bash
# ==============================================================================
# pytest-runner.sh - Hermetic Pytest Runner for Immich ML Service
# ==============================================================================
set -euo pipefail

# As upstream's machine-learning `ci-unit`: the CPU extra provides onnxruntime.
exec "$(dirname "${BASH_SOURCE[0]}")/uv" run --extra cpu pytest "$@"
