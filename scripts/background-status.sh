#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/build/Logs"
CURRENT_LOG="$LOG_DIR/overnight-smoke-current.out"
SESSION_NAME="${SESSION_NAME:-near-private-ios-overnight}"
IRONCLAW_SESSION_NAME="${IRONCLAW_SESSION_NAME:-ironclaw-ios}"

screen_pid() {
  local name="$1"
  { screen -ls 2>/dev/null || true; } |
    awk -v suffix=".$name" '$1 ~ suffix && !found { split($1, parts, "."); print parts[1]; found=1 }'
}

process_summary() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  ps -p "$pid" -o pid=,stat=,etime= 2>/dev/null | sed 's/^/[process] /'
}

latest_status_line() {
  [[ -r "$CURRENT_LOG" ]] || return 0
  rg -n "START|PASS|FAIL|Overnight smoke loop" "$CURRENT_LOG" | tail -1 | sed 's/^/[smoke] /'
}

last_failure_line() {
  [[ -r "$CURRENT_LOG" ]] || return 0
  rg -n "FAIL" "$CURRENT_LOG" | tail -1 | sed 's/^/[last-fail] /'
}

pass_count() {
  [[ -r "$CURRENT_LOG" ]] || {
    printf "0"
    return
  }
  rg -c "PASS  " "$CURRENT_LOG" || true
}

fail_count() {
  [[ -r "$CURRENT_LOG" ]] || {
    printf "0"
    return
  }
  rg -c "FAIL  " "$CURRENT_LOG" || true
}

smoke_pid="$(screen_pid "$SESSION_NAME")"
ironclaw_pid="$(screen_pid "$IRONCLAW_SESSION_NAME")"

echo "NEAR Private Chat background status"
echo "workspace=$ROOT_DIR"
echo "smoke_screen=$SESSION_NAME"
echo "smoke_pid=${smoke_pid:-not-running}"
process_summary "$smoke_pid"
echo "ironclaw_screen=$IRONCLAW_SESSION_NAME"
echo "ironclaw_pid=${ironclaw_pid:-not-running}"
process_summary "$ironclaw_pid"
echo "passes=$(pass_count) failures=$(fail_count)"
latest_status_line
last_failure_line
if [[ -r "$CURRENT_LOG" ]]; then
  stat -f "[log] %N modified=%Sm size=%z" "$CURRENT_LOG"
else
  echo "[log] missing $CURRENT_LOG"
fi
