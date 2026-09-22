#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DISCORDSRV_CONFIG=${DISCORDSRV_CONFIG:-$MINECRAFT_SHARED_DIR/plugins/DiscordSRV/config.yml}
DISCORDSRV_VOICE_CONFIG=${DISCORDSRV_VOICE_CONFIG:-$MINECRAFT_SHARED_DIR/plugins/DiscordSRV/voice.yml}
DISCORD_BOT_TOKEN_FILE=${DISCORD_BOT_TOKEN_FILE:-/etc/minecraft/secrets/discord_bot_token}

# The project's one real Discord server -- the same IDs
# test/paper-local/entrypoint.sh seeds locally (see
# docs/LOCAL_PLUGIN_TESTING.md); not secret (none grants access on its own
# without the bot already invited with the right permissions), so committed
# here rather than rendered from a secret file like the token above.
DISCORD_CHANNEL_ID="1551597801933242418"
DISCORD_VOICE_CATEGORY_ID="1551598654245310494"
DISCORD_LOBBY_CHANNEL_ID="1551598909024112726"

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

# Same self-heal approach as the token above: config.yml/voice.yml live in
# the plugin's own persistent, uncommitted data directory, so a plugin
# update or hand-edit could drift these back to their generated defaults
# (an empty Channels map, a null Voice category/Lobby channel, Voice
# enabled: false). This forces them back to the real server on every tick
# instead of leaving the chat bridge or voice module silently unconfigured.
ensure_discordsrv_channels() {
  if [[ ! -f "$DISCORDSRV_CONFIG" ]]; then
    log "DiscordSRV config not present yet at ${DISCORDSRV_CONFIG} (plugin has not started); nothing to heal"
    return
  fi

  if ! grep -qxF "Channels: {\"global\": \"${DISCORD_CHANNEL_ID}\"}" "$DISCORDSRV_CONFIG"; then
    log "forcing Channels in ${DISCORDSRV_CONFIG}"
    sed -i "s|^Channels:.*|Channels: {\"global\": \"${DISCORD_CHANNEL_ID}\"}|" "$DISCORDSRV_CONFIG"
  fi
}

ensure_discordsrv_voice() {
  if [[ ! -f "$DISCORDSRV_VOICE_CONFIG" ]]; then
    log "DiscordSRV voice config not present yet at ${DISCORDSRV_VOICE_CONFIG} (plugin has not started); nothing to heal"
    return
  fi

  if ! grep -qxF "Voice category: ${DISCORD_VOICE_CATEGORY_ID}" "$DISCORDSRV_VOICE_CONFIG"; then
    log "forcing Voice category in ${DISCORDSRV_VOICE_CONFIG}"
    sed -i "s|^Voice category:.*|Voice category: ${DISCORD_VOICE_CATEGORY_ID}|" "$DISCORDSRV_VOICE_CONFIG"
  fi

  if ! grep -qxF "Lobby channel: ${DISCORD_LOBBY_CHANNEL_ID}" "$DISCORDSRV_VOICE_CONFIG"; then
    log "forcing Lobby channel in ${DISCORDSRV_VOICE_CONFIG}"
    sed -i "s|^Lobby channel:.*|Lobby channel: ${DISCORD_LOBBY_CHANNEL_ID}|" "$DISCORDSRV_VOICE_CONFIG"
  fi

  if ! grep -qxF "Voice enabled: true" "$DISCORDSRV_VOICE_CONFIG"; then
    log "enabling Voice in ${DISCORDSRV_VOICE_CONFIG}"
    sed -i "s|^Voice enabled:.*|Voice enabled: true|" "$DISCORDSRV_VOICE_CONFIG"
  fi
}

ensure_discordsrv_token
ensure_discordsrv_channels
ensure_discordsrv_voice
