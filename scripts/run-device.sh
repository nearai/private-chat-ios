#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="ai.near.privatechat.ios"
DEVICE_ID="${1:-${DEVICE_ID:-}}"

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun xctrace list devices 2>/dev/null | awk '
    /^== Simulators ==/ { in_devices = 0 }
    /^== Devices ==/ { in_devices = 1; next }
    in_devices && /\(/ && $0 !~ /Mac/ {
      print
    }
  ' | sed -n 's/.*(\([^)]*\)).*/\1/p' | head -n 1)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  cat >&2 <<'MSG'
No physical iPhone is visible to Xcode.

Plug the iPhone into this Mac, unlock it, tap Trust, and enable Developer Mode
on the phone if iOS asks. Then rerun:
  scripts/run-device.sh

You can also pass a UDID explicitly:
  scripts/run-device.sh <DEVICE_UDID>
MSG
  exit 1
fi

build_overrides=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  build_overrides+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
else
  echo "Using project signing settings. If signing fails, rerun with DEVELOPMENT_TEAM=<Apple Team ID> scripts/run-device.sh"
fi

xcodebuild \
  -project "$ROOT_DIR/NEARPrivateChat.xcodeproj" \
  -scheme NEARPrivateChat \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${build_overrides[@]}" \
  build

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphoneos/NEARPrivateChat.app' -type d -print | tail -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "Built app was not found under DerivedData." >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"
