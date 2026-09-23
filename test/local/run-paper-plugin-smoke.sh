#!/usr/bin/env bash
set -euo pipefail

release_id="plugin-smoke-$(date -u +%Y%m%dT%H%M%SZ)"
release_dir="${MINECRAFT_ROOT}/releases/${release_id}"
log_file="${release_dir}/logs/paper-smoke.log"
timeout_seconds=${PAPER_SMOKE_TIMEOUT_SECONDS:-600}
paper_pid=""

cleanup() {
  if [[ -n "$paper_pid" ]] && kill -0 "$paper_pid" 2>/dev/null; then
    kill "$paper_pid" 2>/dev/null || true
    wait "$paper_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

show_redacted_log_tail() {
  python3 - "$log_file" <<'PY'
import os
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
for line in lines[-60:]:
    for name in ("RCON_PASSWORD", "MANAGEMENT_SERVER_SECRET", "AUTHME_MYSQL_PASSWORD"):
        secret = os.environ.get(name, "")
        if secret:
            line = line.replace(secret, "[REDACTED]")
    print(line)
PY
}

echo "Preparing release ${release_id} from pinned repository versions..."
/opt/minecraft/bin/prepare-release.sh "$release_id"

python3 - "$release_dir" <<'PY'
import os
import pathlib
import sys
import yaml

release = pathlib.Path(sys.argv[1])
properties = {}
for line in (release / "server.properties").read_text(encoding="utf-8").splitlines():
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        properties[key] = value

authme = yaml.safe_load(
    pathlib.Path("/srv/minecraft/shared/plugins/AuthMe/config.yml").read_text(encoding="utf-8")
)
checks = {
    "RCON_PASSWORD": properties.get("rcon.password"),
    "MANAGEMENT_SERVER_SECRET": properties.get("management-server-secret"),
    "AUTHME_MYSQL_PASSWORD": authme["DataSource"]["mySQLPassword"],
}
for name, rendered in checks.items():
    if not os.environ.get(name) or rendered != os.environ[name]:
        print(f"FAIL: {name} was not rendered from the smoke environment.", file=sys.stderr)
        raise SystemExit(1)
    print(f"PASS: {name} reached the rendered runtime configuration.")
PY

echo "Starting the real Paper server and downloaded plugin JARs..."
cd "$release_dir"
java -Xms512M -Xmx1G -jar paper.jar nogui >"$log_file" 2>&1 &
paper_pid=$!

for ((second = 0; second < timeout_seconds; second += 2)); do
  if grep -Fq 'Done (' "$log_file"; then
    break
  fi
  if ! kill -0 "$paper_pid" 2>/dev/null; then
    echo "FAIL: Paper exited before completing startup. Last log lines (configured secrets redacted):" >&2
    show_redacted_log_tail >&2
    exit 1
  fi
  if (( second > 0 && second % 30 == 0 )); then
    echo "Paper is still starting (${second}s elapsed; timeout ${timeout_seconds}s)..."
  fi
  sleep 2
done

if ! grep -Fq 'Done (' "$log_file"; then
  echo "FAIL: Paper did not complete startup within ${timeout_seconds}s. Last log lines (configured secrets redacted):" >&2
  show_redacted_log_tail >&2
  exit 1
fi

for plugin in AuthMe CoreProtect Chunky DynamicLights; do
  if ! grep -Fq "Enabling ${plugin} " "$log_file"; then
    echo "FAIL: expected plugin ${plugin} was not enabled by Paper. Last log lines (configured secrets redacted):" >&2
    show_redacted_log_tail >&2
    exit 1
  fi
done

echo "PASS: Paper completed startup and enabled AuthMe, CoreProtect, Chunky, and DynamicLights."
