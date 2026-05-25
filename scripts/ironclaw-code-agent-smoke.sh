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
  if [[ -z "$TOKEN" && -n "$IRONCLAW_SSH_HOST" && -r "$IRONCLAW_SSH_KEY" ]]; then
    TOKEN="$(discover_remote_gateway_token)"
  fi
fi

if [[ -z "${TOKEN:-}" || -z "$IRONCLAW_PUBLIC_URL" ]]; then
  echo "Set IRONCLAW_PUBLIC_URL and an IronClaw gateway token before running code-agent smoke." >&2
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
sentinel = "IRONCLAW_CODE_AGENT_OK"

def request(path, method="GET", body=None, timeout=25):
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

instructions = """
IronClaw iOS coding-agent task.
Please run the requested local workstation task now.
You MUST use local workstation tools before answering. For git, code, shell, tests, files, repo setup, or filesystem requests, call shell, file, grep, or apply_patch first.
When calling shell, pass the JSON parameter named command, singular, containing one shell script string.
If a tool call fails because of parameter shape, retry the same turn with the corrected parameter before giving a final answer.
Do not answer "I am not sure" when a local tool can be run. If a tool is unavailable, say exactly which local tool failed.
Use shell for repo setup, file creation, git status, tests, and capability checks. Wrap raw command output in fenced code blocks, then add a concise result summary.
Do not use http, GitHub, tool_install, package installers, external network, or IP probes unless the user explicitly asks for that class of work.
If native tool calling is unavailable, emit one standalone XML tool call outside markdown: <tool_call>{"name":"shell","arguments":{"command":"..."}}</tool_call>
""".strip()
shell_command = f"""
set -eu
rm -rf /tmp/near-ios-agent-smoke
mkdir -p /tmp/near-ios-agent-smoke
cd /tmp/near-ios-agent-smoke
git init -q
cat > calculator.py <<'PYCODE'
def add(a, b):
    return a + b

def multiply(a, b):
    return a * b
PYCODE
cat > test_calculator.py <<'PYCODE'
import unittest
from calculator import add, multiply

class CalculatorTests(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)

    def test_multiply(self):
        self.assertEqual(multiply(4, 5), 20)

if __name__ == "__main__":
    unittest.main()
PYCODE
python3 -m unittest
git status --short
find . -maxdepth 2 -type f | sort
printf '\\n{sentinel}\\n'
""".strip()
user_request = f"""
Use the hosted IronClaw workstation. Use shell to run exactly this one command, then return the raw output and a short summary:
{shell_command}
""".strip()
prompt = f"{instructions}\n\nUser request:\n{user_request}"

try:
    thread = request("/api/chat/thread/new", method="POST")
    thread_id = thread.get("id") if isinstance(thread, dict) else None
    if not thread_id:
        raise RuntimeError("thread creation did not return an id")
    print(f"code-agent thread: {thread_id[:8]}", flush=True)

    request("/api/chat/send", method="POST", body={
        "thread_id": thread_id,
        "content": prompt,
        "timezone": "America/Toronto",
    }, timeout=30)

    last_state = "unknown"
    last_tool_count = 0
    for attempt in range(90):
        time.sleep(2)
        history = request(f"/api/chat/history?thread_id={thread_id}&limit=3", timeout=15)
        pending_gate = history.get("pending_gate") if isinstance(history, dict) else None
        if pending_gate:
            tool = pending_gate.get("tool_name") or pending_gate.get("toolName") or "unknown"
            raise RuntimeError(f"code-agent smoke requires approval before finish: {tool}")
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
            print("response:", response[:700].replace("\n", " "), flush=True)
            if sentinel not in combined:
                trace = " | ".join(
                    f"{call.get('name')}:{str(call.get('result_preview') or call.get('error') or '')[:180]}"
                    for call in tool_calls[:4]
                )
                raise RuntimeError(f"code-agent response/tool trace did not contain {sentinel}; tool_calls={len(tool_calls)} {trace}")
            print("code-agent smoke ok")
            sys.exit(0)
        if state == "failed":
            if sentinel in combined:
                print("code-agent smoke ok")
                sys.exit(0)
            continue
        if attempt and attempt % 15 == 0:
            print(f"waiting for code-agent output; state={state}")
    raise TimeoutError(f"IronClaw code-agent smoke did not return visible output within 180 seconds; last_state={last_state} tool_calls={last_tool_count}")
except urllib.error.HTTPError as error:
    body = error.read().decode("utf-8", errors="replace")
    print(f"code-agent smoke failed: HTTP {error.code} {body[:240]}", file=sys.stderr)
    sys.exit(1)
except Exception as error:
    print(f"code-agent smoke failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
