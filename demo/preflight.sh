#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="$ROOT_DIR/review-artifacts/screenshots-2026-05-24-fresh"
LEGACY_SCREENSHOT_DIR="$ROOT_DIR/review-artifacts/screenshots"

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

need_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

need_cmd ffmpeg
need_cmd ffprobe
need_cmd say
need_cmd awk

need_file "$SCREENSHOT_DIR/01-home.png"
need_file "$SCREENSHOT_DIR/02-new-chat-composer.png"
need_file "$SCREENSHOT_DIR/03-model-picker.png"
need_file "$SCREENSHOT_DIR/04-model-picker-council.png"
need_file "$SCREENSHOT_DIR/05-agent-workspace.png"
need_file "$SCREENSHOT_DIR/07-project-context.png"
need_file "$SCREENSHOT_DIR/08-project-library.png"
need_file "$LEGACY_SCREENSHOT_DIR/03-chat-thread.png"
need_file "$LEGACY_SCREENSHOT_DIR/10-security-attestation.png"
need_file "$LEGACY_SCREENSHOT_DIR/11-share-collaboration.png"

if [[ "${NEAR_DEMO_USES_NEAR_CLOUD:-0}" == "1" && -z "${NEAR_DEMO_NEAR_CLOUD_API_KEY:-}" ]]; then
  echo "Missing NEAR_DEMO_NEAR_CLOUD_API_KEY. Add it to demo/.env.local or set NEAR_DEMO_USES_NEAR_CLOUD=0." >&2
  exit 1
fi

echo "Demo preflight passed."

