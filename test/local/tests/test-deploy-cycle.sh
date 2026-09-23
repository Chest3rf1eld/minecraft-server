#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/harness.sh"

test_first_deploy_succeeds() {
  reset_environment
  prepare_release "rel1" || return 1
  assert_contains "$(cat /srv/minecraft/releases/rel1/server.properties)" \
    "rcon.password=test-rcon-password" "(rendered from repository template)" || return 1
  assert_file_exists /srv/minecraft/releases/rel1/config/paper-global.yml || return 1
  assert_file_exists /srv/minecraft/shared/plugins/AuthMe/config.yml || return 1
  assert_file_exists /srv/minecraft/shared/plugins/Chunky/config.yml || return 1
  assert_file_exists /srv/minecraft/shared/plugins/CoreProtect/config.yml || return 1
  assert_file_exists /srv/minecraft/shared/plugins/DynamicLights/config.yml || return 1
  assert_contains "$(cat /srv/minecraft/shared/plugins/AuthMe/config.yml)" \
    "mySQLPassword: 'test-authme-mysql-password'" "(rendered plugin secret)" || return 1
  if grep -R -q '{{[A-Z][A-Z0-9_]*}}' /srv/minecraft/releases/rel1/config /srv/minecraft/shared/plugins; then
    echo "  ASSERT FAILED: unreplaced template marker in runtime configs" >&2
    return 1
  fi
  if grep -q '{{[A-Z][A-Z0-9_]*}}' /srv/minecraft/releases/rel1/server.properties; then
    echo "  ASSERT FAILED: unreplaced template marker in runtime server.properties" >&2
    return 1
  fi
  /opt/minecraft/bin/deploy.sh || return 1
  assert_eq "SUCCESS" "$(cat /srv/minecraft/state/deploy-state)" "(deploy-state)" || return 1
  assert_eq "rel1" "$(cat /srv/minecraft/state/current-release)" "(current-release)" || return 1
  assert_eq "rel1" "$(readlink -f /srv/minecraft/current | xargs basename)" "(current symlink target)" || return 1
  assert_file_exists /srv/minecraft/shared/whitelist.json || return 1
  systemctl is-active --quiet minecraft.service || {
    echo "  ASSERT FAILED: expected minecraft.service to be active after a successful deploy" >&2
    return 1
  }
}

test_repeat_deploy_is_noop() {
  # Assumes test_first_deploy_succeeds already ran and left rel1 deployed;
  # run_test calls each function independently, so re-derive that state.
  reset_environment
  prepare_release "rel1" || return 1
  /opt/minecraft/bin/deploy.sh || return 1
  local before after
  before=$(cat /srv/minecraft/state/last-backup-success 2>/dev/null || echo missing)
  # A second run with the same target must not re-run backup/restart the
  # service -- that's the exact bug fixed for the retention work (the
  # timer fires this every minute forever otherwise).
  /opt/minecraft/bin/deploy.sh || return 1
  after=$(cat /srv/minecraft/state/last-backup-success 2>/dev/null || echo missing)
  assert_eq "$before" "$after" "(backup marker must be untouched on a no-op deploy)" || return 1
}

test_second_release_prunes_and_updates_previous() {
  reset_environment
  prepare_release "rel1" || return 1
  /opt/minecraft/bin/deploy.sh || return 1
  prepare_release "rel2" || return 1
  DEPLOY_EMPTY_GRACE_SECONDS=1 /opt/minecraft/bin/deploy.sh || return 1
  assert_eq "rel2" "$(cat /srv/minecraft/state/current-release)" "(current-release after 2nd deploy)" || return 1
  assert_eq "rel1" "$(cat /srv/minecraft/state/previous-release)" "(previous-release after 2nd deploy)" || return 1
}

reset_environment
run_test "first deploy reaches SUCCESS with the stub server" test_first_deploy_succeeds
run_test "repeat deploy of the same release is a no-op" test_repeat_deploy_is_noop
run_test "second release becomes current, first becomes previous" test_second_release_prunes_and_updates_previous
report_and_exit
