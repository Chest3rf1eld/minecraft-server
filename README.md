# Minecraft Server Infrastructure

Production-like infrastructure for a small private Minecraft server at `minecraft.nikchester.ru`.

The project intentionally keeps runtime operations simple: one Debian 13 VPS, Paper as a native Java process under systemd, Ansible for provisioning, GitHub Actions for validation/deployment, restic+rclone backups to Yandex Disk, and lightweight Telegram/Healthchecks.io monitoring.

## Documents

- `SPEC.md` - implementation contract and requirements.
- `PLAN.md` - phased implementation plan and exit criteria.
- `minecraft-server-architecture.md` - detailed architecture rationale and constraints.
- `docs/OPERATIONS.md` - day-to-day commands and runbooks.
- `docs/BACKUP_RESTORE.md` - backup and restore procedure.
- `docs/DISASTER_RECOVERY.md` - full VPS loss recovery.
- `docs/SECRETS.md` - expected GitHub secret names.

## Core Constraints

- No Docker or Kubernetes in v1.
- No public RCON.
- No secrets, worlds, databases, logs, or backups in Git.
- No normal deployment kicks players automatically.
- Failed pre-deploy backup blocks deployment.
- AuthMeReloaded is mandatory because `online-mode=false`.
- World rollback after Minecraft version migration requires explicit manual restore.

## Bootstrap Summary

1. Create or confirm a Debian 13 minimal VPS.
2. Point `minecraft.nikchester.ru` to the VPS IP.
3. Add required GitHub Secrets and configure the `production` environment.
4. Fill `ansible/inventory/production/hosts.yml` from `ansible/inventory/production/hosts.example.yml`.
5. Run Ansible bootstrap.
6. Verify Paper, AuthMe, whitelist, CoreProtect, backups, and monitoring.

See `docs/OPERATIONS.md` and `docs/DISASTER_RECOVERY.md` for detailed commands.

## Local Validation

Install the same tools used in CI when available:

```bash
python3 scripts/validate-repository.py
shellcheck scripts/*.sh
ansible-playbook -i ansible/inventory/production/hosts.example.yml ansible/playbooks/bootstrap.yml --syntax-check
ansible-lint ansible/
```

The Paper smoke test runs in GitHub Actions and uses a temporary CI server directory only.
