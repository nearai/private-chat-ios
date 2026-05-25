#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/bin/near-private-chat-verify.js"

node "$CLI" "$ROOT_DIR/fixtures/valid/near-private-chat-transcript-v1.valid.json" >/tmp/near-private-chat-verify-valid.log

if node "$CLI" "$ROOT_DIR/fixtures/tampered/near-private-chat-transcript-v1.tampered-message.json" >/tmp/near-private-chat-verify-tampered-message.log 2>&1; then
  cat /tmp/near-private-chat-verify-tampered-message.log
  echo "Expected tampered-message fixture to fail." >&2
  exit 1
fi

if node "$CLI" "$ROOT_DIR/fixtures/tampered/near-private-chat-transcript-v1.tampered-signature.json" >/tmp/near-private-chat-verify-tampered-signature.log 2>&1; then
  cat /tmp/near-private-chat-verify-tampered-signature.log
  echo "Expected tampered-signature fixture to fail." >&2
  exit 1
fi

echo "Verifier fixtures passed."
