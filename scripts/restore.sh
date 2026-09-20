#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SNAPSHOT=${1:-}
CONFIRM=${2:-}
export HOME=${HOME:-/root}
export RCLONE_CONFIG=${RCLONE_CONFIG:-/etc/minecraft/secrets/rclone.conf}
RCLONE_REMOTE=${RCLONE_REMOTE:-$(rclone_remote_name)}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:${RCLONE_REMOTE:-yandex}:minecraft-restic}
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/minecraft/secrets/restic_password}

[[ -n "$SNAPSHOT" ]] || fail "usage: restore.sh <snapshot> CONFIRM_FULL_RESTORE"
[[ "$CONFIRM" == "CONFIRM_FULL_RESTORE" ]] || fail "restore requires explicit CONFIRM_FULL_RESTORE"

snapshot_exists() {
  # `restic snapshots <id>` exits 0 even for an unknown ID (it just prints
  # "Ignoring ...: no matching ID found" to stderr); only --json distinguishes
  # a real match (an object with "short_id") from an empty result ("[]").
  restic snapshots "$1" --json 2>/dev/null | grep -q '"short_id"'
}

run_restore() {
  log "starting full restore from snapshot ${SNAPSHOT}"
  # Fail before touching the running server if the snapshot doesn't even
  # exist -- a typo'd or already-pruned snapshot ID should never cost a
  # stop/start cycle to discover.
  snapshot_exists "$SNAPSHOT" || fail "snapshot ${SNAPSHOT} not found"
  # A full restore overwrites the current shared state outright; if the
  # target snapshot turns out to be wrong or the restore itself goes badly,
  # there must be something to come back to. backup.sh already no-ops its
  # own lock acquisition when called from inside one (see lib.sh), so this
  # is safe to call directly here.
  "$SCRIPT_DIR/backup.sh" pre-restore || fail "pre-restore backup failed; aborting restore"
  # Re-check: backup.sh no longer prunes for a pre-restore reason (see
  # backup.sh), but this still catches any other way the target could have
  # gone missing before the server is stopped.
  snapshot_exists "$SNAPSHOT" || fail "snapshot ${SNAPSHOT} vanished after pre-restore backup"
  systemctl stop minecraft.service || true
  restic restore "$SNAPSHOT" --target /
  systemctl start minecraft.service

  # First boot after a restore can take well past a fixed sleep (world
  # generation/plugin setup); poll instead of guessing a delay -- the same
  # fixed-sleep pattern in deploy.sh's verify_release previously reported a
  # timed-out ping as success, so guess-and-hope here is worth avoiding too.
  local attempt
  for attempt in $(seq 1 "${VERIFY_PING_ATTEMPTS:-30}"); do
    if "$SCRIPT_DIR/minecraft-status.py" 127.0.0.1 25565 >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" -eq "${VERIFY_PING_ATTEMPTS:-30}" ]]; then
      fail "minecraft protocol ping did not respond in time after restore"
    fi
    sleep 2
  done

  "$SCRIPT_DIR/healthcheck.sh"
  telegram_alert critical "full restore completed from snapshot ${SNAPSHOT}"
}

with_global_lock run_restore
