#!/usr/bin/env bash

discover_remote_gateway_token() {
  local remote_token_file="${IRONCLAW_REMOTE_TOKEN_FILE:-}"
  local remote_token_assignment
  remote_token_assignment="IRONCLAW_REMOTE_TOKEN_FILE=$(printf '%q' "$remote_token_file")"

  local strict_host_key_checking="${IRONCLAW_SSH_STRICT_HOST_KEY_CHECKING:-yes}"
  local user_known_hosts_file="${IRONCLAW_SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"

  if [[ "$strict_host_key_checking" != "yes" && "$strict_host_key_checking" != "accept-new" ]]; then
    echo "Refusing unsafe SSH host-key mode for IronClaw token discovery." >&2
    echo "Set IRONCLAW_SSH_STRICT_HOST_KEY_CHECKING=yes and pin the host in known_hosts, or use accept-new for first-run setup only." >&2
    return 1
  fi

  ssh \
    -p "$IRONCLAW_SSH_PORT" \
    -i "$IRONCLAW_SSH_KEY" \
    -o ConnectTimeout="${IRONCLAW_SSH_CONNECT_TIMEOUT:-8}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking="$strict_host_key_checking" \
    -o UserKnownHostsFile="$user_known_hosts_file" \
    "$IRONCLAW_SSH_USER@$IRONCLAW_SSH_HOST" \
    "$remote_token_assignment" 'bash -s' <<'SH'
set -euo pipefail

candidates=()
if [[ -n "${IRONCLAW_REMOTE_TOKEN_FILE:-}" ]]; then
  candidates+=("$IRONCLAW_REMOTE_TOKEN_FILE")
fi
candidates+=("$HOME/Library/Application Support/NEARPrivateChat/IronClaw/ironclaw-gateway.token")
candidates+=("$HOME/.config/NEARPrivateChat/IronClaw/ironclaw-gateway.token")
candidates+=("$HOME/.near-private-chat/ironclaw-gateway.token")

for token_file in "${candidates[@]}"; do
  if [[ -r "$token_file" ]]; then
    IFS= read -r token < "$token_file" || true
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      exit 0
    fi
  fi
done

echo "No readable IronClaw gateway token file. Set IRONCLAW_AUTH_TOKEN locally or IRONCLAW_REMOTE_TOKEN_FILE for the remote host." >&2
exit 1
SH
}
