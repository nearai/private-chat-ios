#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="${BUNDLE_ID:-ai.near.privatechat.ios}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/ironclaw-local-config.sh"
source "$ROOT_DIR/scripts/lib/ironclaw-token.sh"
load_ironclaw_local_config

DEVICE_ID="$(xcrun simctl list devices available "$DEVICE_NAME" | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -n 1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No available simulator named '$DEVICE_NAME'." >&2
  exit 1
fi

APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -z "$APP_DATA" ]]; then
  echo "Install $BUNDLE_ID on '$DEVICE_NAME' before seeding IronClaw settings." >&2
  exit 1
fi

if [[ "${ALLOW_SIMULATOR_TOKEN_SEED:-0}" != "1" ]]; then
  echo "Refusing to seed simulator token storage without ALLOW_SIMULATOR_TOKEN_SEED=1." >&2
  exit 1
fi

if [[ -n "${IRONCLAW_AUTH_TOKEN:-}" ]]; then
  TOKEN="$IRONCLAW_AUTH_TOKEN"
else
  if [[ -z "$IRONCLAW_SSH_HOST" || ! -r "$IRONCLAW_SSH_KEY" ]]; then
    echo "Set IRONCLAW_AUTH_TOKEN or configure IRONCLAW_SSH_HOST and IRONCLAW_SSH_KEY before seeding." >&2
    exit 1
  fi
  TOKEN="$(discover_remote_gateway_token)"
fi

if [[ -z "$TOKEN" || -z "$IRONCLAW_PUBLIC_URL" ]]; then
  echo "Set IRONCLAW_PUBLIC_URL and an IronClaw gateway token before seeding." >&2
  exit 1
fi

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

APP_DATA="$APP_DATA" \
IRONCLAW_PUBLIC_URL="$IRONCLAW_PUBLIC_URL" \
IRONCLAW_AUTH_TOKEN="$TOKEN" \
python3 - <<'PY'
import json
import os
import pathlib
import plistlib

app_data = pathlib.Path(os.environ["APP_DATA"])
path = app_data / "Library" / "Preferences" / "ai.near.privatechat.ios.plist"
path.parent.mkdir(parents=True, exist_ok=True)
plist = {}
if path.exists():
    with path.open("rb") as handle:
        plist = plistlib.load(handle)

service = "ai.near.privatechat.ios"
plist[f"keychainFallback.{service}.ironclaw.authToken"] = json.dumps(os.environ["IRONCLAW_AUTH_TOKEN"].strip()).encode("utf-8")
plist["ironclawSettings"] = json.dumps({
    "isEnabled": True,
    "baseURL": os.environ["IRONCLAW_PUBLIC_URL"].strip(),
    "threadID": ""
}).encode("utf-8")
plist["selectedModel"] = "ironclaw/agent"
plist["webSearchEnabled"] = True
plist["sourceMode"] = "all"
plist["researchModeEnabled"] = True

with path.open("wb") as handle:
    plistlib.dump(plist, handle)
PY

echo "Seeded $DEVICE_NAME for hosted IronClaw at $IRONCLAW_PUBLIC_URL."
echo "Gateway token stored in simulator fallback keychain; value not printed."
