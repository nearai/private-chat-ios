#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="ai.near.privatechat.ios"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedDataRunSimulator}"

xcodebuild \
  -project "$ROOT_DIR/NEARPrivateChat.xcodeproj" \
  -scheme NEARPrivateChat \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

DEVICE_ID="$(xcrun simctl list devices available "$DEVICE_NAME" | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -n 1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No available simulator named '$DEVICE_NAME'." >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
APP_PATH="$(find "$DERIVED_DATA_PATH" -path '*/Build/Products/Debug-iphonesimulator/NEARPrivateChat.app' -type d -print | tail -n 1)"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
if [[ "${SEED_IRONCLAW:-0}" == "1" ]]; then
  "$ROOT_DIR/scripts/seed-simulator-ironclaw.sh" "$DEVICE_NAME"
fi
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
