# Plugins

Plugin JAR files are not committed. Versions are declared in `../versions.yml` and are installed during release preparation.

Required plugins for v1:

- AuthMeReloaded — its `config.yml` must keep `settings.restrictions.timeout: 60` (players need enough time to type a password twice) and `settings.restrictions.maxRegPerIp: 0` (unlimited registrations per IP, so a second player behind the same household/NAT can still register); `scripts/ensure-authme-config.sh` self-heals both on every deploy cycle since the config file lives in the persistent, uncommitted plugin data directory.
- CoreProtect

Optional administrative plugin:

- Chunky

Optional gameplay plugin:

- Dynamic Lights — held/worn light sources illuminate the world around a player without placing blocks. Its config.yml must keep `track_mobs: false` so mobs holding light sources (e.g. a zombie with a torch) don't also emit light; `scripts/ensure-dynamiclights-config.sh` self-heals this setting on every deploy cycle since the config file itself lives in the persistent, uncommitted plugin data directory.

Optional communication plugin (issue #20):

- DiscordSRV — its Voice Proximity module (`voice.yml`) links a Discord voice channel to in-game distance, so nearby players hear each other over Discord. It is pinned in `../versions.yml`; `scripts/ensure-discordsrv-config.sh` bootstraps its default files on first deploy, applies the project's chat and voice channel IDs, and renders the bot token from `DISCORD_BOT_TOKEN` (`../../docs/SECRETS.md`) on every deploy cycle. Local live testing confirmed bot login, chat relay, and two-player proximity voice. See `../../docs/LOCAL_PLUGIN_TESTING.md` for the test setup and production configuration details.
