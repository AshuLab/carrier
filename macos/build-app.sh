#!/bin/bash
# Builds Carrier.app with SwiftPM (needs Xcode selected, see README.md) and signs it ad hoc.
# Usage: ./build-app.sh [version] [--open]   (version is written into the plist, 0.1.0 when none is given)
# The build number (CFBundleVersion) is what Sparkle compares: X.Y.Z -> X*10000 + Y*100 + Z, and 1 when no version is given.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=0.1.0
BUILD=1
OPEN=false
GIVEN=false
for arg in "$@"; do
  if [ "$arg" = "--open" ]; then OPEN=true; else VERSION="$arg"; GIVEN=true; fi
done
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
swift build -c release
APP=Carrier.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Carrier "$APP/Contents/MacOS/"
# Sparkle: SwiftPM does not give the executable an rpath into the bundle, and without it the app dies at launch. ditto keeps the framework's symlinks.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Carrier"
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
# the golden files `--fixture` serves
mkdir -p "$APP/Contents/Resources"
cp -R Tests/Fixtures "$APP/Contents/Resources/Fixtures"
# the app's icon (made by scripts/make-icon.swift)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM's resource bundle of CarrierCore: the file icons and the licence text that goes with them
cp -R .build/release/Carrier_CarrierCore.bundle "$APP/Contents/Resources/"
# the licences of what is linked in: FluidAudio (Apache-2.0) with the notices of what it vendors (NemoTextProcessing, fastcluster, ...),
# argmax-oss-swift (MIT) with its NOTICES (swift-transformers, Apache-2.0), and the repository's own notices file
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES/FluidAudio" "$LICENSES/argmax-oss-swift"
cp .build/checkouts/FluidAudio/LICENSE "$LICENSES/FluidAudio/LICENSE"
cp -R .build/checkouts/FluidAudio/ThirdPartyLicenses "$LICENSES/FluidAudio/ThirdPartyLicenses"
cp .build/checkouts/argmax-oss-swift/LICENSE .build/checkouts/argmax-oss-swift/NOTICES "$LICENSES/argmax-oss-swift/"
cp ../THIRD-PARTY-NOTICES.md "$LICENSES/THIRD-PARTY-NOTICES.md"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.ashulab.carrier</string>
<key>CFBundleExecutable</key><string>Carrier</string>
<key>CFBundleName</key><string>Carrier</string>
<key>CFBundleDisplayName</key><string>Carrier</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>$MIC_USAGE</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 AshuLab</string>
<key>SUFeedURL</key><string>https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < update-key.pub)</string>
<key>SUEnableAutomaticChecks</key><true/>
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
# the licence texts must be in the app: the ones the libraries ask to be kept with a binary distribution
grep -q "Apache License" "$LICENSES/FluidAudio/LICENSE" || { echo "error: $APP lacks the FluidAudio licence text" >&2; exit 1; }
grep -q "Redistributions in binary form must reproduce" "$LICENSES/FluidAudio/ThirdPartyLicenses/fastcluster-LICENSE.md" || { echo "error: $APP lacks the fastcluster licence text" >&2; exit 1; }
grep -q "text-processing-rs" "$LICENSES/FluidAudio/ThirdPartyLicenses/NemoTextProcessing-LICENSE.md" || { echo "error: $APP lacks the notice of NemoTextProcessing" >&2; exit 1; }
grep -q "Permission is hereby granted" "$LICENSES/argmax-oss-swift/LICENSE" || { echo "error: $APP lacks the WhisperKit licence text" >&2; exit 1; }
grep -q "swift-transformers" "$LICENSES/argmax-oss-swift/NOTICES" || { echo "error: $APP lacks the notice of swift-transformers" >&2; exit 1; }
grep -q "FluidAudio" "$LICENSES/THIRD-PARTY-NOTICES.md" || { echo "error: $APP lacks the third-party notices" >&2; exit 1; }
codesign --force --deep --sign - "$APP"
echo "built $APP"
if [ "$OPEN" = true ]; then open "$APP"; fi
