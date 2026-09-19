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

list_plugin_keys() {
  python3 - "$VERSION_FILE" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for key in (data.get("plugins") or {}):
    print(key)
PY
}

download_plugins() {
  local key required download_url version jar_name
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    required=$(read_yaml_value_optional "plugins.${key}.required")
    download_url=$(read_yaml_value_optional "plugins.${key}.download_url")
    version=$(read_yaml_value_optional "plugins.${key}.version")
    if [[ -z "$download_url" ]]; then
      if [[ "$required" == "True" || "$required" == "true" ]]; then
        fail "no download_url configured for required plugin: $key"
      fi
      log "no download_url configured for optional plugin $key; skipping"
      continue
    fi
    jar_name="${key}-${version}.jar"
    log "downloading plugin $key ($version)"
    curl -fsSL "$download_url" -o "$RELEASE_DIR/plugins/$jar_name"
  done < <(list_plugin_keys)
}

# World data, whitelist/ban/op lists, and plugin data directories (AuthMe accounts,
# CoreProtect logs, etc.) must survive across releases even though each release gets
# a fresh directory. Persist them under MINECRAFT_SHARED_DIR and symlink them into
# the release so Paper and its plugins read/write the same files every deployment.
link_shared_state() {
  local world state_file key data_dir

  mkdir -p "$MINECRAFT_SHARED_DIR/plugins"

  for world in world world_nether world_the_end; do
    mkdir -p "$MINECRAFT_SHARED_DIR/$world"
    ln -sfnT "$MINECRAFT_SHARED_DIR/$world" "$RELEASE_DIR/$world"
  done

  for state_file in whitelist.json banned-players.json banned-ips.json ops.json; do
    [[ -f "$MINECRAFT_SHARED_DIR/$state_file" ]] || printf '[]' >"$MINECRAFT_SHARED_DIR/$state_file"
    ln -sfnT "$MINECRAFT_SHARED_DIR/$state_file" "$RELEASE_DIR/$state_file"
  done

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    data_dir=$(read_yaml_value_optional "plugins.${key}.data_dir")
    [[ -n "$data_dir" ]] || continue
    mkdir -p "$MINECRAFT_SHARED_DIR/plugins/$data_dir"
    ln -sfnT "$MINECRAFT_SHARED_DIR/plugins/$data_dir" "$RELEASE_DIR/plugins/$data_dir"
  done < <(list_plugin_keys)

  chown -R minecraft:minecraft "$MINECRAFT_SHARED_DIR"
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
  download_plugins
  cp -a minecraft/server.properties "$RELEASE_DIR/server.properties"
  # Paper refuses to start at all without this; operating this server at
  # all is an implicit acceptance of the Minecraft EULA already.
  printf 'eula=true\n' >"$RELEASE_DIR/eula.txt"
  if [[ -r /etc/minecraft/secrets/rcon_password ]]; then
    sed -i "s/^rcon.password=.*/rcon.password=$(cat /etc/minecraft/secrets/rcon_password)/" "$RELEASE_DIR/server.properties"
  fi
  cp -a minecraft/paper "$RELEASE_DIR/paper"
  link_shared_state
  chown -R minecraft:minecraft "$RELEASE_DIR"
  printf '%s\n' "$RELEASE_ID" >"$MINECRAFT_STATE_DIR/target-release"
  log "prepared release $RELEASE_ID"
}

with_global_lock prepare
