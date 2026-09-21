# Plugins

Plugin JAR files are not committed. Versions are declared in `../versions.yml` and are installed during release preparation.

Required plugins for v1:

- AuthMeReloaded
- CoreProtect

Optional administrative plugin:

- Chunky

Optional gameplay plugin:

- Dynamic Lights — held/worn light sources illuminate the world around a player without placing blocks. Its config.yml must keep `track_mobs: false` so mobs holding light sources (e.g. a zombie with a torch) don't also emit light; `scripts/ensure-dynamiclights-config.sh` self-heals this setting on every deploy cycle since the config file itself lives in the persistent, uncommitted plugin data directory.
