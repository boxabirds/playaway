#!/bin/bash
# The check that must pass before any build goes to TestFlight: every core test, then the whole iPhone UI suite in the
# simulator. It stops at the first failure and says so; nothing is uploaded by this script.
set -u
cd "$(dirname "$0")/.."
echo "== core tests =="
swift test 2>&1 | tee /tmp/gate-core.txt | grep -E "error:|Executed [0-9]+ tests" | tail -5
if grep -qE "Executed [0-9]+ tests?, .*[^0-9][1-9][0-9]* failures?" /tmp/gate-core.txt || ! grep -qE "Executed [0-9]+ tests" /tmp/gate-core.txt; then echo "GATE FAILED: core tests"; exit 1; fi
echo "== iPhone UI tests (whole suite) =="
scripts/ios-ui-tests.sh > /tmp/gate-ui.txt 2>&1
grep -E "error:|Test Case.*failed|\*\* TEST" /tmp/gate-ui.txt | cut -c1-300
passed=$(grep -cE "Test Case.*passed" /tmp/gate-ui.txt)
if grep -qE "\*\* TEST FAILED|Test Case.*failed" /tmp/gate-ui.txt || [ "$passed" -eq 0 ]; then echo "GATE FAILED: UI tests ($passed passed)"; exit 1; fi
echo "GATE PASSED: core suite and $passed UI tests"
