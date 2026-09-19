#!/usr/bin/env bash
set -euo pipefail

URL_FILE=${HEALTHCHECKS_VPS_URL_FILE:-/etc/minecraft/secrets/healthchecks_vps_url}

if [[ ! -r "$URL_FILE" ]]; then
  echo "Healthchecks VPS URL file is not readable" >&2
  exit 1
fi

curl -fsS "$(<"$URL_FILE")" >/dev/null
