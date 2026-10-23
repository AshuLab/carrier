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

`Carrier.app` has no Dock icon: it shows one menu bar item. Its menu opens with a heading (a dot, green while running, orange when intake is paused, an epic needs you or there is a problem, grey when stopped; a bold title and the epic and slot counts), then, while Carrier runs, the epics (needs you, running, waiting, ready; at most twenty, then "… and N more") with a state glyph, a secondary line and a badge, rebuilt each time the menu opens; the Settings switch "Show epics in the menu" (user default `menu.showEpics`, on by default) turns the list off, and choosing an epic opens the window on its section. Then only the controls that apply: while Carrier is stopped, Start Carrier (enabled only when the settings have `node`, `carrier` and a config path; it says what is missing otherwise); while it runs, Pause intake (Resume intake while paused), Check GitHub now and Stop Carrier, which asks first when epics are running, since it interrupts them (they resume on the next start), and stops straight away when none are. Last, Open window (⌘O), Settings… (⌘,) and Quit Carrier (⌘Q). The line comes from Carrier's control socket, `<root>/orchestrator/control.sock`, where `<root>` is the `root` of the config file (`$CARRIER_HOME/config.json` when that is set in the app's environment, else the config path chosen in Settings, else `~/.carrier/config.json`), `~/.solve` when there is none; the app reads it again at each connection attempt, so a changed config path is followed without a relaunch; the app asks for the snapshot every second while connected and tries to connect every three seconds while not. Check the signature with `codesign --verify Carrier.app` and `codesign -dv Carrier.app` (it should say `Signature=adhoc`).

## Settings

The menu's Settings… opens the values the app starts Carrier with: `carrier`, `node`, the `PATH` and the config path, each editable and marked "not found" when empty. On the first launch (nothing saved in user defaults) the app asks the user's shell once, `zsh -ilc` with markers around what it prints and a 10 second limit, for `carrier`, `node` and the `PATH`; the config path comes from where Carrier keeps it, not from the shell. The root is not a setting: it is always read from the config file. "Detect again" repeats the run. The window's Settings screen (sidebar, bottom) shows the same four values as the Engine tab; a banner on every tab says what Start Carrier lacks, or that it is looking for it, and is not shown when all is found, in which case the Engine tab is one line ("Carrier is ready to start", with Show paths and Detect again) and opens the paths only on request (`enginePathsShown`: they are open by themselves while something is missing or being detected); Choose opens a file or folder chooser, Reveal opens Finder, and the model is `CarrierCore/EngineTab.swift`. The Notifications tab (`CarrierCore/NotificationsTab.swift`, the logic in `CarrierCore/Notifications.swift`) has three groups. What to tell me: Needs you and Ready for test (user defaults `notify.needsYou` and `notify.readyForTest`, on by default) and A problem (`notify.problem`, off by default), which says once when the snapshot's `problem` text appears or changes, once when GitHub starts refusing a watched repo (until it recovers) and once when Carrier stops without the app having asked: Stop in the menu and the restart of the Behavior and Repos tabs call `NotificationWatcher.expectStop()`, which lapses after 30 seconds. How: Only when Carrier is not in front (`notify.onlyWhenAway`, on by default), which holds the banner back while the app is active (`shouldPresent`; the test notification always shows). There is no sound switch: sound and the style of the banner belong to macOS, per app, in System Settings › Notifications › Carrier. Permission shows what macOS says (`UNNotificationSettings`: allowed with banners, alerts or None and the sound on or off, denied, not asked, or only from `Carrier.app`), Open System Settings (always, to change those), Allow (when it has not been asked) and Send a test, which says why instead when macOS would swallow it. A click on a notification opens the window, on the epic when it is about one (the repo and issue travel in the notification's `userInfo`; the delegate is attached at launch so a click on an older notification works too). There are no General or Menu bar tabs since the Settings screen has these four: their models (`CarrierCore/GeneralTab.swift`, `CarrierCore/MenuBarStore.swift`) and views stay in the code, but nothing in the app changes Open at login, Ask before stopping Carrier (`stop.confirm`, on by default), the icon style, the animation or "Show epics in the menu" (`menu.iconStyle`, `menu.animate`, `menu.showEpics`) any more; they keep their defaults, or what was saved before. The Behavior tab (`Carrier/BehaviorTab.swift`, model in `CarrierCore/EngineConfig.swift`, footer rules in `CarrierCore/BehaviorSave.swift`) edits seven values of the config file in place, in three groups: Rhythm (`pollIntervalMinutes`, `logLevel`), Capacity (`limits.maxConcurrentEpics`, `limits.maxReviews`) and Agent runs (`limits.maxExecutionRetries`, `limits.maxExecutionHours`, with Unlimited, and `limits.githubCallTimeoutSeconds`). They are text fields that check the engine's rules as you type; a value equal to the engine's default is taken out of the file, and nothing else in the file is touched (the app never makes the file: without a JSON object there it says to run `carrier init`). The engine reads them only when it starts, so with Carrier stopped the button is Save, and with it running there are Save and restart and Save only; a restart (Stop, wait for the socket to go, Start Carrier) asks first only when epics are running and `stop.confirm` is on, and is off while Start Carrier lacks something. The Repos tab (`Carrier/ReposTab.swift`, model in `CarrierCore/RepoList.swift` and `CarrierCore/AvailableRepos.swift`) lists the repos in the config file's `repos` with a dot (green ok, red when GitHub refused it, grey when new or Carrier is stopped), the last check or the error and the epics each has, from the snapshot's `watched`, `epics` and `queue`. Add repo opens a picker with the repos the engine's gh login can push to, grouped by owner, with search; it asks Carrier for them with the `availableRepos` request (a capability in the hello: an engine without it, a stopped one or a GitHub failure each show their own message, and there is no typing a name by hand). A repo already watched shows ticked and off, and one whose folder name matches another watched or ticked repo is off with the reason. The ✕ on a row asks first, with what happens to the repo's epics (they stop where they are and continue if it is added again; nothing is deleted); the only repo cannot be removed. Changes are a draft until Save and use the Behavior tab's footer (Save, or Save and restart and Save only with Carrier running, and the same question before a restart that interrupts epics). The file is read again just before writing, a kept repo's entry is written back as it was (including anything the app does not show) and a new one is only its name, so the two tabs never overwrite each other's keys. With saved values the shell is never started. The `PATH` the engine will get is the detected one with node's directory first.

## Start Carrier

Start Carrier (the menu item, and a button in the window while Carrier is stopped) runs `node <carrier> --config <config path>` with that `PATH`, in its own session (`posix_spawn` with `POSIX_SPAWN_SETSID`, so quitting the app leaves Carrier running), stdin from `/dev/null` and stdout and stderr in `<root>/orchestrator/logs/app-start.log`, which it creates (the `orchestrator/` folder with mode 0700) when missing. It is never started on its own when the app opens, unless the person turned on "Start Carrier when the app opens" on the Engine tab's ready card (user default `engine.startOnOpen`, off by default): then, at the first state the monitor delivers after launch, the app starts Carrier once when that state is stopped and Start Carrier is enabled, never under `--fixture` (`shouldStartOnOpen`; the wiring in `AppDelegate` has no automated test, as it would start the real Carrier). When the control socket answers within 15 seconds the state becomes running (the next connect attempt shows it, within 3 seconds); when the process exits first, or 15 seconds pass without the socket, an alert shows the end of `app-start.log`. A second press while it starts does nothing. The decision and the command line are in `CarrierCore/StartCarrier.swift`; the spawn and the alert have no automated test. The self-test only checks the start (what it would run), as it does for Stop.

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
