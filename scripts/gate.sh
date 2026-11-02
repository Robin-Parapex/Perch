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

# Simulator: prefer the 3rd generation by name, else the first available Apple TV 4K.
DEVICES="$(xcrun simctl list devices available)"
SIM_NAME="Apple TV 4K (3rd generation)"
if ! grep -q "^ *$SIM_NAME (" <<<"$DEVICES"; then
  SIM_NAME="$(grep -E '^ *Apple TV 4K' <<<"$DEVICES" | head -n 1 | sed -E 's/^ *//; s/ \([0-9A-F-]{36}\).*$//' || true)"
fi
if [ -z "$SIM_NAME" ]; then
  echo "FAIL  no Apple TV 4K simulator available"
  exit 1
fi
DEST="platform=tvOS Simulator,name=$SIM_NAME"
echo "Simulator: $SIM_NAME"

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

# Step 3: app scheme (UI test).
log="$LOGS/PerchApp.log"
if xcodebuild test -project Perch.xcodeproj -scheme PerchApp -destination "$DEST" CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
  pass "app UI tests: PerchApp"
else
  fail "app UI tests: PerchApp" "$log"
fi

if [ "$FAILED" -eq 0 ]; then echo "GATE PASS"; else echo "GATE FAIL"; exit 1; fi
