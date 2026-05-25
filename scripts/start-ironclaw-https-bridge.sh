#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_PORT="${GATEWAY_PORT:-3000}"
DEFAULT_DEV_TOKEN="near-private-ios-local-dev-token"
STATE_DIR="${IRONCLAW_STATE_DIR:-"$HOME/Library/Application Support/NEARPrivateChat/IronClaw"}"
TOKEN_FILE="$STATE_DIR/ironclaw-gateway.token"
LOCAL_URL="http://127.0.0.1:${GATEWAY_PORT}"

if [[ "${GATEWAY_AUTH_TOKEN:-}" == "$DEFAULT_DEV_TOKEN" ]]; then
  echo "Refusing to expose IronClaw through HTTPS with the old shared default token." >&2
  echo "Unset GATEWAY_AUTH_TOKEN to generate a random token, or provide a private token explicitly." >&2
  exit 1
fi

"$ROOT_DIR/scripts/start-ironclaw-gateway.sh"

GATEWAY_AUTH_TOKEN="${GATEWAY_AUTH_TOKEN:-}"
if [[ -z "$GATEWAY_AUTH_TOKEN" && -r "$TOKEN_FILE" ]]; then
  GATEWAY_AUTH_TOKEN="$(cat "$TOKEN_FILE")"
fi

if [[ -z "$GATEWAY_AUTH_TOKEN" || "$GATEWAY_AUTH_TOKEN" == "$DEFAULT_DEV_TOKEN" ]]; then
  echo "Refusing to start a public tunnel without a private random gateway token." >&2
  exit 1
fi

echo
echo "IronClaw is listening locally at ${LOCAL_URL}."
echo "The iPhone app requires a public HTTPS bridge and the gateway bearer token."
if [[ "${PRINT_GATEWAY_TOKEN:-0}" == "1" ]]; then
  echo
  echo "  ${GATEWAY_AUTH_TOKEN}"
else
  echo "Gateway token: hidden. Rerun with PRINT_GATEWAY_TOKEN=1 only when you are ready to paste it into the app."
fi
echo

if command -v cloudflared >/dev/null 2>&1; then
  echo "Starting Cloudflare quick tunnel. Paste the generated https://*.trycloudflare.com URL into Account -> IronClaw Bridge."
  echo "Leave this terminal open while testing from iPhone."
  exec cloudflared tunnel --url "$LOCAL_URL"
fi

if command -v ngrok >/dev/null 2>&1; then
  echo "Starting ngrok tunnel. Paste the generated https://*.ngrok-free.app URL into Account -> IronClaw Bridge."
  echo "Leave this terminal open while testing from iPhone."
  exec ngrok http "$GATEWAY_PORT"
fi

echo "No tunnel helper found."
echo
echo "Install one of:"
echo "  brew install cloudflared"
echo "  brew install ngrok/ngrok/ngrok"
echo
echo "Then rerun this script, or expose ${LOCAL_URL} through your own HTTPS tunnel."
exit 1
