# 0051 - The app also ships as an Intel build, with its own zip and feed

- Status: proposed
- Date: 2026-11-23

## Context

[0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) left an Intel Mac with the engine and the chat host but not the app: the cask said `depends_on arch: :arm64`, the appcast said `hardwareRequirements arm64` and the app ran `/opt/homebrew/bin/brew`.
Nothing in the code needs Apple Silicon.
`macos/Sources` has no `#if arch(arm64)`, no package restricts its architecture, and Sparkle, GhosttyKit and NemoTextProcessing already ship an `x86_64` slice.
A spike compiled the whole app with `swift build -c release --arch x86_64` on an Apple Silicon Mac in 146 seconds, bundled it with the unchanged `build-app.sh`, and ran its `--selftest` under Rosetta: every step of the menu and every page of Settings (Dictation included) drew, and the process was alive at the end.

An Intel Mac cannot run macOS 27 (Sparkle's own source says so), and the app needs macOS 26, so the Intel audience is the Intel Macs on macOS 26 and it will not grow.

## Decision

The release builds the app twice, side by side, on the same `macos-26` runner: Apple Silicon natively, and Intel cross-compiled with `CARRIER_ARCH=x86_64` (`swift build --arch x86_64`).
The Intel app is an x86_64-only binary.
A universal binary is not shipped: it would double the download for everyone, and an Apple Silicon person would carry code that never runs.

Each architecture has its own files, which keeps an installed Apple Silicon app and its feed exactly as they were:

- `Carrier-X.Y.Z.zip` and `appcast.xml` for Apple Silicon, as before; `Carrier-X.Y.Z-intel.zip`, its `.sha256`, its `.dSYM.zip` and `appcast-intel.xml` for Intel.
- The Intel app's `SUFeedURL` is `.../releases/latest/download/appcast-intel.xml`, so an Intel app never reads a feed that offers it an arm64 zip, and the reverse.
- `appcast.mjs` reads the architecture from the app's binary, which must hold exactly one, and names the zip, the item and its checks from it.
  Sparkle only knows the `arm64` hardware requirement, so the Intel item has none.
- The cask has `on_arm` and `on_intel` blocks, each with its own `url` and `sha256`, and no `depends_on arch`.
  `cask.mjs release` writes them, and also turns the flat Apple Silicon cask the tap has today into that shape.
- The app runs the `brew` of its own architecture's prefix, decided at compile time (`/opt/homebrew` on arm64, `/usr/local` on x86_64).

The release does not run the app's tests on an Intel machine: the runner is Apple Silicon.
The pull request's CI checks the bundle of both architectures too (`_macos.yml` runs `check-app.sh` once for each), so a change that breaks the Intel one fails before a release.
The unit tests run natively and the Intel bundle is checked by `check-app.sh` (its binary is x86_64 only, its feed is the Intel one) and by the architecture check of the zip.

## Consequences

Every release has one more app job (about the time of the first), two zips and two appcasts, and its Release has six app files.
An Intel person installs with the same command as before.

What is not known yet, and has to be tried on a real Intel Mac before the first Intel release is announced: the dictation (FluidAudio and WhisperKit target the Neural Engine of Apple Silicon and name no Intel support, so on Intel it may be slow or unusable, and the way out is to turn it off in that build), and the app's speed in general.
Rosetta on Apple Silicon runs the code but says nothing about either.

The Intel build has an end date: when the last Intel Mac on macOS 26 is gone, the second job, the second feed and the `on_intel` block are deleted.
The Intel zip is ad-hoc signed like the other (see 0017).
It is a new dSYM per architecture, symbolicated with `-arch x86_64`.

[0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)'s "An Intel Mac gets the engine and the chat host but not the app" no longer holds once this is accepted.

## Alternatives considered

A universal binary (`--arch arm64 --arch x86_64`), one zip and one feed.
It is one artifact and no cask or feed change, but it doubles the download, cannot be checked as one architecture, and an Intel-specific problem (dictation, say) would block or burden the Apple Silicon build.

No Intel app.
It stays the cheapest.
It was the standing answer, and it leaves the people on an Intel Mac with macOS 26 with the command line only.

An Intel runner (`macos-15-intel`) for the Intel build.
It would let the unit tests run there, but it is a second kind of runner, slower and scarcer, and the cross-compile is the same code.
It stays an option for the tests.
