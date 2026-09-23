#!/usr/bin/env bash
set -euo pipefail

compose_file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/docker-compose.yml"
repo_root="$(cd -- "$(dirname -- "$compose_file")/../.." && pwd)"
compose_args=(-f "$compose_file")
if [[ -f "$repo_root/.env" ]]; then
  compose_args=(--env-file "$repo_root/.env" "${compose_args[@]}")
fi

cleanup() {
  docker compose "${compose_args[@]}" down --remove-orphans >/dev/null
}
trap cleanup EXIT

echo "==> Running the fast deploy/backup/restore suite..."
docker compose "${compose_args[@]}" up --build --abort-on-container-exit

echo "==> Running the real Paper/plugin startup smoke..."
docker compose "${compose_args[@]}" --profile plugins run --build --rm paper-plugin-smoke

echo "==> All local tests passed."
