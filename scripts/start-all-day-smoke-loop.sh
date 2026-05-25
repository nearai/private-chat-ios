#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export RUN_SECONDS="${RUN_SECONDS:-86400}"
export SLEEP_SECONDS="${SLEEP_SECONDS:-300}"
export STOP_ON_FAILURE="${STOP_ON_FAILURE:-0}"

exec "$SCRIPT_DIR/start-overnight-smoke-loop.sh"
