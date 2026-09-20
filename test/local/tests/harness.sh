#!/usr/bin/env bash
# Shared setup/assertions for test/local/tests/*.sh. Sourced, not executed.
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0

# Resets /srv/minecraft to what a freshly provisioned VPS looks like before
# any release exists: state/ and releases/ empty, current/ a REAL directory
# (not a symlink) with a rendered server.properties in it -- exactly what
# Ansible's minecraft role creates, and what switch_current()'s first-ever
# call has to replace. Called at the start of every test script so each one
# is isolated from whatever a previous test left behind, even though
# /srv/minecraft is tmpfs for the whole container run.
reset_environment() {
  rm -rf /srv/minecraft
  mkdir -p /srv/minecraft/state /srv/minecraft/releases /srv/minecraft/shared /srv/minecraft/current
  printf 'motd=fixture\n' >/srv/minecraft/current/server.properties
  rm -f /tmp/minecraft-stub.pid /tmp/minecraft-stub.log
}

# Runs prepare-release.sh for real (curl is shimmed, so the paper.jar/plugin
# "downloads" are just placeholder files) from the fixture repo checkout,
# producing a genuine release directory -- the same function every test
# scenario needs, so it lives here rather than being copy-pasted.
prepare_release() {
  local release_id=$1
  (cd /opt/test/repo && /opt/minecraft/bin/prepare-release.sh "$release_id")
}

assert_eq() {
  local expected=$1 actual=$2 message=${3:-}
  if [[ "$expected" != "$actual" ]]; then
    echo "  ASSERT FAILED: expected '${expected}', got '${actual}' ${message}" >&2
    return 1
  fi
}

assert_file_exists() {
  local path=$1
  if [[ ! -e "$path" ]]; then
    echo "  ASSERT FAILED: expected '${path}' to exist" >&2
    return 1
  fi
}

assert_contains() {
  local haystack=$1 needle=$2
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT FAILED: expected output to contain '${needle}', got: ${haystack}" >&2
    return 1
  fi
}

run_test() {
  local name=$1
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "=== ${name} ==="
  if "$@"; then
    echo "--- PASS: ${name}"
  else
    echo "--- FAIL: ${name}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

report_and_exit() {
  echo
  echo "Ran ${TESTS_RUN} test(s), ${TESTS_FAILED} failed."
  [[ "$TESTS_FAILED" -eq 0 ]]
}
