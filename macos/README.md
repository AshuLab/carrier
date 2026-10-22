# Carrier.app

Menu bar app for Carrier. A SwiftPM package for macOS 26 or later: `CarrierCore` (library), `Carrier` (the AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing). Building needs **Xcode** (see Toolchain).

## Toolchain

Xcode is required, not just the Command Line Tools. With the macOS 27 SDK SwiftUI's `@State` is a macro whose plugin ships only with Xcode, so with only the Command Line Tools selected `swift build` fails with `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`. Install Xcode and select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # or: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcode-select -p                                                  # should print the Xcode path, not .../CommandLineTools
```

`build-app.sh` checks this first: with the Command Line Tools selected it prints how to select Xcode and exits 1 without building.

Workaround, unsupported: `swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk` does build the package under the Command Line Tools (verified), because the older SDK has no `@State` macro. `swift test` that way was not verified and `build-app.sh` does not use it.

## Build and open

```sh
cd macos
./build-app.sh          # release build wrapped in Carrier.app (bundle id dev.ashulab.carrier), signed ad hoc
./build-app.sh --open   # same, then opens it
open Carrier.app
```

`Carrier.app` has no Dock icon: it shows one menu bar item. Its menu opens with a heading (a dot, green while running, orange when intake is paused, an epic needs you or there is a problem, grey when stopped; a bold title and the epic and slot counts), then, while Carrier runs, the epics (needs you, running, waiting, ready; at most twenty, then "… and N more") with a state glyph, a secondary line and a badge, rebuilt each time the menu opens; the Settings switch "Show epics in the menu" (user default `menu.showEpics`, on by default) turns the list off, and choosing an epic opens the window on its section. Then only the controls that apply: while Carrier is stopped, Start Carrier (enabled only when the settings have `node`, `carrier` and a config path; it says what is missing otherwise); while it runs, Pause intake (Resume intake while paused), Check GitHub now and Stop Carrier, which asks first when epics are running, since it interrupts them (they resume on the next start), and stops straight away when none are. Last, Open window (⌘O), Settings… (⌘,) and Quit Carrier (⌘Q). The line comes from Carrier's control socket, `<root>/orchestrator/control.sock`, where `<root>` is the `root` of `$CARRIER_HOME/config.json` (else `~/.carrier/config.json`), `~/.solve` when there is none; the app asks for the snapshot every second while connected and tries to connect every three seconds while not. Check the signature with `codesign --verify Carrier.app` and `codesign -dv Carrier.app` (it should say `Signature=adhoc`).

## Settings

The menu's Settings… opens the values the app starts Carrier with: `carrier`, `node`, the `PATH`, the config path and the shared root, each editable and marked "not found" when empty. On the first launch (nothing saved in user defaults) the app asks the user's shell once, `zsh -ilc` with markers around what it prints and a 10 second limit, for `carrier`, `node` and the `PATH`; the config path and root come from where Carrier keeps them, not from the shell. "Detect again" repeats the run. The window's Settings screen (sidebar, bottom) shows the same five values as the Engine tab with a banner that says whether Start Carrier is ready; Choose opens a file or folder chooser, Reveal opens Finder, and the model is `CarrierCore/EngineTab.swift`. The Notifications tab (`CarrierCore/NotificationsTab.swift`) shows the system permission (allowed, denied with a button to System Settings, not asked, or only from `Carrier.app`), a test notification and the two switches (user defaults `notify.needsYou` and `notify.readyForTest`, on by default) that gate the notification comparison. The General tab (`CarrierCore/GeneralTab.swift`) has Open at login (`SMAppService.mainApp`, driven by its status, disabled outside a bundle), Ask before stopping Carrier (`stop.confirm`, on by default), the start log and Reset settings, which forgets the saved paths after a confirmation and detects again. The Menu bar tab chooses the icon's style (count and bar, count only, bar only; count only falls back to the bar when nothing is running, so the icon never vanishes), whether the bouncing segment animates, and "Show epics in the menu"; they are user defaults (`menu.iconStyle`, `menu.animate`, `menu.showEpics`, model in `CarrierCore/MenuBarStore.swift`) and the icon follows with no relaunch. With saved values the shell is never started. The `PATH` the engine will get is the detected one with node's directory first.

## Start Carrier

Start Carrier (the menu item, and a button in the window while Carrier is stopped) runs `node <carrier> --config <config path>` with that `PATH`, in its own session (`posix_spawn` with `POSIX_SPAWN_SETSID`, so quitting the app leaves Carrier running), stdin from `/dev/null` and stdout and stderr in `<root>/orchestrator/logs/app-start.log`, which it creates (the `orchestrator/` folder with mode 0700) when missing. It is never started on its own when the app opens. When the control socket answers within 15 seconds the state becomes running (the next connect attempt shows it, within 3 seconds); when the process exits first, or 15 seconds pass without the socket, an alert shows the end of `app-start.log`. A second press while it starts does nothing. The decision and the command line are in `CarrierCore/StartCarrier.swift`; the spawn and the alert have no automated test. The self-test only checks the start (what it would run), as it does for Stop.

## File icons

`fileIcon(path)` (`CarrierCore/FileIcons.swift`) is the one place that picks a file's icon: a bundled SVG from Material Icon Theme (MIT) for the languages in `bundledIconName`, else the category's SF Symbol. The SVGs and the upstream licence text are in `Sources/CarrierCore/Resources/FileIcons` (about 12 KB; release pinned in `SOURCE.txt`, notice in `THIRD-PARTY-NOTICES.md`, line in About). `build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when an icon or the licence text is missing from it.

## Test

```sh
cd macos
swift build && swift test
```

The shell's layers have no automated tests (`CarrierTests` only checks that the icon's layer host takes no clicks); the logic behind them is tested in `CarrierCoreTests`. Its smoke check is the self-test flag: it runs the menu's actions from code, one a second (pause, resume and check now are sent to a running Carrier, resume putting back the pause state it found; Stop is only checked, as it would end the Carrier under test), appends a line per step to the file and ends with a line saying the process was still alive.

```sh
./Carrier.app/Contents/MacOS/Carrier --selftest /tmp/carrier-selftest.log
cat /tmp/carrier-selftest.log   # last line: "end: process still alive ..."
```

With `--fixture` the log also has `rings, window open` and `rings, window closed` (`rings=N animating=M`): the spinning rings of running epics turn only while the window is visible and Reduce Motion is off, so the second line must say `animating=0`.

The app keeps running afterwards; quit it from the menu or with `osascript -e 'tell application id "dev.ashulab.carrier" to quit'`.

## Fixture mode

`--fixture [folder]` runs the app against a fake Carrier, so the window can be looked at with no engine. The app starts an in-process control server (`CarrierCore/FixtureServer.swift`) on a socket in a temporary folder under `/tmp`, points `CARRIER_HOME` at it and connects as to any Carrier. It answers `snapshot`, `sessions`, `events`, `epic` and `files` from the golden files in `Tests/Fixtures`, pause, resume, check now and stop with a plain ok that does nothing, and anything else with an error. `folder` defaults to the copy of the golden files that `build-app.sh` puts in `Carrier.app/Contents/Resources/Fixtures`; give one when running without the bundle. The temporary folder is removed when the app quits. In this mode the menu also has "Empty states", a window listing the eight empty states (`CarrierCore/EmptyStates.swift`). It combines with `--selftest`. `--fixture-long-transcript` (with `--fixture`) answers `events` with a made-up transcript of 3,600 events (edits with diffs, passing and failing commands with output) instead of the golden file, to scroll a long one.

```sh
./Carrier.app/Contents/MacOS/Carrier --fixture
./Carrier.app/Contents/MacOS/Carrier --fixture --selftest /tmp/carrier-selftest.log
```

## Window smoke check

`--smoke-window` opens the window, selects the first epic Carrier reports, waits three seconds, prints what it sees and exits: the minimum content size (980 wide; the height is 600 plus the 52 point title band), the width of the sidebar (268) and of the inspector (316), one `scroll pocket` line per scroll pocket (the epic view's pipeline bar makes one in the centre column, at x 268, taller than the 52 point title band) the toolbar items (Sidebar, Open PR and Open issue when the epic has them, Inspector), a `transcript:` line saying how the Agent output tab is laid out (`lazy stack, pinned section headers`, read from the constants the view itself uses) and a `transcript merge:` line, the time to merge a made-up transcript of 5,004 events (a few milliseconds). It needs a screen and combines with `--fixture`.

```sh
./Carrier.app/Contents/MacOS/Carrier --smoke-window --fixture
```
