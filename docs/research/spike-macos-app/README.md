# Spike: macOS menu bar app

Disposable prototype behind [the macOS app research](../macos-app.md). Fake data, nothing connects to Carrier. Needs macOS 13+ and the Command Line Tools.

- `./build-app.sh [--open]` builds `SpikeCarrier.app` with SwiftPM and signs it ad hoc (the permission for notifications needs that).
- `./run-demo.sh ca|smooth|slow|static` starts it: `ca` is the one worth reading (an `NSStatusItem` drawn with Core Animation layers, animation capped at 20 fps, plain AppKit lifecycle).
- `./measure.sh` measures the CPU of the app and of `WindowServer` for each way of animating (see section 6 of the research).
- Start with `Sources/CAItem.swift` (the icon, its animations and the menu) and `Sources/CAAppDelegate.swift` (the window). `Sources/Icon.swift` and `Sources/App.swift` hold the image-swapping variants that lost.
- `SPIKE_CA=1 SPIKE_SELFTEST=<file>` runs the menu actions from code and logs each step.
