#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
ITERATIONS="${ITERATIONS:-12}"
SLEEP_SECONDS="${SLEEP_SECONDS:-300}"
RUN_SECONDS="${RUN_SECONDS:-}"
STOP_ON_FAILURE="${STOP_ON_FAILURE:-0}"
LOG_DIR="$ROOT_DIR/build/Logs"
LOG_FILE="$LOG_DIR/overnight-smoke-$(date +%Y%m%d-%H%M%S).log"
FAILURES=0
PASSES=0
START_EPOCH="$(date +%s)"
END_EPOCH=""
if [[ -n "$RUN_SECONDS" ]]; then
  END_EPOCH=$((START_EPOCH + RUN_SECONDS))
fi

mkdir -p "$LOG_DIR"

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

run_step() {
  local name="$1"
  shift
  local status
  echo "[$(timestamp)] START $name" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  status=${PIPESTATUS[0]}
  if [[ "$status" -eq 0 ]]; then
    PASSES=$((PASSES + 1))
    echo "[$(timestamp)] PASS  $name" | tee -a "$LOG_FILE"
  else
    FAILURES=$((FAILURES + 1))
    echo "[$(timestamp)] FAIL  $name status=$status failures=$FAILURES" | tee -a "$LOG_FILE"
    if [[ "$STOP_ON_FAILURE" == "1" ]]; then
      exit "$status"
    fi
  fi
  return 0
}

should_continue() {
  if [[ "${LOOP_FOREVER:-0}" == "1" ]]; then
    return 0
  fi
  if [[ -n "$END_EPOCH" ]]; then
    [[ "$(date +%s)" -lt "$END_EPOCH" ]]
    return
  fi
  [[ "$iteration" -lt "$ITERATIONS" ]]
}

sleep_until_next_iteration() {
  local sleep_for="$SLEEP_SECONDS"
  if [[ -n "$END_EPOCH" ]]; then
    local now remaining
    now="$(date +%s)"
    remaining=$((END_EPOCH - now))
    if [[ "$remaining" -le 0 ]]; then
      return 0
    fi
    if [[ "$remaining" -lt "$sleep_for" ]]; then
      sleep_for="$remaining"
    fi
  fi
  sleep "$sleep_for"
}

iteration=1
if [[ -n "$END_EPOCH" ]]; then
  echo "[$(timestamp)] Overnight smoke loop starting. run_seconds=$RUN_SECONDS end_epoch=$END_EPOCH sleep_seconds=$SLEEP_SECONDS stop_on_failure=$STOP_ON_FAILURE" | tee -a "$LOG_FILE"
else
  echo "[$(timestamp)] Overnight smoke loop starting. iterations=$ITERATIONS sleep_seconds=$SLEEP_SECONDS stop_on_failure=$STOP_ON_FAILURE" | tee -a "$LOG_FILE"
fi

while true; do
  echo "[$(timestamp)] ITERATION $iteration" | tee -a "$LOG_FILE"
  run_step "build" "$ROOT_DIR/scripts/build-simulator.sh"
  run_step "ironclaw mobile agent source smoke" "$ROOT_DIR/scripts/ironclaw-mobile-agent-source-smoke.sh"
  if [[ "$iteration" -eq 1 || "${SEED_EACH_ITERATION:-0}" == "1" ]]; then
    run_step "seed simulator ironclaw" "$ROOT_DIR/scripts/seed-simulator-ironclaw.sh" "$DEVICE_NAME"
  fi
  run_step "ironclaw preflight" "$ROOT_DIR/scripts/ironclaw-preflight.sh"
  run_step "ironclaw workstation smoke" "$ROOT_DIR/scripts/ironclaw-workstation-smoke.sh"
  run_step "ironclaw code-agent smoke" "$ROOT_DIR/scripts/ironclaw-code-agent-smoke.sh"
  run_step "ironclaw research smoke" "$ROOT_DIR/scripts/ironclaw-research-smoke.sh"
  run_step "attachment upload smoke" "$ROOT_DIR/scripts/attachment-upload-smoke.sh" "$DEVICE_NAME"

  if ! should_continue; then
    break
  fi
  iteration=$((iteration + 1))
  sleep_until_next_iteration
done

echo "[$(timestamp)] Overnight smoke loop complete. passes=$PASSES failures=$FAILURES Log: $LOG_FILE" | tee -a "$LOG_FILE"
