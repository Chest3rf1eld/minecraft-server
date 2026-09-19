#!/usr/bin/env bash
set -euo pipefail

HOST=${1:-127.0.0.1}
PORT=${2:-25565}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$SCRIPT_DIR/minecraft-status.py" "$HOST" "$PORT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("players", {}).get("online", 0))'
