#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SWAP_FILE=${SWAP_FILE:-/swapfile}
SWAP_SIZE=${SWAP_SIZE:-2G}
SWAPPINESS=${SWAPPINESS:-10}
SYSCTL_CONF=${SYSCTL_CONF:-/etc/sysctl.d/99-minecraft-swappiness.conf}
FSTAB_PATH=${FSTAB_PATH:-/etc/fstab}

# minecraft.service runs Java with a heap ceiling (-Xmx) that can approach
# total VPS RAM once JVM off-heap overhead is counted, and chunk
# pregeneration has been observed pushing available memory close to zero.
# Every step here is idempotent (checked before acting), so this is safe to
# call on every deploy -- it only ever does anything the first time, and
# self-heals if the swap file or its config ever goes missing (VPS
# migration, disk cleanup, a rebuilt host).
ensure_swap() {
  if [[ ! -f "$SWAP_FILE" ]]; then
    log "creating swap file ${SWAP_FILE} (${SWAP_SIZE})"
    fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
  fi

  if ! swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE"; then
    log "enabling swap file ${SWAP_FILE}"
    swapon "$SWAP_FILE"
  fi

  if ! grep -q "^${SWAP_FILE} " "$FSTAB_PATH" 2>/dev/null; then
    log "persisting swap file in ${FSTAB_PATH}"
    printf '%s none swap sw 0 0\n' "$SWAP_FILE" >>"$FSTAB_PATH"
  fi

  if [[ ! -f "$SYSCTL_CONF" ]] || ! grep -qx "vm.swappiness=${SWAPPINESS}" "$SYSCTL_CONF"; then
    log "setting vm.swappiness=${SWAPPINESS}"
    printf 'vm.swappiness=%s\n' "$SWAPPINESS" >"$SYSCTL_CONF"
    sysctl -w "vm.swappiness=${SWAPPINESS}" >/dev/null
  fi
}

ensure_swap
