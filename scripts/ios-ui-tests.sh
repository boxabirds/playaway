#!/bin/bash
# Runs the Playaway iPhone UI tests on the simulator (headless) and fails if the app itself crashed.
# Crash reports for other processes (Apple's own simulator apps) are counted and reported, not failed on.
set -u
cd "$(dirname "$0")/../ios" || exit 2
DEVICE="${PLAYAWAY_SIM_DEVICE:-iPhone 17}"
DERIVED="${PLAYAWAY_DERIVED:-/tmp/playaway-ios-dd.noindex}"
LOG="$(mktemp -t playaway-ui-tests)"
REPORTS="$HOME/Library/Logs/DiagnosticReports"
START="$(mktemp -t playaway-start)"
xcodegen generate >/dev/null || exit 2
timeout 540 xcodebuild test -scheme Playaway -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" "$@" >"$LOG" 2>&1 </dev/null
STATUS=$?
grep -E ' error:|Test Case.*(passed|failed)|TEST (SUCCEEDED|FAILED)' "$LOG" | sort -u
APP_CRASHES=$(find "$REPORTS" -name '*.ips' -newer "$START" 2>/dev/null | xargs -I{} sh -c 'grep -l -E "\"procName\" *: *\"(Playaway|PlayawayUITests-Runner)\"" "{}"' 2>/dev/null)
OTHER=$(find "$REPORTS" -name '*.ips' -newer "$START" 2>/dev/null | wc -l | tr -d ' ')
if [ -n "$APP_CRASHES" ]; then echo "APP CRASHED:"; echo "$APP_CRASHES"; STATUS=1; fi
echo "other crash reports during the run (simulator system processes): $OTHER"
echo "log: $LOG"
exit $STATUS
