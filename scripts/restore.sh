#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SNAPSHOT=${1:-}
CONFIRM=${2:-}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:yandex:minecraft-restic}
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/minecraft/secrets/restic_password}
export RCLONE_CONFIG=${RCLONE_CONFIG:-/etc/minecraft/secrets/rclone.conf}

[[ -n "$SNAPSHOT" ]] || fail "usage: restore.sh <snapshot> CONFIRM_FULL_RESTORE"
[[ "$CONFIRM" == "CONFIRM_FULL_RESTORE" ]] || fail "restore requires explicit CONFIRM_FULL_RESTORE"

run_restore() {
  log "starting full restore from snapshot ${SNAPSHOT}"
  systemctl stop minecraft.service || true
  restic restore "$SNAPSHOT" --target /
  systemctl start minecraft.service
  sleep 20
  "$SCRIPT_DIR/healthcheck.sh"
  telegram_alert critical "full restore completed from snapshot ${SNAPSHOT}"
}

with_global_lock run_restore
