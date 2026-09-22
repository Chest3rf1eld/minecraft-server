# Plugins

Plugin JAR files are not committed. Versions are declared in `../versions.yml` and are installed during release preparation.

Required plugins for v1:

- AuthMeReloaded — its `config.yml` must keep `settings.restrictions.timeout: 60` (players need enough time to type a password twice) and `settings.restrictions.maxRegPerIp: 0` (unlimited registrations per IP, so a second player behind the same household/NAT can still register); `scripts/ensure-authme-config.sh` self-heals both on every deploy cycle since the config file lives in the persistent, uncommitted plugin data directory.
- CoreProtect

Optional administrative plugin:

- Chunky

Optional gameplay plugin:

- Dynamic Lights — held/worn light sources illuminate the world around a player without placing blocks. Its config.yml must keep `track_mobs: false` so mobs holding light sources (e.g. a zombie with a torch) don't also emit light; `scripts/ensure-dynamiclights-config.sh` self-heals this setting on every deploy cycle since the config file itself lives in the persistent, uncommitted plugin data directory.
- DiscordSRV — its Voice Proximity module (`voice.yml`) links a Discord voice channel to in-game distance, so nearby players hear each other over Discord. Its `config.yml`/`voice.yml` regenerate with placeholder/disabled defaults (`BotToken: "BOTTOKEN"`, no chat bridge, no voice category/lobby channel, `Voice enabled: false`) whenever those keys go missing; `scripts/ensure-discordsrv-config.sh` renders the real token (from the `DISCORD_BOT_TOKEN` secret, `../../docs/SECRETS.md`), the project's real Discord server/channel IDs, and `Voice enabled: true` in on every deploy cycle. See `../../docs/LOCAL_PLUGIN_TESTING.md` for how it was built and tested locally before being added here (issue #20).
