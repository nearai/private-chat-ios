#!/usr/bin/env bash
# ReleaseGate: the live regression suite that must be green before any
# TestFlight upload. Drives the real app against the production backend.
#
# Usage:
#   export NEAR_DEBUG_SESSION_TOKEN=...     # required (never stored on disk)
#   export NEAR_DEBUG_CLOUD_KEY=...         # optional, enables cloud scenarios
#   scripts/release-gate.sh
#
# Notes:
# - Runs the Debug configuration of the current commit (the DebugBackend
#   token hook is #if DEBUG); it gates the same code that gets archived.
# - Scenarios XCTSkip rather than fail when preconditions are missing
#   (no token, unreachable backend, empty catalog).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${NEAR_DEBUG_SESSION_TOKEN:?Set NEAR_DEBUG_SESSION_TOKEN (and optionally NEAR_DEBUG_CLOUD_KEY) in your shell}"

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_BUNDLE="$ROOT_DIR/build/ReleaseGate/$STAMP.xcresult"
mkdir -p "$ROOT_DIR/build/ReleaseGate"

# Quick reachability precondition: skip-fast with a clear message instead of
# burning a 20-minute run against a dead backend.
if ! curl -s -o /dev/null -m 10 https://private.near.ai; then
  echo "release-gate: https://private.near.ai unreachable — aborting (not a code failure)." >&2
  exit 2
fi

# TEST_RUNNER_-prefixed env vars are forwarded into the test-runner process.
export TEST_RUNNER_NEAR_DEBUG_SESSION_TOKEN="$NEAR_DEBUG_SESSION_TOKEN"
export TEST_RUNNER_NEAR_DEBUG_CLOUD_KEY="${NEAR_DEBUG_CLOUD_KEY:-}"

set +e
xcodebuild \
  -project "$ROOT_DIR/NEARPrivateChat.xcodeproj" \
  -scheme NEARPrivateChat \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$ROOT_DIR/build/DerivedDataGate" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:NEARPrivateChatUITests/ReleaseGateTests \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 360 \
  -retry-tests-on-failure -test-iterations 2 \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
GATE_STATUS=$?
set -e

"$ROOT_DIR/scripts/release-gate-report.sh" "$RESULT_BUNDLE" || true
exit $GATE_STATUS
