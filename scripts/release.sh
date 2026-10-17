#!/bin/bash
# Release pipeline (updates.release.publish): version check, bump, build + notarize, sign the DMG for Sparkle,
# appcast, deploy, tag, release. Every step that publishes comes after every step that can fail locally, and a
# failure stops the script before any later publish step.
#
# Usage:
#   scripts/release.sh [version]          default: increment the last component of the current version
#   scripts/release.sh --print-version [version]   print the version that would be released and exit
#
# Names that are not decided yet are PLACEHOLDER values below. The script refuses to run while any remains.
# Set them in the environment or replace them here once the owner has decided.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Hosting, the same shape as Cutaway's: the appcast on a Cloudflare Pages project, the DMG on a GitHub release. ---
HOSTING_PROJECT="${HOSTING_PROJECT:-playaway-updates}"                # Cloudflare Pages project serving https://playaway-updates.pages.dev/appcast.xml
RELEASE_REPO="${RELEASE_REPO:-boxabirds/playaway}"                    # <owner>/<repo> that hosts release downloads
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-playaway}"               # Playaway's own EdDSA key in the keychain (generate_keys --account playaway), never Cutaway's
# ------------------------------------------------------------------------------------------------------------------

HOSTING_BRANCH="${HOSTING_BRANCH:-main}"
PLACEHOLDER_MARKER="PLACEHOLDER"
INFO_PLIST="${INFO_PLIST:-${ROOT}/Resources/Info.plist}"
APPCAST_TEMPLATE="${APPCAST_TEMPLATE:-${ROOT}/scripts/appcast-template.xml}"
CHECK_MIN_OS="${CHECK_MIN_OS:-${ROOT}/scripts/check-min-os.sh}"
BUILD_SCRIPT="${BUILD_SCRIPT:-${ROOT}/scripts/build-app.sh}"
SIGN_UPDATE="${SIGN_UPDATE:-${ROOT}/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/.build/release-app}"
APPCAST_DIR="${APPCAST_DIR:-${ROOT}/.build/appcast-site}"
VERSION_PATTERN='^[0-9]+(\.[0-9]+){0,2}$'
REJECTED_FOREIGN_KEY="rqIy/mx4aHQfqlexNM0vv6B+tHhHrCJy2sijyrmn450="

read -ra GIT <<< "${GIT_CMD:-git}"
read -ra GH <<< "${GH_CMD:-gh}"
read -ra WRANGLER <<< "${WRANGLER_CMD:-npx wrangler}"

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Version selection (pure; also reachable with --print-version) ---

validate_version() {
    [[ "$1" =~ $VERSION_PATTERN ]] || die "malformed version: '$1' (expected N, N.N or N.N.N)"
}

next_version() {
    local current="$1" parts last
    IFS='.' read -ra parts <<< "$current"
    last=$((${#parts[@]} - 1))
    if [[ ${#parts[@]} -eq 1 ]]; then
        echo "${current}.1"
    else
        parts[$last]=$((10#${parts[$last]} + 1))
        (IFS='.'; echo "${parts[*]}")
    fi
}

select_version() {
    local current="$1"; shift
    if [[ $# -ge 1 ]]; then
        validate_version "$1"
        echo "$1"
    else
        validate_version "$current"
        next_version "$current"
    fi
}

if [[ "${1:-}" == "--print-version" ]]; then
    shift
    current="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
    select_version "$current" "$@"
    exit 0
fi

# --- Step 1: minimum macOS version consistency, before anything else ---

echo "Checking minimum macOS version consistency..."
"$CHECK_MIN_OS" || die "minimum macOS version check failed; nothing was changed or published"

# --- Step 2: placeholders ---

placeholders=()
[[ "$HOSTING_PROJECT" == *"$PLACEHOLDER_MARKER"* ]] && placeholders+=("HOSTING_PROJECT")
[[ "$RELEASE_REPO" == *"$PLACEHOLDER_MARKER"* ]] && placeholders+=("RELEASE_REPO")
for key in SUFeedURL SUPublicEDKey; do
    value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$INFO_PLIST" 2>/dev/null || true)"
    if [[ -z "$value" || "$value" == *"$PLACEHOLDER_MARKER"* ]]; then placeholders+=("${key} in ${INFO_PLIST}"); fi
    if [[ "$value" == "$REJECTED_FOREIGN_KEY" ]]; then die "${key} holds another product's key; update keys must not be shared"; fi
done
if [[ ${#placeholders[@]} -gt 0 ]]; then
    echo "ERROR: placeholder values remain; refusing to release:" >&2
    printf '  - %s\n' "${placeholders[@]}" >&2
    exit 1
fi

# --- Step 2b: the recorded HIG review. An unmarked item, or a fail with no exception, refuses the release. ---

CHECK_HIG="${CHECK_HIG:-${ROOT}/scripts/check-hig.sh}"
echo "Checking the Human Interface Guidelines review..."
"$CHECK_HIG" || die "the HIG checklist is not fully marked; refusing to release (see docs/hig-checklist.md)"

# --- Step 3: version and preflight ---

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
PRODUCT_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST")"
NEW_VERSION="$(select_version "$CURRENT_VERSION" "$@")"
echo "Current version: ${CURRENT_VERSION}"
echo "New version: ${NEW_VERSION}"

for tool in "${GIT[0]}" "${GH[0]}" "${WRANGLER[0]}"; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done
[[ -x "$SIGN_UPDATE" ]] || die "Sparkle sign_update not found at ${SIGN_UPDATE}. Run: swift package resolve"
[[ -z "$("${GIT[@]}" -C "$ROOT" status --porcelain)" ]] || die "uncommitted changes: commit or stash before releasing"

# --- Step 4: bump the version (restored on any failure before the commit) ---

PLIST_BACKUP="$(mktemp)"
cp "$INFO_PLIST" "$PLIST_BACKUP"
committed=false
restore_plist() { if [[ "$committed" == false ]]; then cp "$PLIST_BACKUP" "$INFO_PLIST"; fi; rm -f "$PLIST_BACKUP"; }
trap restore_plist EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$INFO_PLIST"

# --- Step 5: build, sign and notarize ---

echo "Building and notarizing..."
export OUTPUT_DIR
"$BUILD_SCRIPT" --no-launch || die "build failed; nothing was published"
DMG_PATH="${OUTPUT_DIR}/${PRODUCT_NAME}-${NEW_VERSION}.dmg"
[[ -f "$DMG_PATH" ]] || die "expected DMG not found: ${DMG_PATH}"

# --- Step 6: sign the DMG for Sparkle ---

sign_args=()
[[ -n "${SPARKLE_KEY_FILE:-}" ]] && sign_args+=(--ed-key-file "$SPARKLE_KEY_FILE")
[[ -n "${SPARKLE_KEY_ACCOUNT:-}" ]] && sign_args+=(--account "$SPARKLE_KEY_ACCOUNT")
sign_output="$("$SIGN_UPDATE" ${sign_args[@]+"${sign_args[@]}"} "$DMG_PATH" 2>&1)" || { echo "$sign_output" >&2; die "sign_update failed; nothing was published"; }
ED_SIGNATURE="$(grep -o 'sparkle:edSignature="[^"]*"' <<< "$sign_output" | head -1 | sed 's/sparkle:edSignature="//; s/"$//' || true)"
SIGNED_LENGTH="$(grep -o 'length="[^"]*"' <<< "$sign_output" | head -1 | sed 's/length="//; s/"$//' || true)"
DMG_LENGTH="$(stat -f%z "$DMG_PATH")"
[[ -n "$ED_SIGNATURE" ]] || { echo "$sign_output" >&2; die "empty EdDSA signature; nothing was published"; }
if [[ -n "$SIGNED_LENGTH" && "$SIGNED_LENGTH" != "$DMG_LENGTH" ]]; then
    die "sign_update length ${SIGNED_LENGTH} differs from the DMG size ${DMG_LENGTH}; nothing was published"
fi

# --- Step 7: appcast ---

DOWNLOAD_URL="https://github.com/${RELEASE_REPO}/releases/download/v${NEW_VERSION}/${PRODUCT_NAME}-${NEW_VERSION}.dmg"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
appcast="$(cat "$APPCAST_TEMPLATE")"
appcast="${appcast//@PRODUCT_NAME@/$PRODUCT_NAME}"
appcast="${appcast//@VERSION@/$NEW_VERSION}"
appcast="${appcast//@PUB_DATE@/$PUB_DATE}"
appcast="${appcast//@DOWNLOAD_URL@/$DOWNLOAD_URL}"
appcast="${appcast//@LENGTH@/$DMG_LENGTH}"
appcast="${appcast//@ED_SIGNATURE@/$ED_SIGNATURE}"
mkdir -p "$APPCAST_DIR"
printf '%s\n' "$appcast" > "${APPCAST_DIR}/appcast.xml"
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "${APPCAST_DIR}/appcast.xml" || die "generated appcast is not valid XML"; fi
echo "Appcast written to ${APPCAST_DIR}/appcast.xml"

# --- Step 8: publish. Each step runs only if all earlier ones succeeded. ---

echo "Deploying appcast..."
"${WRANGLER[@]}" pages deploy "$APPCAST_DIR" --project-name "$HOSTING_PROJECT" --commit-dirty=true --branch "$HOSTING_BRANCH" \
    || die "appcast deploy failed; no tag was pushed and no release was created"

"${GIT[@]}" -C "$ROOT" add "$INFO_PLIST"
"${GIT[@]}" -C "$ROOT" commit -m "Bump version to ${NEW_VERSION}"
committed=true
"${GIT[@]}" -C "$ROOT" tag "v${NEW_VERSION}"
"${GIT[@]}" -C "$ROOT" push
"${GIT[@]}" -C "$ROOT" push --tags

echo "Creating release..."
"${GH[@]}" release create "v${NEW_VERSION}" "$DMG_PATH" --repo "$RELEASE_REPO" \
    --title "${PRODUCT_NAME} v${NEW_VERSION}" \
    --notes "${PRODUCT_NAME} ${NEW_VERSION}. Existing installs are offered this update by the app."

echo "Release v${NEW_VERSION} complete. DMG: ${DMG_PATH}"
