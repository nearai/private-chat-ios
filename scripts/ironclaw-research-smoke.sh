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
  echo "Set IRONCLAW_PUBLIC_URL and an IronClaw gateway token before running research smoke." >&2
  exit 1
fi

run_research_smoke_once() {
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
sentinel = "IRONCLAW_RESEARCH_OK"

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

prompt = f"""
IronClaw research tool smoke from NEAR Private Chat iOS.
You MUST use the nearai_web_search tool before answering. Do not answer from memory.
Do not use the http tool.
If native tool calling is unavailable, emit this exact standalone XML tool call outside markdown, then continue after the tool result:
<tool_call>{{"name":"nearai_web_search","arguments":{{"query":"current NEAR AI news May 2026"}}}}</tool_call>
Return {sentinel}, one source title or domain, and one short summary sentence.
If nearai_web_search is unavailable, say exactly which tool failed.
""".strip()

try:
    tools = request("/api/extensions/tools", timeout=12)
    tool_names = {tool.get("name", "") for tool in tools.get("tools", [])} if isinstance(tools, dict) else set()
    if "nearai_web_search" not in tool_names:
        raise RuntimeError("nearai_web_search is missing from the IronClaw tool catalog")
    print(f"tool catalog ok: {len(tool_names)} tools")

    thread = request("/api/chat/thread/new", method="POST")
    thread_id = thread.get("id") if isinstance(thread, dict) else None
    if not thread_id:
        raise RuntimeError("thread creation did not return an id")
    print(f"research thread: {thread_id[:8]}", flush=True)

    request("/api/chat/send", method="POST", body={
        "thread_id": thread_id,
        "content": prompt,
        "timezone": "America/Toronto",
    }, timeout=30)

    last_state = "unknown"
    last_tool_count = 0
    retried_for_tool = False
    ignored_turn_number = None
    continuation = f"""
Continue the same research smoke. Your previous answer did not produce a recorded nearai_web_search call.
Call nearai_web_search now. Do not answer from memory. Do not use http.
If native tool calling is unavailable, emit this exact standalone XML tool call outside markdown, then continue after the tool result:
<tool_call>{{"name":"nearai_web_search","arguments":{{"query":"current NEAR AI news May 2026"}}}}</tool_call>
Then return {sentinel}, one source title or domain, and one short summary sentence.
""".strip()

    for attempt in range(105):
        time.sleep(2)
        history = request(f"/api/chat/history?thread_id={thread_id}&limit=3", timeout=15)
        pending_gate = history.get("pending_gate") or history.get("pendingGate") if isinstance(history, dict) else None
        if pending_gate:
            tool = pending_gate.get("tool_name") or pending_gate.get("toolName") or "unknown"
            raise RuntimeError(f"research smoke requires approval before finish: {tool}")
        turns = history.get("turns", []) if isinstance(history, dict) else []
        if not turns:
            continue
        turn = turns[-1]
        turn_number = turn.get("turn_number")
        if ignored_turn_number is not None and isinstance(turn_number, int) and turn_number <= ignored_turn_number:
            continue
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
        used_search = any((call.get("name") or "") == "nearai_web_search" for call in tool_calls)
        if response:
            print("response:", response[:700].replace("\n", " "), flush=True)
            if sentinel not in combined:
                if not retried_for_tool:
                    retried_for_tool = True
                    ignored_turn_number = turn_number if isinstance(turn_number, int) else None
                    request("/api/chat/send", method="POST", body={
                        "thread_id": thread_id,
                        "content": continuation,
                        "timezone": "America/Toronto",
                    }, timeout=30)
                    continue
                raise RuntimeError(f"research response/tool trace did not contain {sentinel}")
            if not used_search:
                if not retried_for_tool:
                    retried_for_tool = True
                    ignored_turn_number = turn_number if isinstance(turn_number, int) else None
                    request("/api/chat/send", method="POST", body={
                        "thread_id": thread_id,
                        "content": continuation,
                        "timezone": "America/Toronto",
                    }, timeout=30)
                    continue
                raise RuntimeError("research smoke finished without a nearai_web_search tool call")
            print("research smoke ok")
            sys.exit(0)
        if state == "failed":
            if sentinel in combined and used_search:
                print("research smoke ok")
                sys.exit(0)
            continue
        if attempt and attempt % 15 == 0:
            print(f"waiting for research output; state={state}")
    raise TimeoutError(f"IronClaw research smoke did not return visible output within 210 seconds; last_state={last_state} tool_calls={last_tool_count}")
except urllib.error.HTTPError as error:
    body = error.read().decode("utf-8", errors="replace")
    print(f"research smoke failed: HTTP {error.code} {body[:240]}", file=sys.stderr)
    sys.exit(1)
except Exception as error:
    print(f"research smoke failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
}

if run_research_smoke_once; then
  exit 0
fi

echo "research smoke first attempt failed; retrying with a fresh thread..." >&2
sleep 3
run_research_smoke_once
