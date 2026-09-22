#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DISCORDSRV_CONFIG=${DISCORDSRV_CONFIG:-$MINECRAFT_SHARED_DIR/plugins/DiscordSRV/config.yml}
DISCORD_BOT_TOKEN_FILE=${DISCORD_BOT_TOKEN_FILE:-/etc/minecraft/secrets/discord_bot_token}

# DiscordSRV writes its own config.yml on first run with a literal
# BotToken: "BOTTOKEN" placeholder (see minecraft/plugins/README.md); the
# real token is a secret (docs/SECRETS.md, DISCORD_BOT_TOKEN) and must never
# be committed, so it's rendered in here from
# /etc/minecraft/secrets/discord_bot_token instead -- same self-heal
# approach as ensure-authme-config.sh/ensure-dynamiclights-config.sh, so a
# plugin update or a hand-edit that reverts the key back to the placeholder
# gets corrected on the next deploy tick rather than leaving the bot offline
# until someone notices.
ensure_discordsrv_token() {
  if [[ ! -f "$DISCORDSRV_CONFIG" ]]; then
    log "DiscordSRV config not present yet at ${DISCORDSRV_CONFIG} (plugin has not started); nothing to heal"
    return
  fi
  if [[ ! -r "$DISCORD_BOT_TOKEN_FILE" ]]; then
    log "no readable token at ${DISCORD_BOT_TOKEN_FILE}; leaving ${DISCORDSRV_CONFIG} as-is"
    return
  fi

  local token escaped_token
  token=$(<"$DISCORD_BOT_TOKEN_FILE")

  if grep -qxF "BotToken: \"${token}\"" "$DISCORDSRV_CONFIG"; then
    return
  fi

  log "forcing BotToken in ${DISCORDSRV_CONFIG}"
  # Escape sed's replacement-side special characters (backslash, the "|"
  # delimiter used below, and "&" which sed expands to the whole match) so
  # the token is substituted as a literal string regardless of its content.
  escaped_token=$(printf '%s' "$token" | sed -e 's/[\&|]/\\&/g')
  sed -i "s|^BotToken:.*|BotToken: \"${escaped_token}\"|" "$DISCORDSRV_CONFIG"
}

ensure_discordsrv_token
