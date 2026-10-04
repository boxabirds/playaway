#!/bin/bash
# Validates docs/hig-checklist.md: every item must be pass, or fail with a recorded exception.
# Compiles Sources/LocalPlayer/UI/HIGChecklist.swift (Foundation only) with a one-line driver, so the check needs
# neither the app bundle nor Sparkle. Exit status is non-zero while any item is unmarked or a fail has no exception.
#
# Usage: scripts/check-hig.sh [path-to-checklist]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKLIST="${1:-${HIG_CHECKLIST:-${ROOT}/docs/hig-checklist.md}}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src"
cp "${ROOT}/Sources/LocalPlayer/UI/HIGChecklist.swift" "$WORK/src/HIGChecklist.swift"
printf 'import Foundation\nexit(runHIGChecklistCheck(path: CommandLine.arguments[1]))\n' > "$WORK/src/main.swift"
xcrun swiftc -swift-version 5 -o "$WORK/hig-check" "$WORK/src/HIGChecklist.swift" "$WORK/src/main.swift"
"$WORK/hig-check" "$CHECKLIST"
