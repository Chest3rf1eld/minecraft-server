#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REASON=${1:-scheduled}
# systemd units run without $HOME set, which makes restic warn on every
# invocation ("unable to locate cache directory") and skip its local
# metadata cache entirely.
export HOME=${HOME:-/root}
export RCLONE_CONFIG=${RCLONE_CONFIG:-/etc/minecraft/secrets/rclone.conf}
RCLONE_REMOTE=${RCLONE_REMOTE:-$(rclone_remote_name)}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:${RCLONE_REMOTE:-yandex}:minecraft-restic}
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/minecraft/secrets/restic_password}
HEALTHCHECKS_BACKUP_URL_FILE=${HEALTHCHECKS_BACKUP_URL_FILE:-/etc/minecraft/secrets/healthchecks_backup_url}

send_hc() {
  local suffix=${1:-}
  if [[ -r "$HEALTHCHECKS_BACKUP_URL_FILE" ]]; then
    # Strip stray whitespace (e.g. a leading space from a copy-paste into
    # the GitHub secret) -- curl rejects a URL containing any outright.
    curl -fsS "$(tr -d '[:space:]' <"$HEALTHCHECKS_BACKUP_URL_FILE")${suffix}" >/dev/null || true
  fi
}

run_backup() {
  ensure_state_dir
  send_hc "/start"
  trap 'send_hc "/fail"' ERR
  log "starting ${REASON} backup"
  if ! restic snapshots >/dev/null 2>&1; then
    log "restic repository not initialized yet; initializing"
    restic init
  fi
  # A prior backup killed mid-run (VPS reboot, OOM, manual intervention)
  # leaves its repository lock behind; restic unlock only clears locks
  # whose owning process is confirmed gone, so this is safe to run every time.
  restic unlock || true
  if systemctl is-active --quiet minecraft.service; then
    "$SCRIPT_DIR/rcon-command.py" "save-all flush" || fail "RCON save-all flush failed"
  fi
  # World data, whitelist/ban/op lists, and plugin data (AuthMe accounts,
  # CoreProtect logs) all live under MINECRAFT_SHARED_DIR and are symlinked
  # into the active release by prepare-release.sh, so backing up this one
  # tree covers everything that must survive a restore.
  timeout "${RESTIC_TIMEOUT_SECONDS:-900}" restic backup \
    "$MINECRAFT_ROOT/shared" \
    --tag "minecraft" \
    --tag "$REASON"
  timeout "${RESTIC_TIMEOUT_SECONDS:-900}" restic forget --keep-within-daily 7d --keep-daily 30 --keep-monthly 6 --prune
  touch "$MINECRAFT_STATE_DIR/last-backup-success"
  send_hc
  trap - ERR
  log "backup completed"
}

with_global_lock run_backup
