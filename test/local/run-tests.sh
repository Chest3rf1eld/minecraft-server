#!/usr/bin/env bash
# Orchestrates the local test suite: see SPEC.md 12.5 for the design and
# test/local/README.md for how to run this. Runs each test/local/tests/
# test-*.sh script (each self-contained, resetting /srv/minecraft at its
# own start) and reports one pass/fail summary.
set -uo pipefail

# Fast by design (SPEC.md 12.5.1/12.5.7): a real Paper first boot easily
# takes 300s+ (see deploy.sh's own comments), which the tests have no
# reason to wait out against a stub that binds its port in milliseconds.
export DEPLOY_EMPTY_GRACE_SECONDS=${DEPLOY_EMPTY_GRACE_SECONDS:-1}
export VERIFY_PING_ATTEMPTS=${VERIFY_PING_ATTEMPTS:-10}

overall_status=0
for test_script in /opt/test/tests/test-*.sh; do
  echo
  echo "############################################"
  echo "# $(basename "$test_script")"
  echo "############################################"
  if ! bash "$test_script"; then
    overall_status=1
  fi
done

echo
if [[ "$overall_status" -eq 0 ]]; then
  echo "ALL TEST SCRIPTS PASSED"
else
  echo "ONE OR MORE TEST SCRIPTS FAILED"
fi
exit "$overall_status"
