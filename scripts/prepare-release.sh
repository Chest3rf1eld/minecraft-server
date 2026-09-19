#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

RELEASE_ID=${1:-$(date -u +%Y%m%dT%H%M%SZ)}
VERSION_FILE=${VERSION_FILE:-$PWD/minecraft/versions.yml}
RELEASE_DIR="$MINECRAFT_ROOT/releases/$RELEASE_ID"

read_yaml_value() {
  local expr=$1
  python3 - "$VERSION_FILE" "$expr" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
value = data
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

read_yaml_value_optional() {
  local expr=$1
  python3 - "$VERSION_FILE" "$expr" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
value = data
try:
    for part in sys.argv[2].split("."):
        value = value[part]
except (KeyError, TypeError):
    value = ""
print(value)
PY
}

prepare() {
  local minecraft_version paper_build paper_url
  minecraft_version=$(read_yaml_value minecraft.version)
  paper_build=$(read_yaml_value paper.build)
  paper_url=$(read_yaml_value_optional paper.download_url)
  mkdir -p "$RELEASE_DIR/plugins" "$RELEASE_DIR/logs"
  if [[ -n "$paper_url" ]]; then
    curl -fsSL "$paper_url" -o "$RELEASE_DIR/paper.jar"
  else
    curl -fsSL \
      "https://api.papermc.io/v2/projects/paper/versions/${minecraft_version}/builds/${paper_build}/downloads/paper-${minecraft_version}-${paper_build}.jar" \
      -o "$RELEASE_DIR/paper.jar"
  fi
  cp -a minecraft/server.properties "$RELEASE_DIR/server.properties"
  if [[ -r /etc/minecraft/secrets/rcon_password ]]; then
    sed -i "s/^rcon.password=.*/rcon.password=$(cat /etc/minecraft/secrets/rcon_password)/" "$RELEASE_DIR/server.properties"
  fi
  cp -a minecraft/paper "$RELEASE_DIR/paper"
  chown -R minecraft:minecraft "$RELEASE_DIR"
  printf '%s\n' "$RELEASE_ID" >"$MINECRAFT_STATE_DIR/target-release"
  log "prepared release $RELEASE_ID"
}

with_global_lock prepare
