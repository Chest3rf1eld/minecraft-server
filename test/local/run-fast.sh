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

if (($# > 0)); then
  docker compose "${compose_args[@]}" run --build --rm test-runner "$@"
else
  docker compose "${compose_args[@]}" up --build --abort-on-container-exit
fi
