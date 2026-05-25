#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/ironclaw-local-config.sh"
source "$ROOT_DIR/scripts/lib/ironclaw-token.sh"
load_ironclaw_local_config

if [[ -n "${IRONCLAW_AUTH_TOKEN:-}" ]]; then
  TOKEN="$IRONCLAW_AUTH_TOKEN"
else
  if [[ -z "$IRONCLAW_SSH_HOST" || ! -r "$IRONCLAW_SSH_KEY" ]]; then
    echo "Set IRONCLAW_AUTH_TOKEN or configure IRONCLAW_SSH_HOST and IRONCLAW_SSH_KEY before running preflight." >&2
    exit 1
  fi
  TOKEN="$(discover_remote_gateway_token)"
fi

if [[ -z "$TOKEN" || -z "$IRONCLAW_PUBLIC_URL" ]]; then
  echo "Set IRONCLAW_PUBLIC_URL and an IronClaw gateway token before running preflight." >&2
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

try:
    health = urllib.request.urlopen(f"{base_url}/api/health", timeout=8).read().decode("utf-8")
    print("health ok:", health[:80])
    status = request("/api/gateway/status", timeout=8)
    if isinstance(status, dict):
        version = status.get("version") or status.get("ironclaw_version") or "unknown"
        model = status.get("model") or status.get("nearai_model") or "unknown"
        print(f"gateway ok: version={version} model={model}")
    thread = request("/api/chat/thread/new", method="POST")
    thread_id = thread.get("id") if isinstance(thread, dict) else None
    if not thread_id:
        raise RuntimeError("thread creation did not return an id")
    send = request("/api/chat/send", method="POST", body={
        "thread_id": thread_id,
        "content": "Return exactly: IC_PREFLIGHT_OK",
        "timezone": "America/Toronto",
    }, timeout=30)
    message_id = send.get("message_id") or send.get("messageId") if isinstance(send, dict) else None
    print("chat accepted:", "yes" if message_id else "accepted without message id")

    failed_without_text = 0
    for _ in range(45):
        time.sleep(2)
        history = request(f"/api/chat/history?thread_id={thread_id}&limit=3", timeout=12)
        turns = history.get("turns", []) if isinstance(history, dict) else []
        if not turns:
            continue
        turn = turns[-1]
        state = str(turn.get("state", "")).lower()
        response = (turn.get("response") or "").strip()
        if response:
            print("response:", response[:240].replace("\n", " "))
            if "IC_PREFLIGHT_OK" not in response:
                raise RuntimeError("preflight response did not contain IC_PREFLIGHT_OK")
            print("preflight ok")
            sys.exit(0)
        if state == "failed":
            failed_without_text += 1
            if failed_without_text >= 35:
                raise RuntimeError("IronClaw turn failed without response text")
            continue
        failed_without_text = 0
    raise TimeoutError("IronClaw did not return visible output within 90 seconds")
except urllib.error.HTTPError as error:
    body = error.read().decode("utf-8", errors="replace")
    print(f"preflight failed: HTTP {error.code} {body[:240]}", file=sys.stderr)
    sys.exit(1)
except Exception as error:
    print(f"preflight failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
