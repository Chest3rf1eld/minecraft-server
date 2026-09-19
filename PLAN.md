# Minecraft Server Infrastructure Implementation Plan

> Status: Ready for implementation
> Source documents: `SPEC.md`, `minecraft-server-architecture.md`

---

## Guiding Decisions

- Build for one existing Debian 13 VPS reachable over SSH.
- Do not create VPS infrastructure with Terraform or provider APIs in v1.
- Keep Paper as a native Java process managed by systemd; do not use Docker.
- Use a public GitHub repository, but never commit secrets, worlds, databases, logs, or backups.
- Use pre-provisioned GitHub Secrets and a GitHub `production` Environment for deployment secrets and approval.
- Select the latest stable Minecraft version during implementation, then pin Minecraft, Paper, Java, and plugin versions in metadata.
- Automate Paper update PRs in v1; defer plugin update automation.
- Use one global operation lock for backup, deployment, force deployment, and restore.
- Restore workflow v1 performs full mutable-state restore only.
- AuthMe password recovery is owner-only manual reset after out-of-game identity verification.
- Recovery targets are best effort: RPO up to 24 hours is acceptable, RTO is best effort.

---

## Phase 1 - Repository Foundation And CI

### Scope

- Create the repository layout.
- Add version metadata and validation.
- Add CI checks that can run without a production VPS.

### Tasks

1. Create directories:
   - `docs/`
   - `ansible/`
   - `minecraft/`
   - `scripts/`
   - `systemd/`
   - `.github/workflows/`
2. Add `minecraft/versions.yml` with pinned fields for:
   - Minecraft version
   - Paper build
   - Java major version
   - AuthMeReloaded version
   - CoreProtect version
   - optional Chunky version
3. Add `.gitignore` for:
   - worlds
   - plugin runtime data
   - logs
   - backups
   - secrets
   - local Ansible inventory overrides
4. Add initial docs:
   - `README.md`
   - `docs/ARCHITECTURE.md`
   - `docs/OPERATIONS.md`
   - `docs/BACKUP_RESTORE.md`
   - `docs/DISASTER_RECOVERY.md`
5. Add CI workflow for:
   - YAML validation
   - Ansible syntax check
   - `ansible-lint`
   - `shellcheck`
   - secret scanning
   - repository consistency checks
6. Add Paper smoke test workflow or job:
   - install pinned Java
   - download pinned Paper build
   - prepare temporary server directory
   - accept EULA in temporary CI environment
   - start Paper
   - wait for successful startup
   - perform Minecraft status ping
   - stop server cleanly

### Exit Criteria

- CI runs on PRs.
- Broken YAML, shell, Ansible, version metadata, or obvious secrets fail CI.
- Paper smoke test passes on a GitHub-hosted runner without touching production.

---

## Phase 2 - Ansible Provisioning

### Scope

Provision an already-created Debian 13 VPS over SSH.

### Tasks

1. Create Ansible inventory structure for production.
2. Implement roles:
   - `base`
   - `java`
   - `minecraft`
   - `firewall`
   - `backup`
   - `monitoring`
   - `deployment`
3. Configure SSH hardening:
   - `PermitRootLogin no`
   - `PasswordAuthentication no`
   - `PubkeyAuthentication yes`
4. Create Unix user `minecraft` without unrestricted sudo.
5. Create filesystem layout under `/srv/minecraft/` and `/etc/minecraft/secrets/`.
6. Install required packages:
   - Java version required by selected Paper release
   - restic
   - rclone
   - firewall tooling
   - SQLite CLI if needed for plugin inspection
7. Install systemd units and timers from repository templates.
8. Apply firewall policy:
   - default deny incoming
   - allow SSH
   - allow Minecraft TCP 25565
   - do not expose RCON

### Exit Criteria

- Ansible can configure a fresh Debian 13 VPS.
- Re-running Ansible is idempotent and does not break the server.
- SSH password login and root SSH login are disabled.
- Required directories, permissions, and systemd units exist.

---

## Phase 3 - Minecraft Runtime

### Scope

Install and verify Paper, AuthMeReloaded, whitelist, CoreProtect, and base configuration.

### Tasks

1. Download and install pinned Paper build.
2. Configure JVM heap defaults:
   - `-Xms2G`
   - `-Xmx3G`
3. Configure `server.properties`:
   - `max-players=5`
   - `online-mode=false`
   - `white-list=true`
   - `enforce-whitelist=true`
   - RCON enabled on localhost only
   - initial `view-distance=8`
   - initial `simulation-distance=6`
4. Install AuthMeReloaded and CoreProtect.
5. Configure CoreProtect SQLite retention around 30 days.
6. Configure OP only for trusted administrator accounts.
7. Ensure AuthMe is treated as security-critical:
   - deployment verification fails if AuthMe is missing or unloaded
   - do not leave unauthenticated offline-mode server online
8. Document owner-only AuthMe password reset procedure.

### Exit Criteria

- Paper starts under `minecraft.service`.
- Minecraft status ping succeeds.
- AuthMe registration/login works for offline clients.
- Whitelist works.
- CoreProtect records player actions.
- RCON is local-only.

---

## Phase 4 - Backup System

### Scope

Implement encrypted offsite backups and mandatory pre-deploy backup behavior.

### Tasks

1. Configure restic repository through rclone to Yandex Disk.
2. Store restic/rclone secrets via GitHub Secrets and runtime secret files with restrictive permissions.
3. Implement `scripts/backup.sh`.
4. Include mutable state:
   - `world/`
   - `world_nether/`
   - `world_the_end/`
   - plugin runtime data
   - AuthMe data
   - CoreProtect SQLite database
   - whitelist, bans, ops
   - runtime config not reproducible from Git
5. Use RCON consistency procedure:
   - at minimum `save-all flush`
   - if `save-off` is used, guarantee `save-on` through traps
6. Add global operation lock.
7. Add scheduled backup timer every 6 hours.
8. Add restic retention:
   - 4 snapshots/day for 7 days
   - 1 snapshot/day for 30 days
   - 1 snapshot/month for 6 months
9. Add backup Healthchecks.io signaling.

### Exit Criteria

- Manual backup succeeds.
- Scheduled backup succeeds.
- Failed backup alerts owner.
- Pre-deploy backup failure blocks deployment.
- Restic snapshots are visible in the Yandex Disk-backed repository.

---

## Phase 5 - Monitoring And Alerts

### Scope

Add lightweight local and external monitoring.

### Tasks

1. Implement `scripts/healthcheck.sh` to check:
   - `minecraft.service` state
   - Minecraft protocol status ping
   - disk usage
   - memory pressure using `MemAvailable`
   - backup age
   - deployment state
2. Configure systemd timer for local health checks.
3. Configure systemd restart behavior:
   - `Restart=on-failure`
   - rate limiting to avoid restart storms
4. Implement `scripts/telegram.sh`.
5. Alert classes:
   - critical: VPS heartbeat lost, Minecraft unavailable after recovery, crash loop, deployment failed, rollback failed, backup failed, backup stale, disk critically full
   - warning: disk warning, sustained memory pressure, deployment pending over 24h, rollback performed
   - info: successful deployment, optional rollback success, optional version update status
6. Configure Healthchecks.io:
   - VPS heartbeat
   - backup watchdog

### Exit Criteria

- Local health check detects unhealthy Minecraft server.
- Telegram alerts are delivered for test failures.
- Healthchecks.io detects missed heartbeat or overdue backup.
- Restart loops are rate-limited and produce a critical alert.

---

## Phase 6 - Deployment Controller

### Scope

Implement safe player-aware deployments and rollback.

### Tasks

1. Implement release directory layout:
   - current release
   - previous release
   - limited retained older releases
   - shared mutable state
2. Implement persisted deployment state.
3. Implement `scripts/player-count.sh`.
4. Implement `scripts/deploy.sh` state machine:
   - pending
   - waiting for empty server
   - 5-minute empty grace period
   - backup
   - deploying
   - verifying
   - success or failed
   - rollback
   - verify rollback
5. Add deployment pending notifications:
   - owner Telegram after 24 hours
   - in-game notice after 24 hours
   - repeat in-game every 6 hours
   - repeat Telegram every 24 hours
6. Implement verification checks:
   - systemd running
   - Paper completed startup
   - Minecraft status ping succeeds
   - expected Minecraft version matches
   - required plugins loaded
   - no fatal startup error
   - AuthMe loaded
7. Implement automatic release rollback for ordinary deploy failures.
8. Implement force deploy workflow:
   - owner-triggered only
   - may bypass player wait
   - still requires pre-deploy backup
   - clearly marked in logs and Telegram
9. Implement production deploy workflow:
   - merge to `main`
   - manual GitHub Environment approval
   - SSH deployment request

### Exit Criteria

- Normal deployment waits while players are online.
- Player joining during grace period cancels countdown.
- Pre-deploy backup is mandatory.
- Failed deployment rolls back previous release.
- Failed rollback produces critical alert.
- Force deploy works only through explicit manual workflow.

---

## Phase 7 - Paper Update Automation

### Scope

Automate Paper update discovery only.

### Tasks

1. Add scheduled workflow to check PaperMC API for newer compatible builds.
2. Create or update a PR when a newer Paper build exists.
3. Update `minecraft/versions.yml` in the PR.
4. Run CI and Paper smoke test on the PR.
5. Do not auto-merge.
6. Do not auto-deploy.
7. Document plugin update process as manual in v1.

### Exit Criteria

- Paper update PR can be created automatically.
- New Minecraft version is never deployed automatically.
- Plugin update automation is explicitly deferred.

---

## Phase 8 - Full Restore And Disaster Recovery

### Scope

Implement full mutable-state restore and validate disaster recovery.

### Tasks

1. Implement `scripts/restore.sh` for full mutable state restore only.
2. Implement `.github/workflows/restore-backup.yml` with:
   - manual `workflow_dispatch`
   - backup snapshot or timestamp input
   - explicit confirmation input
   - full restore scope only
3. Restore procedure:
   - acquire global lock
   - stop Minecraft
   - restore selected restic snapshot
   - restore compatible release if needed
   - start Minecraft
   - verify health
   - notify owner
4. Document disaster recovery path:
   - create new Debian 13 VPS manually
   - update DNS if IP changed
   - use pre-provisioned GitHub Secrets
   - run Ansible bootstrap
   - restore from Yandex Disk
   - verify service
5. Run at least one restore test.

### Exit Criteria

- Full restore workflow requires explicit manual confirmation.
- Restore cannot be triggered by a normal push.
- Full mutable state restore is tested.
- Disaster recovery runbook is accurate enough for a new VPS recovery.

---

## Final V1 Acceptance Checklist

- Fresh Debian 13 VPS can be prepared using Ansible.
- Re-running Ansible is safe.
- Paper starts successfully.
- Maximum players is 5.
- Offline clients can use AuthMe registration/login.
- Whitelist works.
- CoreProtect records player changes.
- PRs trigger required tests.
- Broken shell, YAML, Ansible, or version metadata fails CI.
- Secret leaks are detected.
- Paper smoke test runs on GitHub-hosted runner.
- Production deployment requires manual GitHub approval.
- Deployment waits while players are online.
- No player is automatically kicked in normal deployment.
- Empty server remains empty for 5 minutes before deployment.
- Pre-deploy backup is mandatory.
- Failed backup blocks deployment.
- Failed normal deployment rolls back automatically.
- Paper updates can create automated PRs.
- New Minecraft versions are never automatically deployed.
- Backups run every 6 hours.
- Backups are encrypted.
- Backups are stored outside the VPS.
- Retention policy is enforced.
- Full restore procedure is tested.
- Minecraft failure generates Telegram alert.
- Complete VPS failure generates Telegram alert through Healthchecks.io.
- Missing backup generates alert.
- Disk usage is monitored.
- SSH password login is disabled.
- Root SSH login is disabled.
- RCON is not public.
- Secrets are absent from the public repository.
- A new VPS can be reconstructed from GitHub repository, pre-provisioned GitHub Secrets, and Yandex Disk backup.
