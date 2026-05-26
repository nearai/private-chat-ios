#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/demo/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/demo/.env.local"
  set +a
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd xcrun
need_cmd xcodebuild

if [[ "${NEAR_DEMO_USES_NEAR_CLOUD:-0}" == "1" && -z "${NEAR_DEMO_NEAR_CLOUD_API_KEY:-}" ]]; then
  echo "Missing NEAR_DEMO_NEAR_CLOUD_API_KEY. Add it to demo/.env.local or set NEAR_DEMO_USES_NEAR_CLOUD=0." >&2
  exit 1
fi

echo "Real-capture preflight passed."
