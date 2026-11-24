#!/bin/bash
# Builds Carrier.app with SwiftPM (needs Xcode selected, see README.md) and signs it ad hoc.
# Usage: ./build-app.sh [version] [--open]   (version is written into the plist, 0.1.0 when none is given)
# CARRIER_REUSE_BUILD=1 skips `swift build` and bundles the .build/release/Carrier that is already there (check-app.sh and the release build many bundles from one compile).
# No version means a dev build: its own name, bundle id and settings, and no updater, so it never gets mixed up with the installed Carrier.
# CARRIER_ARCH=x86_64 builds the Intel app: an x86_64-only binary (never a universal one, so the compile also works on an Apple Silicon runner) with its own update feed, appcast-intel.xml.
# No CARRIER_ARCH is the Mac the script runs on (Apple Silicon), and the feed is appcast.xml.
# The build number (CFBundleVersion) is what Sparkle compares: X.Y.Z -> X*10000 + Y*100 + Z, and 1 when no version is given.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=0.1.0
BUILD=1
# an allowlist: the value reaches `swift build` and the feed's URL
case "${CARRIER_ARCH:-}" in
  "") ARCH_FLAGS=(); FEED=appcast.xml ;;
  x86_64) ARCH_FLAGS=(--arch x86_64); FEED=appcast-intel.xml ;;
  *) echo "error: CARRIER_ARCH '${CARRIER_ARCH}' is not x86_64 (or empty, for this Mac's own architecture)" >&2; exit 1 ;;
esac
OPEN=false
GIVEN=false
for arg in "$@"; do
  if [ "$arg" = "--open" ]; then OPEN=true; else VERSION="$arg"; GIVEN=true; fi
done
if [ "$GIVEN" = true ]; then
  CHANNEL=release; NAME=Carrier; BUNDLE_ID=dev.ashulab.carrier; ICON=AppIcon
  # the updater starts only from a bundle with a feed (AppUpdater.start), so a dev build has none
  UPDATER="<key>SUFeedURL</key><string>https://github.com/AshuLab/carrier/releases/latest/download/$FEED</string>
<key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < update-key.pub)</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>3600</integer>"
else
  CHANNEL=dev; NAME="Carrier Dev"; BUNDLE_ID=dev.ashulab.carrier.dev; ICON=AppIconDev; UPDATER=""
fi
# the version lands in the plist as XML, so only X.Y.Z gets in
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version '$VERSION' is not X.Y.Z" >&2; exit 1; }
if [ "$GIVEN" = true ]; then
  IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
  # a part of 100 or more would make the number stop growing with the version
  [ "$((10#$MINOR))" -lt 100 ] && [ "$((10#$PATCH))" -lt 100 ] || { echo "error: version '$VERSION' has a minor or patch of 100 or more, so its build number would not grow with it" >&2; exit 1; }
  BUILD=$((10#$MAJOR * 10000 + 10#$MINOR * 100 + 10#$PATCH))
fi
# what macOS shows when the app asks for the microphone; CARRIER_MIC_USAGE exists so check-app.sh can prove an empty one fails the build
MIC_USAGE="${CARRIER_MIC_USAGE-Carrier listens through the microphone only while you dictate a message, and the audio never leaves your Mac.}"
# checked before the compile, which takes minutes: the plist check at the end only confirms what is already known here
[ -n "$MIC_USAGE" ] || { echo "error: NSMicrophoneUsageDescription is empty" >&2; exit 1; }
# SwiftUI's @State is a macro whose plugin ships only with Xcode, so the Command Line Tools cannot compile the views.
case "$(xcode-select -p 2>/dev/null)" in
  */CommandLineTools*|"")
    cat >&2 <<'MSG'
error: Carrier.app needs Xcode, but the developer directory is not Xcode (the Command Line Tools or nothing).
The Command Line Tools cannot compile the SwiftUI views (the @State macro plugin ships only with Xcode).
Install Xcode, then select it:  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
Or for this shell only:         export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
MSG
    exit 1 ;;
esac
if [ "${CARRIER_REUSE_BUILD:-}" = 1 ]; then
  [ -x .build/release/Carrier ] || { echo "error: CARRIER_REUSE_BUILD=1 but .build/release/Carrier does not exist" >&2; exit 1; }
else
  # (${ARCH_FLAGS[@]+...}: bash 3.2 of macOS, under set -u, takes an empty array as unset)
  swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
fi
# the Intel app must hold an x86_64 binary and nothing else, whatever .build/release was left holding
if [ -n "${CARRIER_ARCH:-}" ]; then
  [ "$(lipo -archs .build/release/Carrier)" = "$CARRIER_ARCH" ] || { echo "error: .build/release/Carrier is '$(lipo -archs .build/release/Carrier)', not $CARRIER_ARCH only" >&2; exit 1; }
fi
APP=Carrier.app
rm -rf "$APP" Carrier.dSYM
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Carrier "$APP/Contents/MacOS/"
# Sparkle: SwiftPM does not give the executable an rpath into the bundle, and without it the app dies at launch. ditto keeps the framework's symlinks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Carrier"
if [ "$GIVEN" = true ]; then
  # a release ships without its debug map (STABs, 30 MB of the binary): it points at .build's .o files, so dsymutil reads it now, before the strip drops it,
  # and crash reports are symbolicated with Carrier.dSYM. Neither install_name_tool nor strip change the LC_UUID, so the dSYM matches the signed binary (check-app.sh).
  dsymutil .build/release/Carrier -o Carrier.dSYM
  strip -S -x "$APP/Contents/MacOS/Carrier"
fi
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
# the golden files `--fixture` serves
mkdir -p "$APP/Contents/Resources"
cp -R Tests/Fixtures "$APP/Contents/Resources/Fixtures"
# what `--fixture` shows is AppFixture's (no sessions, no epics, yet), not the tests' set (those stay in Tests/Fixtures)
rm "$APP"/Contents/Resources/Fixtures/chat-events-*.json
cp AppFixture/*.json "$APP/Contents/Resources/Fixtures/"
# the app's icon of its channel, compiled from Resources/AppIcon.icon or AppIconDev.icon (the one with the pink mark) by scripts/make-icon.sh:
# Assets.car is the layered icon of macOS 26 and the .icns is for what reads the file. It is not compiled here: see make-icon.sh
cp "Resources/Compiled/$ICON/Assets.car" "Resources/Compiled/$ICON/$ICON.icns" "$APP/Contents/Resources/"
# SwiftPM's resource bundle of CarrierCore: the file icons and the licence text that goes with them
cp -R .build/release/Carrier_CarrierCore.bundle "$APP/Contents/Resources/"
# GhosttyTerminal's bundled shell integration and terminfo database
cp -R .build/release/GhosttyKit_GhosttyTerminal.bundle "$APP/Contents/Resources/"
# the licences of what is linked in: FluidAudio (Apache-2.0) with the notices of what it vendors (NemoTextProcessing, fastcluster, ...),
# argmax-oss-swift (MIT) with its NOTICES (swift-transformers, Apache-2.0), libghostty-spm/Ghostty + DisplayLink (MIT), and the repository's own notices file
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES/FluidAudio" "$LICENSES/argmax-oss-swift" "$LICENSES/libghostty-spm" "$LICENSES/DisplayLink"
cp .build/checkouts/FluidAudio/LICENSE "$LICENSES/FluidAudio/LICENSE"
cp -R .build/checkouts/FluidAudio/ThirdPartyLicenses "$LICENSES/FluidAudio/ThirdPartyLicenses"
cp .build/checkouts/argmax-oss-swift/LICENSE .build/checkouts/argmax-oss-swift/NOTICES "$LICENSES/argmax-oss-swift/"
cp .build/checkouts/libghostty-spm/LICENSE "$LICENSES/libghostty-spm/LICENSE"
cp .build/checkouts/DisplayLink/LICENSE "$LICENSES/DisplayLink/LICENSE"
cp ../THIRD-PARTY-NOTICES.md "$LICENSES/THIRD-PARTY-NOTICES.md"
# CFBundleLocalizations lists `en` alone: declaring `es` turns macOS's own texts Spanish at once, so it waits until every copy key has its Spanish words
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>Carrier</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CarrierChannel</key><string>$CHANNEL</string>
<key>CFBundleIconFile</key><string>$ICON</string>
<key>CFBundleIconName</key><string>$ICON</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>$MIC_USAGE</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 AshuLab</string>
$UPDATER
</dict></plist>
PLIST
# dictation asks macOS for the microphone, and without a usage description the app is killed on the first click
[ -n "$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" 2>/dev/null)" ] || { echo "error: $APP has no NSMicrophoneUsageDescription, or it is empty" >&2; exit 1; }
# the icons and their licence must be in the app: every icon of the source folder, and the upstream MIT text
# (the bundle's layout depends on the toolchain: Swift 6.4 nests Contents/Resources, 6.3 does not)
ICONS="$(find "$APP/Contents/Resources/Carrier_CarrierCore.bundle" -type d -name FileIcons | head -n 1)"
[ -n "$ICONS" ] || { echo "error: $APP has no FileIcons folder; its bundle holds:" >&2; find "$APP/Contents/Resources/Carrier_CarrierCore.bundle" -maxdepth 3 >&2; exit 1; }
for svg in Sources/CarrierCore/Resources/FileIcons/*.svg; do
  [ -f "$ICONS/$(basename "$svg")" ] || { echo "error: $APP lacks the icon $(basename "$svg")" >&2; exit 1; }
done
grep -q "Permission is hereby granted" "$ICONS/LICENSE" || { echo "error: $APP lacks the Material Icon Theme licence text" >&2; exit 1; }
# the same for the interface's own icon sets: Tabler (an outline and a filled folder, MIT) and Lucide (ISC), each with its upstream licence text
TABLER="$(find "$APP/Contents/Resources/Carrier_CarrierCore.bundle" -type d -name TablerIcons | head -n 1)"
[ -n "$TABLER" ] || { echo "error: $APP has no TablerIcons folder" >&2; exit 1; }
for svg in Sources/CarrierCore/Resources/TablerIcons/*/*.svg; do
  [ -f "$TABLER/$(basename "$(dirname "$svg")")/$(basename "$svg")" ] || { echo "error: $APP lacks the icon $(basename "$svg")" >&2; exit 1; }
done
grep -q "Permission is hereby granted" "$TABLER/LICENSE" || { echo "error: $APP lacks the Tabler Icons licence text" >&2; exit 1; }
LUCIDE="$(find "$APP/Contents/Resources/Carrier_CarrierCore.bundle" -type d -name LucideIcons | head -n 1)"
[ -n "$LUCIDE" ] || { echo "error: $APP has no LucideIcons folder" >&2; exit 1; }
for svg in Sources/CarrierCore/Resources/LucideIcons/*.svg; do
  [ -f "$LUCIDE/$(basename "$svg")" ] || { echo "error: $APP lacks the icon $(basename "$svg")" >&2; exit 1; }
done
grep -q "Permission to use, copy, modify" "$LUCIDE/LICENSE" || { echo "error: $APP lacks the Lucide licence text" >&2; exit 1; }
# the licence texts must be in the app: the ones the libraries ask to be kept with a binary distribution
grep -q "Apache License" "$LICENSES/FluidAudio/LICENSE" || { echo "error: $APP lacks the FluidAudio licence text" >&2; exit 1; }
grep -q "Redistributions in binary form must reproduce" "$LICENSES/FluidAudio/ThirdPartyLicenses/fastcluster-LICENSE.md" || { echo "error: $APP lacks the fastcluster licence text" >&2; exit 1; }
grep -q "text-processing-rs" "$LICENSES/FluidAudio/ThirdPartyLicenses/NemoTextProcessing-LICENSE.md" || { echo "error: $APP lacks the notice of NemoTextProcessing" >&2; exit 1; }
grep -q "Permission is hereby granted" "$LICENSES/argmax-oss-swift/LICENSE" || { echo "error: $APP lacks the WhisperKit licence text" >&2; exit 1; }
grep -q "swift-transformers" "$LICENSES/argmax-oss-swift/NOTICES" || { echo "error: $APP lacks the notice of swift-transformers" >&2; exit 1; }
grep -q "MIT License" "$LICENSES/libghostty-spm/LICENSE" || { echo "error: $APP lacks the libghostty-spm licence text" >&2; exit 1; }
grep -q "MIT License" "$LICENSES/DisplayLink/LICENSE" || { echo "error: $APP lacks the DisplayLink licence text" >&2; exit 1; }
grep -q "FluidAudio" "$LICENSES/THIRD-PARTY-NOTICES.md" || { echo "error: $APP lacks the third-party notices" >&2; exit 1; }
grep -q "Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors" "$LICENSES/THIRD-PARTY-NOTICES.md" || { echo "error: $APP lacks the Ghostty MIT copyright notice" >&2; exit 1; }
grep -q "OUT OF OR IN CONNECTION WITH THE SOFTWARE" "$LICENSES/THIRD-PARTY-NOTICES.md" || { echo "error: $APP lacks the Ghostty MIT licence text" >&2; exit 1; }
GHOSTTY_TERMINFO="$(find "$APP/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle" -type d -name terminfo | head -n 1)"
[ -n "$GHOSTTY_TERMINFO" ] || { echo "error: $APP lacks GhosttyKit_GhosttyTerminal.bundle terminfo database" >&2; exit 1; }
GHOSTTY_DIR="$(find "$APP/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle" -type d -name Ghostty | head -n 1)"
[ -n "$GHOSTTY_DIR" ] || { echo "error: $APP lacks GhosttyKit_GhosttyTerminal.bundle Ghostty resources" >&2; exit 1; }
grep -q "Copyright (c) 2017 Ryan Caloras" "$GHOSTTY_DIR/shell-integration/bash/LICENSE-bash-preexec.md" || { echo "error: $APP lacks LICENSE-bash-preexec.md" >&2; exit 1; }
codesign --force --deep --sign - "$APP"
echo "built $APP"
if [ "$OPEN" = true ]; then open "$APP"; fi
