#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_BUNDLE_ID="${SIMULATOR_BUNDLE_ID:-ai.near.privatechat.ios}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/ironclaw-local-config.sh"
source "$ROOT_DIR/scripts/lib/ironclaw-token.sh"
load_ironclaw_local_config

discover_simulator_token() {
  python3 - "$SIMULATOR_BUNDLE_ID" <<'PY'
import json
import os
import plistlib
import subprocess
import sys

bundle_id = sys.argv[1]
try:
    app_data = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", "booted", bundle_id, "data"],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
except Exception:
    sys.exit(0)

plist_path = os.path.join(app_data, "Library", "Preferences", f"{bundle_id}.plist")
try:
    with open(plist_path, "rb") as handle:
        prefs = plistlib.load(handle)
except Exception:
    sys.exit(0)

raw = prefs.get(f"keychainFallback.{bundle_id}.ironclaw.authToken")
if isinstance(raw, bytes):
    try:
        print(json.loads(raw.decode("utf-8")))
    except Exception:
        pass
elif isinstance(raw, str):
    try:
        print(json.loads(raw) if raw.startswith('"') else raw)
    except Exception:
        print(raw)
PY
}

if [[ -n "${IRONCLAW_AUTH_TOKEN:-}" ]]; then
  TOKEN="$IRONCLAW_AUTH_TOKEN"
else
  TOKEN="$(discover_simulator_token | head -n 1)"
  if [[ -z "$TOKEN" && ( -z "$IRONCLAW_SSH_HOST" || ! -r "$IRONCLAW_SSH_KEY" ) ]]; then
    echo "Set IRONCLAW_AUTH_TOKEN or configure IRONCLAW_SSH_HOST and IRONCLAW_SSH_KEY before running workstation smoke." >&2
    exit 1
  fi
  if [[ -z "$TOKEN" ]]; then
    TOKEN="$(discover_remote_gateway_token)"
  fi
fi

if [[ -z "$TOKEN" || -z "$IRONCLAW_PUBLIC_URL" ]]; then
  echo "Set IRONCLAW_PUBLIC_URL and an IronClaw gateway token before running workstation smoke." >&2
  exit 1
fi

IRONCLAW_PUBLIC_URL="$IRONCLAW_PUBLIC_URL" \
IRONCLAW_AUTH_TOKEN="$TOKEN" \
python3 - <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.request

base_url = os.environ["IRONCLAW_PUBLIC_URL"].rstrip("/")
token = os.environ["IRONCLAW_AUTH_TOKEN"].strip()
sentinel = "IRONCLAW_WORKSTATION_OK"

def request(path, method="GET", body=None, timeout=20):
    data = None
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {token}",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base_url}/{path.lstrip('/')}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read()
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))

prompt = f"""
Workstation smoke test from NEAR Private Chat iOS.
Please run the minimal local workstation command now.
Use only local built-in workstation tools. Do not call http, GitHub, tool_install, package installers, or external network.
When calling shell, pass the JSON parameter named command, singular.
Do not use set -euo pipefail; the shell tool may run commands through /bin/sh.
Use shell to run exactly: pwd; git --version; printf '\\n{sentinel}\\n'
Then reply with one short sentence that includes {sentinel}.
If shell is unavailable, say exactly which local tool failed and do not claim success.
""".strip()

try:
    thread = request("/api/chat/thread/new", method="POST")
    thread_id = thread.get("id") if isinstance(thread, dict) else None
    if not thread_id:
        raise RuntimeError("thread creation did not return an id")

    send = request("/api/chat/send", method="POST", body={
        "thread_id": thread_id,
        "content": prompt,
        "timezone": "America/Toronto",
    }, timeout=30)
    message_id = send.get("message_id") or send.get("messageId") if isinstance(send, dict) else None
    print("workstation accepted:", "yes" if message_id else "accepted without message id")

    last_state = "unknown"
    last_tool_count = 0
    for attempt in range(90):
        time.sleep(2)
        history = request(f"/api/chat/history?thread_id={thread_id}&limit=3", timeout=12)
        pending_gate = history.get("pending_gate") or history.get("pendingGate") if isinstance(history, dict) else None
        if pending_gate:
            tool = pending_gate.get("tool_name") or pending_gate.get("toolName") or "unknown"
            raise RuntimeError(f"workstation requires approval before smoke can finish: {tool}")
        turns = history.get("turns", []) if isinstance(history, dict) else []
        if not turns:
            continue
        turn = turns[-1]
        state = str(turn.get("state", "")).lower()
        response = (turn.get("response") or "").strip()
        tool_calls = turn.get("tool_calls") or []
        last_state = state
        last_tool_count = len(tool_calls)
        tool_previews = "\n".join(
            str(call.get("result") or call.get("result_preview") or call.get("error") or "")
            for call in tool_calls
        )
        combined = f"{response}\n{tool_previews}"
        if response:
            print("response:", response[:600].replace("\n", " "))
            if sentinel not in combined or "git version" not in combined:
                raise RuntimeError(f"workstation response/tool trace did not contain real shell output and {sentinel}")
            print("workstation smoke ok")
            sys.exit(0)
        if state == "failed":
            if sentinel in combined and "git version" in combined:
                print("workstation smoke ok")
                sys.exit(0)
            continue
        if attempt and attempt % 15 == 0:
            print(f"waiting for workstation output; state={state} tool_calls={len(tool_calls)}")
    raise TimeoutError(f"IronClaw workstation did not return visible output within 180 seconds; last_state={last_state} tool_calls={last_tool_count}")
except urllib.error.HTTPError as error:
    body = error.read().decode("utf-8", errors="replace")
    print(f"workstation smoke failed: HTTP {error.code} {body[:240]}", file=sys.stderr)
    sys.exit(1)
except Exception as error:
    print(f"workstation smoke failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
