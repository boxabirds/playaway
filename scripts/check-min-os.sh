#!/bin/bash
# The single minimum-macOS-version validator for this repository (updates.version.consistency).
# Compares the appcast template's sparkle:minimumSystemVersion, Info.plist LSMinimumSystemVersion and the
# platform in Package.swift against the one supported floor. "26" and "26.0" are equal.
# Exit 0 when all three agree; otherwise exit 1 naming every disagreeing or unreadable source.
#
# Usage: scripts/check-min-os.sh
# Test overrides: APPCAST_TEMPLATE, INFO_PLIST, PACKAGE_SWIFT (paths to the three sources).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST_TEMPLATE="${APPCAST_TEMPLATE:-${ROOT}/scripts/appcast-template.xml}"
INFO_PLIST="${INFO_PLIST:-${ROOT}/Resources/Info.plist}"
PACKAGE_SWIFT="${PACKAGE_SWIFT:-${ROOT}/Package.swift}"
FLOOR="26.0"

# 26.0 -> 26, 26.0.0 -> 26, 15.4 -> 15.4
normalize() {
    local v="$1"
    while [[ "$v" == *.0 ]]; do v="${v%.0}"; done
    echo "$v"
}

read_appcast() {
    [[ -f "$1" ]] || return 1
    sed -n 's|.*<sparkle:minimumSystemVersion>\([^<]*\)</sparkle:minimumSystemVersion>.*|\1|p' "$1" | head -1 | tr -d '[:space:]'
}

read_plist() {
    [[ -f "$1" ]] || return 1
    /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$1" 2>/dev/null
}

# .macOS(.v26) -> 26, .macOS(.v10_15) -> 10.15, .macOS("26.0") -> 26.0
read_package() {
    [[ -f "$1" ]] || return 1
    local line
    line="$(grep -o '\.macOS([^)]*)' "$1" | head -1)"
    [[ -n "$line" ]] || return 1
    if [[ "$line" =~ \.macOS\(\.v([0-9_]+)\) ]]; then
        echo "${BASH_REMATCH[1]//_/.}"
    elif [[ "$line" =~ \.macOS\(\"([0-9.]+)\"\) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

failures=0
check() {
    local label="$1" file="$2" reader="$3" value
    if ! value="$("$reader" "$file")" || [[ -z "$value" ]]; then
        echo "FAIL ${label}: minimum system version missing or unreadable in ${file}"
        failures=$((failures + 1))
        return
    fi
    if [[ "$(normalize "$value")" != "$(normalize "$FLOOR")" ]]; then
        echo "FAIL ${label}: ${file} says ${value}, expected ${FLOOR}"
        failures=$((failures + 1))
    else
        echo "ok   ${label}: ${value}"
    fi
}

check "appcast" "$APPCAST_TEMPLATE" read_appcast
check "Info.plist" "$INFO_PLIST" read_plist
check "Package.swift" "$PACKAGE_SWIFT" read_package

if [[ "$failures" -gt 0 ]]; then
    echo "Minimum macOS version check failed: ${failures} source(s) disagree with ${FLOOR}"
    exit 1
fi
echo "Minimum macOS version consistent: ${FLOOR}"
