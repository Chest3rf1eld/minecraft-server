# Local testing infrastructure

Runs `scripts/deploy.sh`, `scripts/backup.sh`, `scripts/restore.sh`, and
`scripts/prepare-release.sh` completely unmodified, without touching the
production VPS. Design and decisions: `SPEC.md` §12.5. Tracking issue: #9,
implementation issue: #11.

## What this replaces, and what it doesn't

- **Real:** the scripts themselves, restic, rclone, flock-based locking,
  a local minio container standing in for Yandex Disk.
- **Faked:** there is no real Paper JVM. `systemctl` and `curl` are shimmed
  (`bin/`) so `is-active`/`start`/`stop` control a lightweight TCP+RCON
  stub (`stub/minecraft_stub.py`) instead of a real server process, and
  downloads (Paper/plugins, Telegram, Healthchecks.io) never hit the
  network. `fallocate`/`mkswap`/`swapon`/`sysctl` are also no-ops --
  `ensure-swap.sh` does real host-level work that has no place running
  against the Docker host.
- **Not covered here:** Ansible provisioning, and anything about Paper's
  own startup behavior (world generation, plugin loading, the EULA
  check). Those need the real VPS -- see `docs/OPERATIONS.md`.

## Running it

Requires Docker Desktop running.

```bash
docker compose -f test/local/docker-compose.yml up --build --abort-on-container-exit
```

Exit code is 0 if every test script passed, non-zero otherwise. Everything
is ephemeral (`tmpfs` for `/srv/minecraft` and minio's data dir): each run
starts from a clean slate, and nothing survives `docker compose down`.

To re-run after a script change without rebuilding minio:

```bash
docker compose -f test/local/docker-compose.yml up --build test-runner
```

## Layout

- `Dockerfile` / `docker-compose.yml` -- the test container + minio.
- `bin/` -- shims (`systemctl`, `curl`, `fallocate`, `mkswap`, `swapon`,
  `sysctl`), placed ahead of the real ones in `PATH`.
- `stub/minecraft_stub.py` -- status-ping + RCON stub the shimmed
  `systemctl start/stop` controls.
- `fixtures/` -- `rclone.conf` pointed at the local minio, and throwaway
  restic/Telegram/Healthchecks "secrets" (their content doesn't matter;
  `curl` is shimmed, so nothing real ever reads them over the network).
- `tests/harness.sh` -- shared setup (`reset_environment`,
  `prepare_release`) and assertions, sourced by every `test-*.sh`.
- `tests/test-*.sh` -- one file per scenario (deploy cycle, backup/restore,
  rollback, lock contention). `run-tests.sh` runs all of them and reports
  one pass/fail summary.

## Adding a scenario

Add `tests/test-my-thing.sh` following the existing ones (source
`harness.sh`, call `reset_environment` at the top, define test functions,
run them with `run_test "description" fn`, end with `report_and_exit`) --
`run-tests.sh` picks up any `test-*.sh` automatically.

If a scenario needs a release to intentionally fail startup (for testing
rollback), touch a `.force_fail` marker file inside that specific release
directory before deploying it -- see `bin/systemctl` and
`tests/test-rollback.sh`.
