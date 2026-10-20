#!/bin/bash
# Disposable spike: builds SpikeCarrier.app (SwiftPM, no Xcode project) and signs it ad hoc.
# Run it twice to test whether a rebuilt + re-signed app makes macOS ask for notification permission again.
set -euo pipefail
cd "$(dirname "$0")"
N=$(( $(cat .build-number 2>/dev/null || echo 0) + 1 )); echo "$N" > .build-number
swift build -c release
APP=SpikeCarrier.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/SpikeCarrier "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.ashulab.carrier.spike</string>
<key>CFBundleExecutable</key><string>SpikeCarrier</string>
<key>CFBundleName</key><string>Carrier Spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$N</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP (build $N)"
if [ "${1:-}" = "--open" ]; then open "$APP"; fi
