# Backup And Restore

## Backup Policy

- Scheduled backups run every 6 hours.
- A pre-deploy backup is mandatory before any deployment that can change runtime state.
- Backups are encrypted with restic and uploaded to Yandex Disk through rclone.
- A failed pre-deploy backup blocks deployment.

## Backup Contents

Backups include mutable state required to reconstruct the Minecraft service:

- `world/`
- `world_nether/`
- `world_the_end/`
- plugin runtime data
- AuthMe data
- CoreProtect SQLite database
- whitelist, bans, ops
- runtime config not reproducible from Git

Paper and plugin JARs are normally reproduced from pinned metadata and are not the primary purpose of backups.

## Retention

Initial restic retention policy:

```text
4 snapshots/day for 7 days
1 snapshot/day for 30 days
1 snapshot/month for 6 months
```

## Manual Backup

```bash
sudo /opt/minecraft/bin/backup.sh scheduled
```

## Full Restore V1

Selective restore is out of scope for v1. The restore workflow restores full mutable state from a selected restic snapshot.

High-level restore flow:

1. Acquire global operation lock.
2. Stop Minecraft.
3. Restore selected snapshot into the mutable state location.
4. Start Minecraft.
5. Verify service health.
6. Notify owner.

Use `.github/workflows/restore-backup.yml` for owner-confirmed restore from GitHub Actions.
