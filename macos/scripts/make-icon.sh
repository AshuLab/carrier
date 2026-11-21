#!/bin/bash
# Compiles the app icons (Resources/AppIcon.icon, Resources/AppIconDev.icon: Icon Composer files) into Resources/Compiled/<name>/ with actool:
# Assets.car (the layered icon of macOS 26) and an .icns, plus the hash of the .icon that made them (check-app.sh compares it, so a changed .icon with no new build is caught).
# Run it from macos/ after changing a .icon, and commit what it writes. build-app.sh only copies the result: the runner's Xcode (26.x) cannot open an .icon saved by a newer Icon Composer, so CI does not compile.
set -euo pipefail
cd "$(dirname "$0")/../Resources"
icon_hash() { find "$1.icon" -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1; }
if [ "${1:-}" = "--hash" ]; then icon_hash "$2"; exit 0; fi
for NAME in AppIcon AppIconDev; do
  OUT="Compiled/$NAME"
  rm -rf "$OUT"; mkdir -p "$OUT"
  xcrun actool "$NAME.icon" --compile "$OUT" --output-format human-readable-text --warnings --errors \
    --output-partial-info-plist "$OUT/partial.plist" --app-icon "$NAME" --include-all-app-icons \
    --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 26.0 --platform macosx >/dev/null
  rm "$OUT/partial.plist"
  icon_hash "$NAME" > "$OUT/source.sha256"
  echo "wrote Resources/$OUT"
done
