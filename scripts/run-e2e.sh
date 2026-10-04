#!/bin/bash
# Builds the ad-hoc signed dev bundle, then runs the end-to-end tests against it.
# The e2e tests drive the real app through open and osascript; macOS may ask once to allow Automation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUNDLE_NAME=LocalPlayerE2E BUNDLE_ID=com.localplayer.app.e2e "$ROOT/scripts/bundle-dev.sh" debug "$ROOT/.build/e2e-app" >/dev/null
swift test --filter E2ETests
