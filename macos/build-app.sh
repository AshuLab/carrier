#!/bin/bash
# Builds Carrier.app with SwiftPM (needs Xcode selected, see README.md) and signs it ad hoc.
# Usage: ./build-app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")"
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
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.ashulab.carrier</string>
<key>CFBundleExecutable</key><string>Carrier</string>
<key>CFBundleName</key><string>Carrier</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
if [ "${1:-}" = "--open" ]; then open "$APP"; fi
