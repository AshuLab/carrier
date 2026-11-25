#!/bin/bash
# Builds Carrier.app with build-app.sh and asserts what the updater needs from the bundle (CI runs it on a PR that touches the packaging, and the release workflow before it publishes).
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Carrier.app/Contents/Info.plist
fail() { echo "check-app: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
expect() { [ "$2" = "$3" ] || fail "$1 is '$2', expected '$3'"; }
# the copy catalog is compiled into one folder per language (the bundle nests Contents/Resources with Swift 6.4 and not with 6.3, hence find)
expect_lprojs() {
  for lproj in en.lproj es.lproj; do
    [ -n "$(find Carrier.app/Contents/Resources/Carrier_CarrierCore.bundle -type d -name "$lproj" | head -n 1)" ] || fail "$1: Carrier_CarrierCore.bundle has no $lproj"
  done
}

# CARRIER_ARCH=x86_64 checks the Intel app: its binary and its own feed; no CARRIER_ARCH is the Apple Silicon app, whose binary is arm64 only
case "${CARRIER_ARCH:-}" in
  x86_64) FEED=appcast-intel.xml ;;
  *) FEED=appcast.xml ;;
esac

./build-app.sh 1.2.3
# the one compile: the builds below only change the plist, so they bundle this binary
export CARRIER_REUSE_BUILD=1
expect SUFeedURL "$(plist SUFeedURL)" "https://github.com/AshuLab/carrier/releases/latest/download/$FEED"
expect "architecture of the binary" "$(lipo -archs Carrier.app/Contents/MacOS/Carrier)" "${CARRIER_ARCH:-arm64}"
expect SUPublicEDKey "$(plist SUPublicEDKey)" "$(cat update-key.pub)"
expect SUEnableAutomaticChecks "$(plist SUEnableAutomaticChecks)" true
expect SUScheduledCheckInterval "$(plist SUScheduledCheckInterval)" 3600
expect CFBundleShortVersionString "$(plist CFBundleShortVersionString)" 1.2.3
expect "bundle id of a release" "$(plist CFBundleIdentifier)" dev.ashulab.carrier
expect "channel of a release" "$(plist CarrierChannel)" release
# the compiled icons are committed, so each must come from the .icon as it is now (scripts/make-icon.sh writes them)
for name in AppIcon AppIconDev; do
  expect "compiled $name is of its .icon (run scripts/make-icon.sh)" "$(cat "Resources/Compiled/$name/source.sha256")" "$(scripts/make-icon.sh --hash "$name")"
done
expect "icon of a release" "$(plist CFBundleIconName)" AppIcon
[ -f Carrier.app/Contents/Resources/Assets.car ] && [ -f Carrier.app/Contents/Resources/AppIcon.icns ] || fail "a release lacks its compiled icon"
expect "CFBundleLocalizations of a release" "$(plutil -extract CFBundleLocalizations json -o - "$PLIST")" '["en","es"]'
expect_lprojs "a release"
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
GHOSTTY_TERMINFO="$(find Carrier.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle -type d -name terminfo | head -n 1)"
[ -n "$GHOSTTY_TERMINFO" ] || fail "GhosttyKit_GhosttyTerminal.bundle terminfo database is not in the app"
GHOSTTY_DIR="$(find Carrier.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle -type d -name Ghostty | head -n 1)"
[ -n "$GHOSTTY_DIR" ] || fail "GhosttyKit_GhosttyTerminal.bundle Ghostty resources are not in the app"
grep -q "Copyright (c) 2017 Ryan Caloras" "$GHOSTTY_DIR/shell-integration/bash/LICENSE-bash-preexec.md" || fail "bash-preexec license missing from GhosttyKit_GhosttyTerminal.bundle"
grep -q "Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors" "$L/THIRD-PARTY-NOTICES.md" || fail "Ghostty copyright notice missing from $L/THIRD-PARTY-NOTICES.md"
grep -q "OUT OF OR IN CONNECTION WITH THE SOFTWARE" "$L/THIRD-PARTY-NOTICES.md" || fail "Ghostty MIT text missing from $L/THIRD-PARTY-NOTICES.md"
codesign --verify --deep --strict Carrier.app || fail "codesign --verify --deep --strict failed"
# a release ships without its debug map (STABs, type "-" in nm -a) and keeps the symbols in Carrier.dSYM, which must be the one of the signed binary (crash reports are symbolicated with it)
BIN=Carrier.app/Contents/MacOS/Carrier
# (the linker's own OPT marker, `radr://5614542`, survives `strip -S`: it is no debug map)
expect "STABs left in the release binary (not stripped)" "$(nm -a "$BIN" | awk '$2 == "-" && $5 != "OPT"' | wc -l | tr -d ' ')" 0
[ -d Carrier.dSYM ] || fail "the release build left no Carrier.dSYM"
expect "dSYM UUID" "$(xcrun dwarfdump --uuid Carrier.dSYM | awk '{print $2}')" "$(xcrun dwarfdump --uuid "$BIN" | awk '{print $2}')"

./build-app.sh 0.1.4 >/dev/null
expect "CFBundleVersion for 0.1.4" "$(plist CFBundleVersion)" 104

./build-app.sh >/dev/null
expect "CFBundleVersion for no version" "$(plist CFBundleVersion)" 1
expect "CFBundleShortVersionString for no version" "$(plist CFBundleShortVersionString)" 0.1.0
expect "bundle id of a dev build" "$(plist CFBundleIdentifier)" dev.ashulab.carrier.dev
expect "channel of a dev build" "$(plist CarrierChannel)" dev
expect "CFBundleLocalizations of a dev build" "$(plutil -extract CFBundleLocalizations json -o - "$PLIST")" '["en","es"]'
expect_lprojs "a dev build"
expect "icon of a dev build" "$(plist CFBundleIconName)" AppIconDev
[ -f Carrier.app/Contents/Resources/Assets.car ] && [ -f Carrier.app/Contents/Resources/AppIconDev.icns ] || fail "a dev build lacks its compiled icon"
plist SUFeedURL >/dev/null 2>&1 && fail "a dev build has SUFeedURL, so its updater would start"
[ ! -d Carrier.dSYM ] || fail "a dev build left a Carrier.dSYM"

for v in 1.100.0 1.0.100; do
  if OUT="$(./build-app.sh "$v" 2>&1)"; then fail "build-app.sh accepted $v"; fi
  [[ "$OUT" == *"100 or more"* ]] || fail "build-app.sh refused $v for another reason: $OUT"
done
if OUT="$(CARRIER_MIC_USAGE= ./build-app.sh 2>&1)"; then fail "build-app.sh accepted an empty NSMicrophoneUsageDescription"; fi
[[ "$OUT" == *NSMicrophoneUsageDescription* ]] || fail "build-app.sh refused an empty microphone description for another reason: $OUT"
echo "check-app: ok"
