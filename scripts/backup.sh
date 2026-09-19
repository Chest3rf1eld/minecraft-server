#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REASON=${1:-scheduled}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:yandex:minecraft-restic}
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/minecraft/secrets/restic_password}
export RCLONE_CONFIG=${RCLONE_CONFIG:-/etc/minecraft/secrets/rclone.conf}
HEALTHCHECKS_BACKUP_URL_FILE=${HEALTHCHECKS_BACKUP_URL_FILE:-/etc/minecraft/secrets/healthchecks_backup_url}

send_hc() {
  local suffix=${1:-}
  if [[ -r "$HEALTHCHECKS_BACKUP_URL_FILE" ]]; then
    curl -fsS "$(<"$HEALTHCHECKS_BACKUP_URL_FILE")${suffix}" >/dev/null || true
  fi
}

run_backup() {
  ensure_state_dir
  send_hc "/start"
  trap 'send_hc "/fail"' ERR
  log "starting ${REASON} backup"
  if systemctl is-active --quiet minecraft.service; then
    "$SCRIPT_DIR/rcon-command.py" "save-all flush" || fail "RCON save-all flush failed"
  fi
  timeout "${RESTIC_TIMEOUT_SECONDS:-900}" restic backup \
    "$MINECRAFT_ROOT/shared" \
    "$MINECRAFT_ROOT/current/whitelist.json" \
    "$MINECRAFT_ROOT/current/banned-players.json" \
    "$MINECRAFT_ROOT/current/banned-ips.json" \
    "$MINECRAFT_ROOT/current/ops.json" \
    --tag "minecraft" \
    --tag "$REASON"
  timeout "${RESTIC_TIMEOUT_SECONDS:-900}" restic forget --keep-within-daily 7d --keep-daily 30 --keep-monthly 6 --prune
  touch "$MINECRAFT_STATE_DIR/last-backup-success"
  send_hc
  trap - ERR
  log "backup completed"
}

with_global_lock run_backup
