#!/bin/sh
# Local test convenience only (not a secret -- see docs/LOCAL_PLUGIN_TESTING.md):
# points DiscordSRV's chat bridge at a public test channel on every start, so
# a fresh test/paper-local/data/ doesn't need to be hand-edited just to get
# chat relaying working before you've set up your own bot/server fully. The
# bot token itself is never touched here -- see the same doc for how that's
# supplied locally.
set -eu

CONFIG=/server/plugins/DiscordSRV/config.yml
VOICE_CONFIG=/server/plugins/DiscordSRV/voice.yml
TEST_CHANNEL_ID="1551597801933242418"
TEST_VOICE_CATEGORY_ID="1551598654245310494"
TEST_LOBBY_CHANNEL_ID="1551598909024112726"

if [ -f "$CONFIG" ] && ! grep -qxF "Channels: {\"global\": \"${TEST_CHANNEL_ID}\"}" "$CONFIG"; then
  sed -i "s|^Channels:.*|Channels: {\"global\": \"${TEST_CHANNEL_ID}\"}|" "$CONFIG"
fi

if [ -f "$VOICE_CONFIG" ] && ! grep -qxF "Voice category: ${TEST_VOICE_CATEGORY_ID}" "$VOICE_CONFIG"; then
  sed -i "s|^Voice category:.*|Voice category: ${TEST_VOICE_CATEGORY_ID}|" "$VOICE_CONFIG"
fi

if [ -f "$VOICE_CONFIG" ] && ! grep -qxF "Lobby channel: ${TEST_LOBBY_CHANNEL_ID}" "$VOICE_CONFIG"; then
  sed -i "s|^Lobby channel:.*|Lobby channel: ${TEST_LOBBY_CHANNEL_ID}|" "$VOICE_CONFIG"
fi

# Seeds a small worldborder (see datapacks/tiny-test-world) so proximity
# voice can be tested by walking a short distance instead of exploring a
# full world. world/datapacks doesn't exist yet on a brand new world, but
# Paper picks up whatever's there once it creates/loads "world" -- this
# just needs to run before the java process below, not before the world
# technically exists.
mkdir -p /server/world/datapacks
cp -r /server/datapack-template/tiny-test-world /server/world/datapacks/

exec java -Xms512M -Xmx1536M -jar paper.jar nogui
