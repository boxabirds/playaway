#!/bin/bash
# Assembles a local, ad-hoc signed LocalPlayer.app from the SwiftPM build, for development and end-to-end tests.
# This is NOT the release pipeline: no Developer ID signing and no notarization (see scripts/build-app.sh).
#
# Usage: scripts/bundle-dev.sh [debug|release] [output-dir]
# Environment: BUNDLE_NAME and BUNDLE_ID give the bundle another name and identifier (the e2e suite uses this so it
# never shares a process name, defaults or saved windows with a copy the person is actually using).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
OUT_DIR="${2:-${ROOT}/.build/dev-app}"
NAME="${BUNDLE_NAME:-LocalPlayer}"
APP="${OUT_DIR}/${NAME}.app"
FRAMEWORKS_RPATH="@executable_path/../Frameworks"

cd "$ROOT"
swift build -c "$CONFIG" >&2
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/LocalPlayer" "$APP/Contents/MacOS/${NAME}"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${BUNDLE_NAME:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${NAME}" -c "Set :CFBundleName ${NAME}" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUNDLE_ID:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$APP/Contents/Info.plist"
fi
for resource in LocalPlayer.sdef ui-manifest.json; do
    [[ -f "$ROOT/Resources/$resource" ]] && cp "$ROOT/Resources/$resource" "$APP/Contents/Resources/$resource"
done
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/${NAME}" | grep -q "$FRAMEWORKS_RPATH"; then
    install_name_tool -add_rpath "$FRAMEWORKS_RPATH" "$APP/Contents/MacOS/${NAME}"
fi
codesign --force --deep --sign - "$APP" >&2
echo "$APP"
