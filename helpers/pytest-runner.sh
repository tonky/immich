#!/usr/bin/env bash
# ==============================================================================
# pytest-runner.sh - Hermetic Pytest Runner for Immich ML Service
# ==============================================================================
set -euo pipefail

TARGETS="${*:-}"
if [ -z "${TARGETS}" ]; then
  exec uv run pytest
else
  exec uv run pytest ${TARGETS}
fi
