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

Run the complete local test pass, including the real Paper/plugin startup
smoke:

```bash
bash test/local/run-all.sh
```

This runs the fast isolated deploy suite first and then the networked Paper
plugin smoke. It can take several minutes on the first run.

To run only the fast, offline-friendly suite:

```bash
bash test/local/run-fast.sh
```

The full test pass downloads the pinned Paper/plugin JARs and verifies that the
real Paper server starts and enables the configured plugins. To run just that
integration smoke:

```bash
docker compose --env-file .env -f test/local/docker-compose.yml --profile plugins run --build --rm paper-plugin-smoke
```

This profile needs internet access. It uses disposable fallback values unless
you explicitly provide local overrides, and an
ephemeral server directory; it does not connect to production services or
persist a world. The fast suite tests deploy/backup/restore behavior, while the
plugin smoke tests real artifact compatibility and startup.

The Paper smoke accepts `RCON_PASSWORD`, `MANAGEMENT_SERVER_SECRET`, and
`AUTHME_MYSQL_PASSWORD` from the invoking shell, or from the ignored project
root `.env` file. It falls back to disposable values when they are unset. GitHub
does not provide a way for a local process to read back environment secret
values. A safe pre-deploy check of the actual `production` secrets is tracked
separately in issue #31.

To use local overrides, create the ignored root `.env` file with these entries
(quote values only if the parser requirements of your environment call for it):

```dotenv
RCON_PASSWORD=local-value
MANAGEMENT_SERVER_SECRET=local-value
AUTHME_MYSQL_PASSWORD=local-value
```

`run-all.sh` passes this file to Compose when it exists. The direct Compose
command above assumes `.env` exists; omit `--env-file .env` to use fallback
values when it does not.

Exit code is 0 if every test script passed, non-zero otherwise. Everything
is ephemeral (`tmpfs` for `/srv/minecraft` and minio's data dir): each run
starts from a clean slate, and nothing survives `docker compose down`.

To re-run a single test script after a change without rebuilding minio:

```bash
bash test/local/run-fast.sh /opt/test/tests/test-discordsrv-config.sh
```

`run-fast.sh` and `run-all.sh` stop the Compose stack after testing, including
when a test fails or is interrupted. Direct `docker compose` commands can leave
dependency containers such as MinIO running after the test runner exits.

## Layout

- `Dockerfile` / `docker-compose.yml` -- the test container + minio.
- `PaperSmoke.Dockerfile` / `run-paper-plugin-smoke.sh` -- optional real Paper
  and plugin startup integration check.
- `run-all.sh` -- runs both test layers and tears down the Compose stack.
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
