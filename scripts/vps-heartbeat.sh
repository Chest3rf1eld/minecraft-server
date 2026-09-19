#!/usr/bin/env bash
set -euo pipefail

URL_FILE=${HEALTHCHECKS_VPS_URL_FILE:-/etc/minecraft/secrets/healthchecks_vps_url}

if [[ ! -r "$URL_FILE" ]]; then
  echo "Healthchecks VPS URL file is not readable" >&2
  exit 1
fi

# Strip stray whitespace (e.g. a leading space from a copy-paste into the
# GitHub secret) -- a URL should never legitimately contain any, and curl
# rejects one outright ("Malformed input to a URL function") otherwise.
curl -fsS "$(tr -d '[:space:]' <"$URL_FILE")" >/dev/null
