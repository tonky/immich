#!/usr/bin/env bash
# ==============================================================================
# pytest-runner.sh - Hermetic Pytest Runner for Immich ML Service
# ==============================================================================
set -euo pipefail

# As upstream's machine-learning `ci-unit`: the CPU extra provides onnxruntime.
export PYTHONDONTWRITEBYTECODE=1
# ENACT_TEST_VERBOSE: the recall harness reads each test's own outcome (`<nodeid> PASSED`).
exec "$(dirname "${BASH_SOURCE[0]}")/uv" run --extra cpu pytest -p no:cacheprovider ${ENACT_TEST_VERBOSE:+-v} "$@"
