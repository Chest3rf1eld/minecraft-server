#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FAILURES=0
WARNINGS=0
HOST=${MINECRAFT_HEALTH_HOST:-127.0.0.1}
PORT=${MINECRAFT_HEALTH_PORT:-25565}
DISK_WARNING=${MINECRAFT_DISK_WARNING_PERCENT:-80}
DISK_CRITICAL=${MINECRAFT_DISK_CRITICAL_PERCENT:-90}
BACKUP_MAX_AGE_SECONDS=${BACKUP_MAX_AGE_SECONDS:-86400}

check_service() {
  if ! systemctl is-active --quiet minecraft.service; then
    log "minecraft.service is not active"
    FAILURES=$((FAILURES + 1))
  fi
}

check_ping() {
  if ! "$SCRIPT_DIR/minecraft-status.py" "$HOST" "$PORT" >/tmp/minecraft-status.json; then
    log "Minecraft protocol ping failed"
    FAILURES=$((FAILURES + 1))
  fi
}

check_disk() {
  local usage
  usage=$(df -P "$MINECRAFT_ROOT" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
  if [[ "$usage" -ge "$DISK_CRITICAL" ]]; then
    telegram_alert critical "disk usage critical: ${usage}%"
    FAILURES=$((FAILURES + 1))
  elif [[ "$usage" -ge "$DISK_WARNING" ]]; then
    telegram_alert warning "disk usage warning: ${usage}%"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_backup_age() {
  local stamp="$MINECRAFT_STATE_DIR/last-backup-success"
  if [[ ! -f "$stamp" ]]; then
    telegram_alert critical "no successful backup marker exists"
    FAILURES=$((FAILURES + 1))
    return
  fi
  local now last age
  now=$(date +%s)
  last=$(stat -c %Y "$stamp")
  age=$((now - last))
  if [[ "$age" -gt "$BACKUP_MAX_AGE_SECONDS" ]]; then
    telegram_alert critical "backup is stale: ${age}s old"
    FAILURES=$((FAILURES + 1))
  fi
}

check_memory() {
  local available_kb
  available_kb=$(awk '/MemAvailable:/ { print $2 }' /proc/meminfo)
  if [[ "$available_kb" -lt 262144 ]]; then
    telegram_alert warning "MemAvailable is below 256 MiB"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_service
check_ping
check_disk
check_backup_age
check_memory

if [[ "$FAILURES" -gt 0 ]]; then
  telegram_alert critical "healthcheck failed with ${FAILURES} failures and ${WARNINGS} warnings"
  exit 1
fi

log "healthcheck passed with ${WARNINGS} warnings"
