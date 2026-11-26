# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [ui](../docs/ui.md).

## Packages and the tree

A SwiftPM package for macOS 26+: `CarrierCore` (library), `CarrierUI` (library, the pieces), `Carrier` (AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).
A dependency points down only ([ADR 0052](../docs/adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md)); the areas are Lifecycle, Sessions, Chat, Epics, Projects, Terminal, Dictation, Usage, KeepAwake, Updates, Health and Settings.

- `CarrierCore/<Area>/`: clients, rules, what a view shows, with no SwiftUI or AppKit; `Platform/` has the protocols for what only the machine does, `Connection/` the sockets, `Theme/`, `Copy/` and `Settings/` the generated tokens, words and preference keys (`pnpm design`), `Support/` and `Fixtures/` what is shared.
- `Carrier/App/`: the composition root (`AppDelegate`, `MainMenu`, `PanelModel`, the window), where the controllers are built.
- `Carrier/Features/<Area>/`: thin views and the models only they use.
- `Carrier/Platform/`: the implementations of `CarrierCore/Platform/` and every framework import.
- `CarrierUI/` (its own target, depends on `CarrierCore` only): the pieces of [ui](../docs/ui.md), which cannot name a type of `Carrier/Features/`, `Carrier/App/` or `Carrier/Platform/`: the compiler refuses it. A piece is `public` (its type, its initializer and what the app calls); the words it says come from `CarrierCore` through `Copy`, so it ships no resource bundle of its own.
  Text size and accent reach every view through the environment, never a static: `.scaledFont(...)` for a size, `.tint` or `pieceTheme.accent` for the accent, set by `.themed()` at each window's root; `Font.scaled` and the static accent are gone.

Where a file goes: a Settings page that changes one area lives in that area, one about Carrier's config or the app as a whole in `Features/Settings/`; a file that needs a platform framework and also draws is split in two; a test goes to the folder of what it tests.
No view starts a process, reads or writes a file or opens a socket: it asks a model.
What each area does is in its doc under `docs/macos/` ([the list](README.md#what-the-app-does)), and the code map and tests of lifecycle, epics, dictation, terminal and keep awake are in the section of their doc called "Where it lives in the code" (keep awake: "Code and tests"):
[lifecycle](../docs/macos/lifecycle.md) (Lifecycle), [app-shell](../docs/macos/app-shell.md) (App), [sessions](../docs/macos/sessions.md), [chat](../docs/macos/chat.md), [new-session](../docs/macos/new-session.md), [epics](../docs/macos/epics.md), [projects](../docs/macos/projects.md), [terminal](../docs/macos/terminal.md), [dictation](../docs/macos/dictation.md), [usage](../docs/macos/usage.md), [keep-awake](../docs/macos/keep-awake.md), [settings](../docs/macos/settings.md) with [Health](../docs/macos/settings-health.md).

## Tests

The gated recognizer tests (`{Apple,FluidAudio,WhisperKit}RecognizerTests`) run only with `CARRIER_IT_DICTATION` naming a folder laid out as the app keeps its models ([layout](../docs/macos/dictation.md#speech-models)).
The live shell test (`CarrierTerminalStoreTests`) spawns a real Ghostty surface offscreen, only with `CARRIER_IT_TERMINAL=1`.
A test finds `Tests/Fixtures`, `Sources` and the repository root with `testPaths()` (`Tests/CarrierCoreTests/TestPaths.swift` and `Tests/CarrierTests/TestPaths.swift`), never by climbing from `#filePath`, so a file can move to any depth.
A test that scans the sources reads every subfolder and fails when it scans fewer files than a minimum (`swiftFiles(under:minimum:)`), and finds a source file by its name, not its path.

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build ([CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder)).
`CarrierChannel` in the plist is `dev` or `release`; `isDevBuild` (`Carrier/App/AppDelegate.swift`) reads it, and a dev build has no `SUFeedURL`, so `AppUpdater.start` does not start the updater.
`scripts/check-app.sh` asserts id, channel and missing feed for both; a new difference goes into `build-app.sh` and that script.

## Icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and upstream licence are in `CarrierCore/Resources/FileIcons`; `build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when it lacks an icon or the licence.
Interface icons: `AppIcon` in three sets (`IconSets.swift`, `IconsTests`), drawn by `Glyph`.

## Settings

The window is `SettingsWindow.swift`, a page's pieces `CarrierUI/` ([settings](../docs/macos/settings.md)); `SettingsIndexDriftTests` keeps the search's `settingsIndex` in step with them.
The Pieces gallery under `--fixture` (`Carrier/Features/Settings/PiecesGalleryView.swift` and its siblings, its data `CarrierCore/Fixtures/PiecesGalleryData.swift`) is looked at, not tested; `scripts/check-structure.sh` fails for a piece with no `GalleryEntry` ([ui](../docs/ui.md#the-gallery)).
Where each page lives in the code and what is tested (Providers, Projects, Agents, Sessions, Health): [settings](../docs/macos/settings.md#where-the-pages-live-in-the-code).

### Preferences

The keys, their types and defaults are `design/preferences.json`, generated into `CarrierCore/Settings/Preferences.generated.swift` (`pnpm design`).
Views read and write a preference with `@AppStorage(Preference.<name>)`, the initializers of `CarrierUI/Modifiers/PreferenceStorage.swift` (`PreferenceStorageTests`); code that is not a view uses `AppPreferences`.
`CarrierCore/Settings/` is the only place that touches user defaults: `scripts/check-structure.sh` fails on `UserDefaults.standard` or a literal `forKey:` anywhere else, and lists the state it leaves out (the per-session `chat.*.<id>` keys).
`PreferenceKey` is named `CarrierCore.PreferenceKey` in a file that imports SwiftUI, which has a protocol of that name.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`choose(_:)`, `choose(repo:)`, `choose(folder:)`, `choose(newProject:)`, `watch`), which the shared `AddProjectSheet.swift` drives in `ProjectSheetMode.newSession` (`NewSessionTests`); `AppDelegate`'s wiring is untested.
The health fix list, script and opener are tested in `HealthFixTests` (hostile values run nothing); the button not.
The worktree choice is `CarrierCore/Projects/WorktreeChoice.swift` (pure values over the `workspace` reply; `WorktreeChoiceTests`, golden files).

## Conversation

What the person sees: [sessions](../docs/macos/chat.md#conversation).

The words are tested; the Finder and pasteboard calls not.
`CarrierCore/Connection/ChatLink.swift` reads the chat host ([how](../docs/macos/sessions.md#how-the-app-reads-the-chat-host); `ChatLinkTests`).
A subagent's row is `Subagent` (`Subagent.swift`), built by `chatFeed` from `task` events (`SubagentRowTests`).

## Platform adapters

Each thing only macOS can do is a protocol of `CarrierCore/Platform/` implemented in `Carrier/Platform/`, and `scripts/check-structure.sh` fails when a file outside `Carrier/Platform/` imports Ghostty, FluidAudio, WhisperKit, Speech, AVFoundation, IOKit, Carbon, ApplicationServices, UserNotifications, Sparkle, MetricKit or ServiceManagement, or calls a symbol with the prefix `AX`, `SPU`, `AVAudio`, `IOPM`, `UN`, `MX` or `CGEvent`.
`KeepAwakeAssertion` (`SystemKeepAwakeAssertion`, IOKit), `GlobalShortcut` (`SystemGlobalShortcut`, Carbon), `Clipboard` (`SystemClipboard`), `Updater` (`AppUpdater`, Sparkle), `NotificationCentre` and `NotificationPermissionReader` (`SystemNotificationCentre`): the models over them take the protocol (`KeepAwakeControllerTests` and `GlobalDictationControllerTests` with a fake; one test of the real assertion, `SystemKeepAwakeAssertionTests`).
The app's controllers are built where they are used: `KeepAwakeController.shared` in `KeepAwakeController+App.swift`, `GlobalDictationController.shared`, and the views take the protocol from `SettingsWindow` and `PanelView`.

## Embedded terminal

Where it lives in the code and what is tested: [terminal](../docs/macos/terminal.md#where-it-lives-in-the-code).
