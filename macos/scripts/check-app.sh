#!/bin/bash
# Builds Carrier.app with build-app.sh and asserts what the updater needs from the bundle (the macOS app workflow runs it).
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Carrier.app/Contents/Info.plist
fail() { echo "check-app: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
expect() { [ "$2" = "$3" ] || fail "$1 is '$2', expected '$3'"; }

./build-app.sh 1.2.3
expect SUFeedURL "$(plist SUFeedURL)" "https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml"
expect SUPublicEDKey "$(plist SUPublicEDKey)" "$(cat update-key.pub)"
expect SUEnableAutomaticChecks "$(plist SUEnableAutomaticChecks)" true
expect CFBundleShortVersionString "$(plist CFBundleShortVersionString)" 1.2.3
expect "CFBundleVersion for 1.2.3" "$(plist CFBundleVersion)" 10203
[ -n "$(plutil -extract NSMicrophoneUsageDescription raw "$PLIST")" ] || fail "NSMicrophoneUsageDescription is missing or empty"
otool -l Carrier.app/Contents/MacOS/Carrier | grep -A2 LC_RPATH | grep -q "path @executable_path/../Frameworks " || fail "no rpath @executable_path/../Frameworks"
F=Carrier.app/Contents/Frameworks/Sparkle.framework
[ -f "$F/Versions/B/Sparkle" ] || fail "Sparkle.framework is not in the app"
[ -L "$F/Sparkle" ] && [ -L "$F/Versions/Current" ] || fail "Sparkle.framework lost its symlinks"
codesign --verify --deep --strict Carrier.app || fail "codesign --verify --deep --strict failed"

./build-app.sh 0.1.4 >/dev/null
expect "CFBundleVersion for 0.1.4" "$(plist CFBundleVersion)" 104

./build-app.sh >/dev/null
expect "CFBundleVersion for no version" "$(plist CFBundleVersion)" 1
expect "CFBundleShortVersionString for no version" "$(plist CFBundleShortVersionString)" 0.1.0

for v in 1.100.0 1.0.100; do
  if OUT="$(./build-app.sh "$v" 2>&1)"; then fail "build-app.sh accepted $v"; fi
  [[ "$OUT" == *"100 or more"* ]] || fail "build-app.sh refused $v for another reason: $OUT"
done
if OUT="$(CARRIER_MIC_USAGE= ./build-app.sh 2>&1)"; then fail "build-app.sh accepted an empty NSMicrophoneUsageDescription"; fi
[[ "$OUT" == *NSMicrophoneUsageDescription* ]] || fail "build-app.sh refused an empty microphone description for another reason: $OUT"
echo "check-app: ok"
