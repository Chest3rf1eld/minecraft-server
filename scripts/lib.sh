#!/usr/bin/env bash
set -euo pipefail

MINECRAFT_ROOT=${MINECRAFT_ROOT:-/srv/minecraft}
MINECRAFT_BIN_DIR=${MINECRAFT_BIN_DIR:-/opt/minecraft/bin}
MINECRAFT_STATE_DIR=${MINECRAFT_STATE_DIR:-$MINECRAFT_ROOT/state}
MINECRAFT_CURRENT_DIR=${MINECRAFT_CURRENT_DIR:-$MINECRAFT_ROOT/current}
MINECRAFT_SHARED_DIR=${MINECRAFT_SHARED_DIR:-$MINECRAFT_ROOT/shared}
MINECRAFT_LOCK_FILE=${MINECRAFT_LOCK_FILE:-$MINECRAFT_STATE_DIR/operation.lock}
MINECRAFT_LOG_TAG=${MINECRAFT_LOG_TAG:-minecraft-infra}

log() {
  printf '%s [%s] %s\n' "$(date -Is)" "$MINECRAFT_LOG_TAG" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

ensure_state_dir() {
  mkdir -p "$MINECRAFT_STATE_DIR"
}

with_global_lock() {
  ensure_state_dir
  local timeout_seconds=${LOCK_TIMEOUT_SECONDS:-900}
  exec 9>"$MINECRAFT_LOCK_FILE"
  if ! flock -w "$timeout_seconds" 9; then
    log "could not acquire global operation lock"
    exec 9>&-
    return 1
  fi
  "$@"
  local status=$?
  flock -u 9
  exec 9>&-
  return "$status"
}

secret_file() {
  printf '/etc/minecraft/secrets/%s' "$1"
}

# Reads the first remote name defined in an rclone config file (e.g. "yandex-disk"
# from "[yandex-disk]"). The remote's name is whatever the operator chose when they
# generated the config, so it must be read rather than assumed.
rclone_remote_name() {
  local config=${1:-${RCLONE_CONFIG:-/etc/minecraft/secrets/rclone.conf}}
  if [[ -r "$config" ]]; then
    sed -n 's/^\[\(.*\)\]$/\1/p' "$config" | head -n1
  fi
}

telegram_alert() {
  local level=$1
  local message=$2
  if command -v "$MINECRAFT_BIN_DIR/telegram.sh" >/dev/null 2>&1; then
    "$MINECRAFT_BIN_DIR/telegram.sh" "$level" "$message" || true
  else
    log "telegram script missing: [$level] $message"
  fi
}
