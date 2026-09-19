# Disaster Recovery

The target recovery set is:

```text
GitHub repository
+ pre-provisioned GitHub Secrets / production Environment
+ Yandex Disk restic backups
```

RPO is best effort with up to 24 hours acceptable for this private server. RTO is best effort.

## Full VPS Loss

1. Create a new Debian 13 minimal VPS manually.
2. Add or confirm SSH key access for the owner/bootstrap user.
3. Update `minecraft.nikchester.ru` DNS if the IP changed.
4. Confirm GitHub `production` secrets are still present.
5. Prepare production inventory from `ansible/inventory/production/hosts.example.yml`.
6. Run Ansible bootstrap.
7. Run the full restore workflow against the selected restic snapshot.
8. Verify Minecraft status ping, AuthMe, whitelist, CoreProtect, backup, and alerts.

## Critical Safety Rules

- Do not automatically restore world data during ordinary deploy rollback.
- Do not automatically roll back world data after Minecraft version migration.
- Do not run restore concurrently with backup or deployment.
- Do not trigger restore from normal push events.
