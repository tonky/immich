#!/usr/bin/env bash
# ==============================================================================
# pytest-runner.sh - Hermetic Pytest Runner for Immich ML Service
# ==============================================================================
set -euo pipefail

# As upstream's machine-learning `ci-unit`: the CPU extra provides onnxruntime.
exec uv run --extra cpu pytest "$@"
