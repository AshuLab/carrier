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
# the licences of FluidAudio (and of what it vendors), WhisperKit (with swift-transformers), libghostty-spm/DisplayLink and the repository's notices travel with the binary
L=Carrier.app/Contents/Resources/Licenses
for f in FluidAudio/LICENSE FluidAudio/ThirdPartyLicenses/NemoTextProcessing-LICENSE.md FluidAudio/ThirdPartyLicenses/fastcluster-LICENSE.md argmax-oss-swift/LICENSE argmax-oss-swift/NOTICES libghostty-spm/LICENSE DisplayLink/LICENSE THIRD-PARTY-NOTICES.md; do
  [ -s "$L/$f" ] || fail "$L/$f is not in the app"
done
[ -d Carrier.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle/Contents/Resources/terminfo ] || fail "GhosttyKit_GhosttyTerminal.bundle terminfo database is not in the app"
[ -d Carrier.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle/Contents/Resources/Ghostty ] || fail "GhosttyKit_GhosttyTerminal.bundle Ghostty resources are not in the app"
grep -q "Copyright (c) 2017 Ryan Caloras" Carrier.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle/Contents/Resources/Ghostty/shell-integration/bash/LICENSE-bash-preexec.md || fail "bash-preexec license missing from GhosttyKit_GhosttyTerminal.bundle"
grep -q "Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors" "$L/THIRD-PARTY-NOTICES.md" || fail "Ghostty copyright notice missing from $L/THIRD-PARTY-NOTICES.md"
grep -q "OUT OF OR IN CONNECTION WITH THE SOFTWARE" "$L/THIRD-PARTY-NOTICES.md" || fail "Ghostty MIT text missing from $L/THIRD-PARTY-NOTICES.md"
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
