#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DYNAMICLIGHTS_CONFIG=${DYNAMICLIGHTS_CONFIG:-$MINECRAFT_SHARED_DIR/plugins/DynamicLights/config.yml}

# DynamicLights defaults track_mobs to true and regenerates that default
# whenever its config is missing the key, so mobs holding a light source
# (e.g. a zombie with a torch) would otherwise emit dynamic light too. The
# config file lives in the plugin's own persistent, uncommitted data
# directory, so it can drift back to the default on a plugin update or a
# manual edit -- this is idempotent (checked before acting), so it is safe
# to call on every deploy and self-heals track_mobs back to false whenever
# it drifts.
ensure_dynamiclights_config() {
  if [[ ! -f "$DYNAMICLIGHTS_CONFIG" ]]; then
    log "DynamicLights config not present yet at ${DYNAMICLIGHTS_CONFIG} (plugin has not started); nothing to heal"
    return
  fi

  if grep -qx 'track_mobs: false' "$DYNAMICLIGHTS_CONFIG"; then
    return
  fi

  if grep -q '^track_mobs:' "$DYNAMICLIGHTS_CONFIG"; then
    log "forcing track_mobs: false in ${DYNAMICLIGHTS_CONFIG}"
    sed -i 's/^track_mobs:.*/track_mobs: false/' "$DYNAMICLIGHTS_CONFIG"
  else
    log "adding track_mobs: false to ${DYNAMICLIGHTS_CONFIG}"
    printf 'track_mobs: false\n' >>"$DYNAMICLIGHTS_CONFIG"
  fi
}

ensure_dynamiclights_config
