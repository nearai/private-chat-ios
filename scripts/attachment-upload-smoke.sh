#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="${BUNDLE_ID:-ai.near.privatechat.ios}"
PRIVATE_API_BASE_URL="${PRIVATE_API_BASE_URL:-https://private.near.ai}"
APP_PATH="${APP_PATH:-build/DerivedDataSmoke/Build/Products/Debug-iphonesimulator/NEARPrivateChat.app}"

DEVICE_ID="$(xcrun simctl list devices available "$DEVICE_NAME" | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -n 1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No available simulator named '$DEVICE_NAME'." >&2
  exit 1
fi

APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -z "$APP_DATA" ]]; then
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Install $BUNDLE_ID on '$DEVICE_NAME' before running attachment smoke tests, or build $APP_PATH first." >&2
    exit 1
  fi
  xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
  xcrun simctl install "$DEVICE_ID" "$APP_PATH" >/dev/null
  APP_DATA="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -z "$APP_DATA" ]]; then
    echo "Installed $BUNDLE_ID on '$DEVICE_NAME', but no app container was available." >&2
    exit 1
  fi
fi

APP_DATA="$APP_DATA" \
PRIVATE_API_BASE_URL="$PRIVATE_API_BASE_URL" \
python3 - <<'PY'
import json
import mimetypes
import os
import pathlib
import plistlib
import tempfile
import urllib.error
import urllib.request
import uuid

app_data = pathlib.Path(os.environ["APP_DATA"])
base_url = os.environ["PRIVATE_API_BASE_URL"].rstrip("/")
prefs = app_data / "Library" / "Preferences" / "ai.near.privatechat.ios.plist"

def decode_json_data(value):
    if isinstance(value, bytes):
        return json.loads(value.decode("utf-8"))
    if isinstance(value, str):
        return json.loads(value)
    return value

def load_session_token():
    if not prefs.exists():
        return None
    with prefs.open("rb") as handle:
        plist = plistlib.load(handle)
    for key in [
        "debug.session",
        "keychainFallback.ai.near.privatechat.ios.session",
    ]:
        value = plist.get(key)
        if not value:
            continue
        try:
            session = decode_json_data(value)
            token = (session or {}).get("token", "").strip()
            if token:
                return token
        except Exception:
            continue
    return None

token = load_session_token()
if not token:
    raise SystemExit("No simulator session token found. Sign into the app first.")

def make_tiny_pdf(path):
    text = "NEAR Private Chat small PDF attachment smoke test."
    objects = [
        "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj",
        "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj",
        "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj",
        f"4 0 obj << /Length {44 + len(text)} >> stream\nBT /F1 12 Tf 36 96 Td ({text}) Tj ET\nendstream endobj",
        "5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj",
    ]
    content = "%PDF-1.4\n"
    offsets = [0]
    for obj in objects:
        offsets.append(len(content.encode("latin-1")))
        content += obj + "\n"
    xref = len(content.encode("latin-1"))
    content += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n"
    for offset in offsets[1:]:
        content += f"{offset:010d} 00000 n \n"
    content += f"trailer << /Root 1 0 R /Size {len(objects) + 1} >>\nstartxref\n{xref}\n%%EOF\n"
    path.write_bytes(content.encode("latin-1"))

def upload(path):
    boundary = f"Boundary-{uuid.uuid4()}"
    parts = []
    def add_field(name, value):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    add_field("purpose", "user_data")
    add_field("expires_after[anchor]", "created_at")
    add_field("expires_after[seconds]", "36000")
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\nContent-Type: {mime}\r\n\r\n".encode()
    )
    parts.append(path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    body = b"".join(parts)
    request = urllib.request.Request(
        f"{base_url}/v1/files",
        data=body,
        method="POST",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))

try:
    with tempfile.TemporaryDirectory(prefix="near-private-attachments-") as tmp:
        root = pathlib.Path(tmp)
        fixtures = [
            root / "note.txt",
            root / "data.json",
            root / "table.csv",
            root / "brief.pdf",
        ]
        fixtures[0].write_text("This is a tiny text fixture for NEAR Private Chat attachments.\n", encoding="utf-8")
        fixtures[1].write_text(json.dumps({"fixture": "json", "ok": True}, indent=2), encoding="utf-8")
        fixtures[2].write_text("name,value\nalpha,1\nbeta,2\n", encoding="utf-8")
        make_tiny_pdf(fixtures[3])
        for fixture in fixtures:
            result = upload(fixture)
            file_id = result.get("id", "")
            print(f"uploaded {fixture.name}: id={file_id[:18]}... bytes={result.get('bytes')}")
    print("attachment upload smoke ok")
except urllib.error.HTTPError as error:
    body = error.read().decode("utf-8", errors="replace")
    raise SystemExit(f"attachment upload failed: HTTP {error.code} {body[:240]}")
PY
