#!/usr/bin/env bash
# Local gate: project drift check, package tests, app UI test on a tvOS simulator.
# Full logs go to build/gate/ (gitignored). Run from any directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$ROOT/build/gate"
mkdir -p "$LOGS"
cd "$ROOT"

PACKAGES=()
for manifest in Packages/*/Package.swift; do
  [ -e "$manifest" ] || continue
  PACKAGES+=("$(basename "$(dirname "$manifest")")")
done
FAILED=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1  (log: ${2:-n/a})"; [ -n "${2:-}" ] && tail -n 15 "$2" | sed 's/^/      /'; FAILED=1; }

# Simulator: the 3rd-generation test simulator, by id. Never the other Apple TV simulator: it holds the
# live Plex sign-in, and UI tests wipe it.
SIM_ID="11ACEAE4-F474-4F94-842C-E8A000C4D417"
if ! xcrun simctl list devices available | grep -q "$SIM_ID"; then
  echo "FAIL  test simulator $SIM_ID is not available"
  exit 1
fi
DEST="platform=tvOS Simulator,id=$SIM_ID"
echo "Simulator: $SIM_ID"

# Step 1: generated project must match what is on disk.
BEFORE="$(mktemp -d)"
trap 'rm -rf "$BEFORE"' EXIT
if [ -d Perch.xcodeproj ]; then cp -R Perch.xcodeproj "$BEFORE/Perch.xcodeproj"; fi
if [ -f PerchApp/Info.plist ]; then cp PerchApp/Info.plist "$BEFORE/Info.plist"; fi
if xcodegen generate >"$LOGS/xcodegen.log" 2>&1; then
  if [ -d "$BEFORE/Perch.xcodeproj" ] && [ -f "$BEFORE/Info.plist" ] \
    && diff -r "$BEFORE/Perch.xcodeproj" Perch.xcodeproj >"$LOGS/drift.log" 2>&1 \
    && diff "$BEFORE/Info.plist" PerchApp/Info.plist >>"$LOGS/drift.log" 2>&1; then
    pass "xcodegen: Perch.xcodeproj and PerchApp/Info.plist match project.yml"
  else
    # Restore the pre-generate copies so a second run fails too.
    if [ -d "$BEFORE/Perch.xcodeproj" ]; then rm -rf Perch.xcodeproj; cp -R "$BEFORE/Perch.xcodeproj" Perch.xcodeproj; fi
    if [ -f "$BEFORE/Info.plist" ]; then cp "$BEFORE/Info.plist" PerchApp/Info.plist; fi
    fail "xcodegen: Perch.xcodeproj or PerchApp/Info.plist differ from generated output (restored; run xcodegen generate and commit)" "$LOGS/drift.log"
  fi
else
  fail "xcodegen generate" "$LOGS/xcodegen.log"
fi

# Step 2: package tests.
for pkg in "${PACKAGES[@]}"; do
  log="$LOGS/$pkg.log"
  if (cd "Packages/$pkg" && xcodebuild test -scheme "$pkg" -destination "$DEST" CODE_SIGNING_ALLOWED=NO) >"$log" 2>&1; then
    pass "package tests: $pkg"
  else
    fail "package tests: $pkg" "$log"
  fi
done

# Step 3: app scheme (UI tests). Built signed (team 3TWLQK4535, as project.yml): an unsigned build has no
# Keychain access group (-34018), so the WP-05 UI tests could not sign in and would skip.
log="$LOGS/PerchApp.log"
if xcodebuild test -project Perch.xcodeproj -scheme PerchApp -destination "$DEST" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=3TWLQK4535 >"$log" 2>&1; then
  if grep -qiE "Test case .* skipped" "$log"; then
    fail "app UI tests: PerchApp ran but skipped tests (signing?)" "$log"
  else
    pass "app UI tests: PerchApp"
  fi
else
  fail "app UI tests: PerchApp" "$log"
fi

if [ "$FAILED" -eq 0 ]; then echo "GATE PASS"; else echo "GATE FAIL"; exit 1; fi
