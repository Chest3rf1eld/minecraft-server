# Operations Runbook

## Service Commands

```bash
sudo systemctl status minecraft
sudo systemctl restart minecraft
sudo journalctl -u minecraft -n 200 --no-pager
sudo journalctl -u minecraft -f
```

## Health Checks

```bash
sudo /opt/minecraft/bin/healthcheck.sh
sudo /opt/minecraft/bin/player-count.sh
```

Health is not based on systemd alone. The health check must also perform a Minecraft status ping and verify required plugins where practical.

## Deployment Flow

Normal deployment happens through GitHub Actions after merge to `main` and manual approval of the `production` environment.

The VPS-side controller waits until the server is empty, waits an additional 5-minute grace period, creates a pre-deploy backup, deploys the release, verifies health, and rolls back binaries/configuration if verification fails.

## Force Deploy

Use force deploy only for owner-approved emergencies. It may bypass player waiting, but still requires a successful pre-deploy backup and health verification.

## AuthMe Password Reset

AuthMe password recovery is manual in v1:

1. Verify the player identity outside Minecraft.
2. Use the AuthMe administrative command or documented plugin data procedure to reset the password.
3. Ask the player to log in and set a new password.
4. Do not automate self-service recovery in v1.

## Disk Pressure

Initial thresholds:

- warning: 80%
- critical: 90%

If disk is high, inspect world growth, logs, CoreProtect SQLite size, local releases, and temporary backup files. Do not delete current or previous known-good release while investigating deploy issues.

## Version Updates

Paper release preparation uses `paper.download_url` from `minecraft/versions.yml` when present. The current Paper artifact requires Java 25 or newer, so Java 25 is the pinned runtime target. The automated Paper update checker is disabled while a direct artifact URL is configured. Minecraft version upgrades are manual and require extra caution because world data may migrate. Plugin updates are manual in v1.

## OP And Whitelist

Initial OP and whitelist entries are managed manually through Minecraft console/RCON commands after bootstrap. Do not commit generated `ops.json` or `whitelist.json` runtime files to Git.
