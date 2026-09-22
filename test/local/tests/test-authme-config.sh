#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/harness.sh"

# Exercises scripts/ensure-authme-config.sh directly rather than through a
# full deploy.sh cycle: deploy.sh's own pre-deploy backup writes a real
# restic snapshot into the minio instance shared by every test script in
# this run (reset_environment only clears /srv/minecraft, not that
# external repository), and test-backup-restore.sh's snapshot-count
# assertions are sensitive to how many same-day snapshots already exist
# when it runs. This script only needs to prove the self-heal logic
# itself; deploy.sh's one-line call into it is covered by code review, the
# same as ensure-dynamiclights-config.sh's equivalent wiring.
AUTHME_CONFIG=/srv/minecraft/shared/plugins/AuthMe/config.yml

write_stock_authme_config() {
  mkdir -p "$(dirname "$AUTHME_CONFIG")"
  cat >"$AUTHME_CONFIG" <<'EOF'
settings:
    restrictions:
        allowedNicknameCharacters: '[a-zA-Z0-9_]*'
        timeout: 30
        maxRegPerIp: 1
        forceSurvivalMode: false
    sessions:
        enabled: false
        timeout: 10
DataSource:
    backend: SQLITE
EOF
}

test_heals_stock_config() {
  reset_environment
  # Simulates AuthMe having already generated its own config once (e.g. a
  # plugin reinstall/update regenerated stock defaults).
  write_stock_authme_config
  /opt/minecraft/bin/ensure-authme-config.sh || return 1

  assert_contains "$(grep -A3 'restrictions:' "$AUTHME_CONFIG")" "timeout: 60" \
    "(settings.restrictions.timeout must be healed to 60)" || return 1
  assert_contains "$(grep -A3 'restrictions:' "$AUTHME_CONFIG")" "maxRegPerIp: 0" \
    "(settings.restrictions.maxRegPerIp must be healed to 0)" || return 1
  # The unrelated settings.sessions.timeout shares the same leaf key name
  # and must be left untouched.
  assert_contains "$(grep -A2 'sessions:' "$AUTHME_CONFIG")" "timeout: 10" \
    "(settings.sessions.timeout must NOT be touched)" || return 1
}

test_re_heals_after_drift() {
  reset_environment
  write_stock_authme_config
  /opt/minecraft/bin/ensure-authme-config.sh || return 1

  # A plugin update/reinstall on the VPS can regenerate stock defaults at
  # any time, not just at deploy -- the next unconditional deploy-timer
  # tick (a no-op deploy, no new release pending) must still re-heal it.
  sed -i 's/timeout: 60/timeout: 30/; s/maxRegPerIp: 0/maxRegPerIp: 1/' "$AUTHME_CONFIG"
  /opt/minecraft/bin/ensure-authme-config.sh || return 1

  assert_contains "$(grep -A3 'restrictions:' "$AUTHME_CONFIG")" "timeout: 60" \
    "(drifted settings.restrictions.timeout must be re-healed)" || return 1
  assert_contains "$(grep -A3 'restrictions:' "$AUTHME_CONFIG")" "maxRegPerIp: 0" \
    "(drifted settings.restrictions.maxRegPerIp must be re-healed)" || return 1
}

test_missing_config_is_a_noop() {
  reset_environment
  # AuthMe hasn't started yet (first-ever deploy): there's nothing to heal
  # and this must not fail the deploy tick that calls it.
  /opt/minecraft/bin/ensure-authme-config.sh || return 1
  if [[ -f "$AUTHME_CONFIG" ]]; then
    echo "  ASSERT FAILED: config should not have been created" >&2
    return 1
  fi
}

reset_environment
run_test "heals a stock AuthMe config to the tuned timeout/IP-limit values" test_heals_stock_config
run_test "AuthMe config heal re-applies if it drifts back to defaults" test_re_heals_after_drift
run_test "missing AuthMe config (plugin never started) is a no-op, not a failure" test_missing_config_is_a_noop
report_and_exit
