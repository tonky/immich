#!/usr/bin/env bash
# ==============================================================================
# start-immich-ml.sh - Service Launcher for Immich Machine Learning Service
# ==============================================================================
# Runs the real FastAPI service; a missing environment fails its readiness probe
# instead of being replaced by a stand-in that answers /ping.
set -euo pipefail

if [ ! -f machine-learning/immich_ml/main.py ]; then
  echo "❌ [immich-ml] machine-learning/ is not checked out" >&2
  exit 1
fi
exec uv run --directory machine-learning uvicorn immich_ml.main:app --host 127.0.0.1 --port 3003
