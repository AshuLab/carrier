#!/bin/sh
# Takes the screenshots the note refers to, into ../macos-app-design/theme-reach/. Needs a logged-in desktop; each run opens a window for a few seconds.
cd "$(dirname "$0")" && swift build -q || exit 1
B=.build/debug/SpikeThemeReach
O=../macos-app-design/theme-reach
mkdir -p "$O"
$B --theme forest --no-accent --no-paint --shot $O/stock.png
$B --theme forest --shot $O/forest-light.png
$B --theme forest --accent-color-api --shot $O/accent-color-api.png
$B --theme forest --list-tint --row-bg --shot $O/list-tint.png
$B --theme forest --tint subtle --shot $O/tint-subtle.png
$B --theme forest --tint strong --shot $O/tint-strong.png
$B --theme forest --no-paint --window-bg --shot $O/window-bg.png
$B --theme forest --under-title --tint subtle --shot $O/under-title.png
$B --theme forest --scheme dark --shot $O/forest-dark.png
$B --theme forest --sheet --shot $O/sheet-light.png
$B --theme forest --scheme light --scheme-api nsapp --sheet --shot $O/sheet-light-nsapp.png
$B --theme forest --sheet --sheet-tint --sheet-bg --shot $O/sheet-tinted.png
$B --theme forest --scheme dark --scheme-api nsapp --sheet --sheet-tint --sheet-bg --shot $O/sheet-tinted-dark.png
$B --theme forest --popover --shot $O/popover-light.png
$B --theme forest --scheme dark --popover --sheet-bg --shot $O/popover-bg-dark.png
