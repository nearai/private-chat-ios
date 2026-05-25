#!/usr/bin/env bash

load_ironclaw_local_config() {
  local user_config="$HOME/.config/NEARPrivateChat/ironclaw.env"
  local repo_config="${ROOT_DIR:-}/local/ironclaw.env"

  if [[ -r "$user_config" ]]; then
    # shellcheck disable=SC1090
    source "$user_config"
  fi
  if [[ -n "${ROOT_DIR:-}" && -r "$repo_config" ]]; then
    # shellcheck disable=SC1090
    source "$repo_config"
  fi

  : "${IRONCLAW_PUBLIC_URL:=}"
  : "${IRONCLAW_SSH_HOST:=}"
  : "${IRONCLAW_SSH_PORT:=22821}"
  : "${IRONCLAW_SSH_USER:=agent}"
  : "${IRONCLAW_SSH_KEY:=}"
}
