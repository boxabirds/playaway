#!/bin/bash
# Release build: universal binary, hand-assembled bundle, inside-out Developer ID signing with hardened runtime,
# notarization, stapling and a DMG (updates.build.package). Not the dev bundler: see scripts/bundle-dev.sh.
#
# Usage: scripts/build-app.sh [--skip-notarize] [--no-launch] [--test-entitlements]
#
# Configuration (environment):
#   NOTARY_PROFILE        keychain profile for notarytool (required unless --skip-notarize; no default on purpose)
#   SIGNING_IDENTITY      overrides the keychain lookup of a "Developer ID Application" identity
#   OUTPUT_DIR            where the .app and .dmg are written (default: .build/release-app)
#   BUILD_DIR             where `swift build` leaves the binary and Sparkle.framework (default: swift build --show-bin-path)
#   ENTITLEMENTS_FILE     entitlements to sign with (default: Resources/LocalPlayer.entitlements)
# Tool commands (each may be a shim in tests): SWIFT_CMD SECURITY_CMD CODESIGN_CMD DITTO_CMD HDIUTIL_CMD
#   NOTARYTOOL_CMD (default "xcrun notarytool") STAPLER_CMD (default "xcrun stapler") SPCTL_CMD
# Test-only: CODESIGN_TIMESTAMP_FLAG (default --timestamp), ALLOW_SINGLE_ARCH=1, STAPLE_RETRY_DELAY_SECONDS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY_NAME="LocalPlayer"
INFO_PLIST_SRC="${ROOT}/Resources/Info.plist"
ENTITLEMENTS="${ENTITLEMENTS_FILE:-${ROOT}/Resources/LocalPlayer.entitlements}"
BUILD_DIR="${BUILD_DIR:-}"   # default: asked of SwiftPM after the build (the path differs between SwiftPM backends)
BUILD_ARGS=(-c release --arch arm64 --arch x86_64)
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/.build/release-app}"
NOTARY_TIMEOUT="30m"
STAPLE_RETRY_DELAY_SECONDS="${STAPLE_RETRY_DELAY_SECONDS:-5}"
CODESIGN_TIMESTAMP_FLAG="${CODESIGN_TIMESTAMP_FLAG:---timestamp}"
FRAMEWORKS_RPATH="@executable_path/../Frameworks"
FORBIDDEN_ENTITLEMENT="com.apple.security.app-sandbox"
DEVELOPER_ID_PATTERN="Developer ID Application"

read -ra SWIFT <<< "${SWIFT_CMD:-swift}"
read -ra SECURITY <<< "${SECURITY_CMD:-security}"
read -ra CODESIGN <<< "${CODESIGN_CMD:-codesign}"
read -ra DITTO <<< "${DITTO_CMD:-ditto}"
read -ra HDIUTIL <<< "${HDIUTIL_CMD:-hdiutil}"
read -ra NOTARYTOOL <<< "${NOTARYTOOL_CMD:-xcrun notarytool}"
read -ra STAPLER <<< "${STAPLER_CMD:-xcrun stapler}"
read -ra SPCTL <<< "${SPCTL_CMD:-spctl}"

SKIP_NOTARIZE=false
SKIP_LAUNCH=false
TEST_ENTITLEMENTS=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize)     SKIP_NOTARIZE=true ;;
        --no-launch)         SKIP_LAUNCH=true ;;
        --test-entitlements) TEST_ENTITLEMENTS=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# The app is not sandboxed: Sparkle replaces the app in place. The sandbox key must never be present.
validate_entitlements() {
    local plist="$1"
    if [[ ! -f "$plist" ]]; then
        echo "ERROR: Entitlements file not found: $plist" >&2
        return 1
    fi
    if ! /usr/libexec/PlistBuddy -c "Print" "$plist" >/dev/null 2>&1; then
        echo "ERROR: Entitlements file is not a readable plist: $plist" >&2
        return 1
    fi
    if /usr/libexec/PlistBuddy -c "Print :${FORBIDDEN_ENTITLEMENT}" "$plist" >/dev/null 2>&1; then
        echo "ERROR: Forbidden entitlement present: ${FORBIDDEN_ENTITLEMENT}. The app must not be sandboxed." >&2
        return 1
    fi
    echo "Entitlements validated: no ${FORBIDDEN_ENTITLEMENT}"
}

if [[ "$TEST_ENTITLEMENTS" == true ]]; then
    validate_entitlements "$ENTITLEMENTS"
    exit $?
fi

# --- Preflight: everything that can fail cheaply fails before the build ---

validate_entitlements "$ENTITLEMENTS" || exit 1

SIGNING_IDENTITY="${SIGNING_IDENTITY:-$("${SECURITY[@]}" find-identity -v -p codesigning 2>/dev/null \
    | grep "$DEVELOPER_ID_PATTERN" | head -1 | awk -F'"' '{print $2}' || true)}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "ERROR: No \"${DEVELOPER_ID_PATTERN}\" identity found in the keychain. Nothing was built." >&2
    echo "       For a local, unsigned-for-distribution bundle use scripts/bundle-dev.sh." >&2
    exit 1
fi

if [[ "$SKIP_NOTARIZE" == false && -z "${NOTARY_PROFILE:-}" ]]; then
    echo "ERROR: NOTARY_PROFILE is not set (the notarytool keychain profile name). Use --skip-notarize to build without notarizing." >&2
    exit 1
fi

PRODUCT_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST_SRC")"
APP_BUNDLE="${OUTPUT_DIR}/${PRODUCT_NAME}.app"

# --- Build ---

echo "Building universal release binary (arm64 + x86_64)..."
(cd "$ROOT" && "${SWIFT[@]}" build "${BUILD_ARGS[@]}")
if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="$(cd "$ROOT" && "${SWIFT[@]}" build "${BUILD_ARGS[@]}" --show-bin-path)"
fi

[[ -f "${BUILD_DIR}/${BINARY_NAME}" ]] || { echo "ERROR: built binary not found: ${BUILD_DIR}/${BINARY_NAME}" >&2; exit 1; }
if [[ "${ALLOW_SINGLE_ARCH:-0}" != "1" ]]; then
    archs="$(lipo -archs "${BUILD_DIR}/${BINARY_NAME}")"
    if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
        echo "ERROR: binary is not universal (arm64 + x86_64), found: ${archs}" >&2
        exit 1
    fi
fi

# --- Assemble the bundle ---

echo "Bundling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources" "${APP_BUNDLE}/Contents/Frameworks"
cp "${BUILD_DIR}/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
cp "$INFO_PLIST_SRC" "${APP_BUNDLE}/Contents/Info.plist"
for resource in LocalPlayer.sdef ui-manifest.json; do
    if [[ -f "${ROOT}/Resources/${resource}" ]]; then cp "${ROOT}/Resources/${resource}" "${APP_BUNDLE}/Contents/Resources/${resource}"; fi
done
for spm_bundle in "${BUILD_DIR}"/*.bundle; do
    [[ -e "$spm_bundle" ]] || continue
    cp -R "$spm_bundle" "${APP_BUNDLE}/Contents/Resources/"
done

SPARKLE_FRAMEWORK="${BUILD_DIR}/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "ERROR: Sparkle.framework not found in build artifacts at ${SPARKLE_FRAMEWORK}" >&2
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
if ! otool -l "$EXECUTABLE" | grep -q "$FRAMEWORKS_RPATH"; then
    install_name_tool -add_rpath "$FRAMEWORKS_RPATH" "$EXECUTABLE"
fi

for key in SUFeedURL SUPublicEDKey; do
    value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true)"
    if [[ -z "$value" || "$value" == *PLACEHOLDER* ]]; then
        echo "WARNING: ${key} is missing or still a placeholder: this bundle cannot verify or find updates." >&2
    fi
done

# --- Scripting parity gate: every app-specific on-screen action must have a scripting equivalent (prd.script.parity_gate).
# Runs the built app itself against the bundled dictionary, so a gap stops the build before anything is signed.

echo "Checking scripting parity..."
# install_name_tool invalidated the binary's signature and macOS refuses to run it, so give it a throwaway ad-hoc
# one for the gate. The real Developer ID signing below uses --force and replaces it.
"${CODESIGN[@]}" --force --sign - "$EXECUTABLE" >/dev/null 2>&1 || true
if ! "$EXECUTABLE" --check-script-parity "${APP_BUNDLE}/Contents/Resources/LocalPlayer.sdef"; then
    echo "ERROR: scripting parity gate failed. Nothing was signed." >&2
    exit 1
fi

# --- Inside-out signing ---

sign() { "${CODESIGN[@]}" --force --options runtime "$CODESIGN_TIMESTAMP_FLAG" --sign "$SIGNING_IDENTITY" "$@"; }

echo "Signing with: ${SIGNING_IDENTITY}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"

# 1. every Mach-O file, deepest first
while IFS= read -r -d '' binary; do
    if [[ "$(file -b "$binary" 2>/dev/null || true)" == *"Mach-O"* ]]; then
        echo "  Signing: ${binary#"$FRAMEWORKS_DIR"/}"
        sign "$binary"
    fi
done < <(find "$FRAMEWORKS_DIR" -depth -type f -print0)
# 2. XPC services, 3. nested apps
for pattern in "*.xpc" "*.app"; do
    while IFS= read -r -d '' bundle; do
        echo "  Signing: ${bundle#"$FRAMEWORKS_DIR"/}"
        sign "$bundle"
    done < <(find "$FRAMEWORKS_DIR" -depth -name "$pattern" -type d -print0)
done
# 4. frameworks, 5. dylibs
for framework in "${FRAMEWORKS_DIR}"/*.framework; do
    [[ -e "$framework" ]] || continue
    echo "  Signing framework: $(basename "$framework")"
    sign "$framework"
done
for dylib in "${FRAMEWORKS_DIR}"/*.dylib; do
    [[ -e "$dylib" ]] || continue
    echo "  Signing dylib: $(basename "$dylib")"
    sign "$dylib"
done
# 6. the app itself, with entitlements
echo "  Signing app bundle..."
sign --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "  Verifying signature..."
"${CODESIGN[@]}" --verify --deep --strict "$APP_BUNDLE"
echo "Signature verified"

# --- Notarize and staple ---

staple_with_retry() {
    local target="$1"
    if ! "${STAPLER[@]}" staple "$target"; then
        echo "Staple failed, retrying once..."
        sleep "$STAPLE_RETRY_DELAY_SECONDS"
        if ! "${STAPLER[@]}" staple "$target"; then
            echo "ERROR: Stapling failed after retry. Manual fix: xcrun stapler staple \"${target}\"" >&2
            exit 1
        fi
    fi
}

# notarytool can exit 0 for a rejected submission, so success also needs "status: Accepted".
notarize() {
    local artifact="$1" output submission_id
    if ! output="$("${NOTARYTOOL[@]}" submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --timeout "$NOTARY_TIMEOUT" 2>&1)"; then
        echo "$output"
        notarization_failed "$output"
    fi
    echo "$output"
    if ! grep -q "status: Accepted" <<< "$output"; then
        notarization_failed "$output"
    fi
}

notarization_failed() {
    local submission_id
    submission_id="$(grep -m1 -E '^[[:space:]]*id:' <<< "$1" | awk '{print $2}' || true)"
    echo "ERROR: Notarization failed. Fetch the log with:" >&2
    echo "  xcrun notarytool log ${submission_id:-<submission-id>} --keychain-profile ${NOTARY_PROFILE}" >&2
    exit 1
}

if [[ "$SKIP_NOTARIZE" == true ]]; then
    echo "Skipping notarization (--skip-notarize)"
else
    ZIP_PATH="${OUTPUT_DIR}/${PRODUCT_NAME}.zip"
    "${DITTO[@]}" -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    echo "Submitting app for notarization..."
    notarize "$ZIP_PATH"
    rm -f "$ZIP_PATH"
    echo "Stapling notarization ticket..."
    staple_with_retry "$APP_BUNDLE"
fi

# --- DMG ---

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist")"
DMG_PATH="${OUTPUT_DIR}/${PRODUCT_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"
echo "Creating DMG: ${DMG_PATH}"
"${HDIUTIL[@]}" create -volname "$PRODUCT_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
"${CODESIGN[@]}" --force "$CODESIGN_TIMESTAMP_FLAG" --sign "$SIGNING_IDENTITY" "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == false ]]; then
    echo "Notarizing DMG..."
    notarize "$DMG_PATH"
    staple_with_retry "$DMG_PATH"

    echo "Verifying signatures..."
    "${CODESIGN[@]}" --verify --deep --strict "$APP_BUNDLE" || { echo "ERROR: app signature verification failed" >&2; exit 1; }
    "${SPCTL[@]}" --assess --type execute --verbose "$APP_BUNDLE" || { echo "ERROR: app failed Gatekeeper assessment" >&2; exit 1; }
    "${CODESIGN[@]}" --verify --verbose "$DMG_PATH" || { echo "ERROR: DMG signature verification failed" >&2; exit 1; }
    "${STAPLER[@]}" validate "$DMG_PATH" || { echo "ERROR: DMG staple validation failed" >&2; exit 1; }
    echo "All signatures verified"
fi

if [[ "$SKIP_LAUNCH" == false ]]; then
    echo "Launching ${PRODUCT_NAME}..."
    open "$APP_BUNDLE"
fi

echo "DMG: ${DMG_PATH}"
echo "Done."
