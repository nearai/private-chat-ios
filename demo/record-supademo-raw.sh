#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${NEAR_DEMO_DEVICE_NAME:-iPhone 17 Pro}"
BUNDLE_ID="${NEAR_DEMO_BUNDLE_ID:-ai.near.privatechat.ios}"
DERIVED_DATA_DIR="${NEAR_DEMO_DERIVED_DATA_DIR:-$ROOT_DIR/demo/build/DerivedData}"
OUT_DIR="$ROOT_DIR/demo/out"
RAW_VIDEO="${1:-$OUT_DIR/near-private-chat-supademo-raw.mov}"
AUTOCAPTURE="${NEAR_DEMO_AUTOCAPTURE:-1}"
CAPTURE_SECONDS="${NEAR_DEMO_CAPTURE_SECONDS:-170}"
DEMO_SCREEN="${NEAR_DEMO_SCREEN:-onboarding}"
AUTOPLAY_DELAY_MS="${NEAR_DEMO_AUTOPLAY_DELAY_MS:-2500}"

bash "$ROOT_DIR/demo/preflight.sh"

mkdir -p "$OUT_DIR"

DEVICE_ID="$(xcrun simctl list devices available | sed -n "s/^[[:space:]]*$DEVICE_NAME (\([A-F0-9-]*\)) (.*$/\1/p" | head -n 1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "Simulator not found: $DEVICE_NAME" >&2
  exit 1
fi

echo "Booting $DEVICE_NAME ($DEVICE_ID)..."
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null

echo "Setting clean simulator status bar..."
xcrun simctl status_bar "$DEVICE_ID" override \
  --time 9:41 \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 >/dev/null 2>&1 || true

echo "Building app..."
xcodebuild build \
  -project "$ROOT_DIR/NEARPrivateChat.xcodeproj" \
  -scheme NEARPrivateChat \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA_DIR"

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug-iphonesimulator/NEARPrivateChat.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing app..."
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

if [[ "$AUTOCAPTURE" == "1" ]]; then
  echo "Recording real app capture to $RAW_VIDEO..."
  rm -f "$RAW_VIDEO"

  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" \
    -NEARDemoCapture \
    -NEARDemoAutoPlay \
    "-NEARDemoScreen=$DEMO_SCREEN" \
    "-NEARDemoAutoPlayDelayMS=$AUTOPLAY_DELAY_MS" >/dev/null

  sleep 1

  xcrun simctl io "$DEVICE_ID" recordVideo "$RAW_VIDEO" >/tmp/near-private-chat-recordVideo.log 2>&1 &
  RECORD_PID=$!
  cleanup() {
    if kill -0 "$RECORD_PID" >/dev/null 2>&1; then
      kill -INT "$RECORD_PID" >/dev/null 2>&1 || true
      wait "$RECORD_PID" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup INT TERM EXIT

  sleep "$CAPTURE_SECONDS"
  cleanup
  trap - INT TERM EXIT

  if [[ ! -s "$RAW_VIDEO" ]]; then
    echo "Recording failed. recordVideo log:" >&2
    cat /tmp/near-private-chat-recordVideo.log >&2 || true
    exit 1
  fi

  echo "Raw Supademo capture ready: $RAW_VIDEO"
  exit 0
fi

echo "Launching app..."
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" -NEARDemoCapture "-NEARDemoScreen=$DEMO_SCREEN"

cat <<EOF

Real simulator is now running in demo-capture mode.

Before recording:
1. Confirm Home shows Q3 Launch and the resume chat.
2. Confirm there are no QA/debug projects visible.
3. Dismiss the keyboard.
4. Put the simulator window in the final capture position.

Press Return to start recording: $RAW_VIDEO
Stop recording with Ctrl-C after the one-cut tap script is complete.

EOF

read -r
rm -f "$RAW_VIDEO"
xcrun simctl io "$DEVICE_ID" recordVideo "$RAW_VIDEO"
