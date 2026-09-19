#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FORCE=${FORCE_DEPLOY:-false}
GRACE_SECONDS=${DEPLOY_EMPTY_GRACE_SECONDS:-300}
PENDING_NOTICE_AFTER=${DEPLOY_PENDING_NOTICE_AFTER_SECONDS:-86400}

state_file() {
  printf '%s/deploy-state' "$MINECRAFT_STATE_DIR"
}

set_state() {
  ensure_state_dir
  printf '%s\n' "$1" >"$(state_file)"
  log "deployment state: $1"
}

wait_for_empty_server() {
  if [[ "$FORCE" == "true" ]]; then
    log "force deploy requested; skipping player wait"
    return
  fi
  set_state WAITING_FOR_EMPTY_SERVER
  local start now online
  start=$(date +%s)
  while true; do
    online=$($SCRIPT_DIR/player-count.sh 127.0.0.1 25565 || echo 999)
    if [[ "$online" -eq 0 ]]; then
      set_state EMPTY_GRACE_PERIOD
      sleep "$GRACE_SECONDS"
      online=$($SCRIPT_DIR/player-count.sh 127.0.0.1 25565 || echo 999)
      if [[ "$online" -eq 0 ]]; then
        return
      fi
      log "player joined during grace period; returning to wait"
    fi
    now=$(date +%s)
    if [[ $((now - start)) -gt "$PENDING_NOTICE_AFTER" ]]; then
      telegram_alert warning "deployment has been pending for more than 24 hours"
      if command -v mcrcon >/dev/null 2>&1; then
        true
      fi
      start=$now
    fi
    sleep 60
  done
}

verify_release() {
  set_state VERIFYING
  systemctl start minecraft.service
  sleep 20
  systemctl is-active --quiet minecraft.service
  "$SCRIPT_DIR/minecraft-status.py" 127.0.0.1 25565 >/tmp/minecraft-deploy-status.json
  if ! grep -Riq 'AuthMe' "$MINECRAFT_CURRENT_DIR/logs" 2>/dev/null; then
    fail "AuthMe load evidence was not found in logs"
  fi
}

rollback_release() {
  set_state ROLLBACK
  local previous
  previous=$(cat "$MINECRAFT_STATE_DIR/previous-release" 2>/dev/null || true)
  [[ -n "$previous" && -d "$MINECRAFT_ROOT/releases/$previous" ]] || fail "no previous release available"
  systemctl stop minecraft.service || true
    ln -sfnT "$MINECRAFT_ROOT/releases/$previous" "$MINECRAFT_CURRENT_DIR"
  set_state VERIFY_ROLLBACK
  if verify_release; then
    set_state ROLLED_BACK
    telegram_alert warning "deployment failed; rolled back to ${previous}"
  else
    set_state CRITICAL_FAILURE
    telegram_alert critical "deployment rollback failed"
    exit 1
  fi
}

run_deploy() {
  ensure_state_dir
  set_state PENDING
  wait_for_empty_server
  set_state BACKUP
  "$SCRIPT_DIR/backup.sh" pre-deploy
  set_state DEPLOYING
  systemctl stop minecraft.service || true
  # Release preparation is intentionally separate; this controller verifies and switches prepared releases.
  if [[ -f "$MINECRAFT_STATE_DIR/target-release" ]]; then
    target=$(cat "$MINECRAFT_STATE_DIR/target-release")
    [[ -d "$MINECRAFT_ROOT/releases/$target" ]] || fail "target release missing: $target"
    readlink -f "$MINECRAFT_CURRENT_DIR" | xargs -r basename >"$MINECRAFT_STATE_DIR/previous-release"
    ln -sfnT "$MINECRAFT_ROOT/releases/$target" "$MINECRAFT_CURRENT_DIR"
  fi
  if verify_release; then
    set_state SUCCESS
    telegram_alert info "deployment succeeded"
  else
    rollback_release
  fi
}

with_global_lock run_deploy
