#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_NAME="${SESSION_NAME:-near-private-ios-overnight}"
RUN_SECONDS="${RUN_SECONDS:-86400}"
SLEEP_SECONDS="${SLEEP_SECONDS:-300}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
STOP_ON_FAILURE="${STOP_ON_FAILURE:-0}"
LOG_DIR="$ROOT_DIR/build/Logs"
CURRENT_LOG="$LOG_DIR/overnight-smoke-current.out"

mkdir -p "$LOG_DIR"
bash -n "$ROOT_DIR/scripts/overnight-smoke-loop.sh"

while IFS= read -r existing_session; do
  [[ -z "$existing_session" ]] && continue
  screen -S "$existing_session" -X quit || true
done < <(screen -ls | awk -v suffix=".$SESSION_NAME" '$1 ~ suffix {print $1}')

while IFS= read -r existing_pid; do
  [[ -z "$existing_pid" ]] && continue
  kill "$existing_pid" 2>/dev/null || true
done < <(ps -axo pid=,command= | awk '/scripts\/overnight-smoke-loop.sh/ && $0 !~ /awk/ {print $1}')

sleep 1

while IFS= read -r existing_pid; do
  [[ -z "$existing_pid" ]] && continue
  kill -9 "$existing_pid" 2>/dev/null || true
done < <(ps -axo pid=,command= | awk '/scripts\/overnight-smoke-loop.sh/ && $0 !~ /awk/ {print $1}')

screen -dmS "$SESSION_NAME" /usr/bin/env \
  ROOT_DIR="$ROOT_DIR" \
  RUN_SECONDS="$RUN_SECONDS" \
  SLEEP_SECONDS="$SLEEP_SECONDS" \
  DEVICE_NAME="$DEVICE_NAME" \
  STOP_ON_FAILURE="$STOP_ON_FAILURE" \
  /bin/bash -lc 'cd "$ROOT_DIR" && exec caffeinate -dimsu -t "$RUN_SECONDS" scripts/overnight-smoke-loop.sh > build/Logs/overnight-smoke-current.out 2>&1'

sleep 0.5
SCREEN_PID="$(
  { screen -ls || true; } |
    awk -v suffix=".$SESSION_NAME" '$1 ~ suffix && !found { split($1, parts, "."); print parts[1]; found=1 }'
)"
if [[ -n "$SCREEN_PID" ]]; then
  printf "%s\n" "$SCREEN_PID" > "$LOG_DIR/all-day-smoke.pid"
fi

echo "started screen=$SESSION_NAME"
if [[ -n "${SCREEN_PID:-}" ]]; then
  echo "screen_pid=$SCREEN_PID"
fi
echo "log=$CURRENT_LOG"
echo "run_seconds=$RUN_SECONDS sleep_seconds=$SLEEP_SECONDS stop_on_failure=$STOP_ON_FAILURE"
