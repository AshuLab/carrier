# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [ui](../docs/ui.md).

## Packages

A SwiftPM package for macOS 26+: `CarrierCore` (library), `Carrier` (AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).

## Tests

The gated recognizer tests (`{Apple,FluidAudio,WhisperKit}RecognizerTests`) run only with `CARRIER_IT_DICTATION` naming a folder laid out as the app keeps its models ([layout](../docs/macos/dictation.md#speech-models)).
The live shell test (`CarrierTerminalStoreTests`) spawns a real Ghostty surface offscreen, only with `CARRIER_IT_TERMINAL=1`.
A test finds `Tests/Fixtures`, `Sources` and the repository root with `testPaths()` (`TestPaths.swift` in each test target), never by climbing from `#filePath`, so a file can move to any depth.
A test that scans the sources reads every subfolder and fails when it scans fewer files than a minimum (`swiftFiles(under:minimum:)`), and finds a source file by its name, not its path.

## Starting Carrier and the chat host

What the person sees: [lifecycle](../docs/macos/lifecycle.md).

The decision and command line are in `CarrierCore/Lifecycle/StartCarrier.swift`; the chat host's, with its notice, in `StartChatHost.swift`. The start itself (one at a time, `engine.json`, the wait for the socket or the exit, the retry when a tool is not found, the log's tail) is `CarrierStart` and `CarrierLauncher` (`CarrierLauncherTests`, fake `ProcessRunner` and `HostSocket`); `Carrier/Platform/SystemProcessRunner.swift` does the spawn, and the alert stays in `StartController`. `Carrier/ChatHostStarter.swift` reuses the launcher and shows its alert. Tested on a real socket with a scripted engine (`EngineReplacementTests`).
`CarrierCore/EngineLink.swift` reads the engine ([how](../docs/macos/app-shell.md#how-the-app-reads-the-engine); `EngineLinkTests`).

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build ([CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder)).
`CarrierChannel` in the plist is `dev` or `release`; `isDevBuild` (`Carrier/App/AppDelegate.swift`) reads it, and a dev build has no `SUFeedURL`, so `AppUpdater.start` does not start the updater.
`scripts/check-app.sh` asserts id, channel and missing feed for both; a new difference goes into `build-app.sh` and that script.

## Epics

What the person sees: [the app shell](../docs/macos/app-shell.md#resume-card). The resume words and request are tested; the sheet, its "Resuming…" state and layout not.

### The epic's Agent output

What the person sees: [the app shell](../docs/macos/app-shell.md#slices-and-findings-in-an-epics-log).

The rows, words and marks are two pure functions, `sliceCard(lane:)` (`SliceCard.swift`, `SliceCardTests`) and `findingsCard(_:stage:round:)` (`FindingsCard.swift`, `FindingsCardTests`, which also reads the golden epic reply); the views only for their heights (`LaneHeaderTests`).
The session row's words are `sessionRowText` and `RoleIdentities`; the epic's events become the chat's calls in `flowItems` (`EpicTranscriptAdapterTests`).

## Icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and upstream licence are in `CarrierCore/Resources/FileIcons`; `build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when it lacks an icon or the licence.
Interface icons: `AppIcon` in three sets (`IconSets.swift`, `IconsTests`), drawn by `Glyph`.

## Settings

The window is `SettingsWindow.swift`, a page's pieces `Carrier/UI/` ([settings](../docs/macos/settings.md)); `SettingsIndexDriftTests` keeps the search's `settingsIndex` in step with them.
The Pieces gallery under `--fixture` (`Features/Settings/PiecesGallery*.swift`, its data `CarrierCore/Fixtures/PiecesGalleryData.swift`) is looked at, not tested; `scripts/check-structure.sh` fails for a piece with no `GalleryEntry` ([ui](../docs/ui.md#the-gallery)).
Where each page lives in the code and what is tested (Providers, Projects, Agents, Sessions, Health): [settings](../docs/macos/settings.md#where-the-pages-live-in-the-code).

### Preferences

The keys, their types and defaults are `design/preferences.json`, generated into `CarrierCore/Settings/Preferences.generated.swift` (`pnpm design`).
Views read and write a preference with `@AppStorage(Preference.<name>)`, the initializers of `Carrier/UI/Modifiers/PreferenceStorage.swift` (`PreferenceStorageTests`); code that is not a view uses `AppPreferences`.
`CarrierCore/Settings/` is the only place that touches user defaults: `scripts/check-structure.sh` fails on `UserDefaults.standard` or a literal `forKey:` anywhere else, and lists the state it leaves out (the per-session `chat.*.<id>` keys).
`PreferenceKey` is named `CarrierCore.PreferenceKey` in a file that imports SwiftUI, which has a protocol of that name.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`choose(_:)`, `choose(repo:)`, `choose(folder:)`, `choose(newProject:)`, `watch`), which the shared `AddProjectSheet.swift` drives in `ProjectSheetMode.newSession` (`NewSessionTests`); `AppDelegate`'s wiring is untested.
The health fix list, script and opener are tested in `HealthFixTests` (hostile values run nothing); the button not.
The worktree choice is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply; `WorktreeChoiceTests`, golden files).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls not.
`CarrierCore/ChatLink.swift` reads the chat host ([how](../docs/macos/sessions.md#how-the-app-reads-the-chat-host); `ChatLinkTests`).
A subagent's row is `Subagent` (`Subagent.swift`), built by `chatFeed` from `task` events (`SubagentRowTests`).

## Usage

What the person sees: [usage](../docs/macos/usage.md).

## Platform adapters

Each thing only macOS can do is a protocol of `CarrierCore/Platform/` implemented in `Carrier/Platform/`, and `scripts/check-structure.sh` fails when a file outside `Carrier/Platform/` imports Ghostty, FluidAudio, WhisperKit, Speech, AVFoundation, IOKit, Carbon, ApplicationServices, UserNotifications, Sparkle, MetricKit or ServiceManagement, or calls a symbol with the prefix `AX`, `SPU`, `AVAudio`, `IOPM`, `UN`, `MX` or `CGEvent`.
`KeepAwakeAssertion` (`SystemKeepAwakeAssertion`, IOKit), `GlobalShortcut` (`SystemGlobalShortcut`, Carbon), `Clipboard` (`SystemClipboard`), `Updater` (`AppUpdater`, Sparkle), `NotificationCentre` and `NotificationPermissionReader` (`SystemNotificationCentre`): the models over them take the protocol (`KeepAwakeControllerTests` and `GlobalDictationControllerTests` with a fake; one test of the real assertion, `SystemKeepAwakeAssertionTests`).
The app's controllers are built where they are used: `KeepAwakeController.shared` in `KeepAwakeController+App.swift`, `GlobalDictationController.shared`, and the views take the protocol from `SettingsWindow` and `PanelView`.

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic: `CarrierCore/Dictation.swift`, `DictationSession.swift`, `TentativeText.swift`, `DictationPresentation.swift`, tested with `ScriptedDictation.swift`; `DictationController` holds the switch both boxes read; `LaunchPhases`: after the first frame.
Readiness: `speechModelStep`, `ModelSlot`, run by `DictationController.warmUp`; `DictationSession.run` captures before `prepare`.
The platform it needs is protocols in `CarrierCore/Platform/` (`Recognizer`, `AudioCapture`, `BatchTranscriber`, `ModelDownloader`, `TextModelClient`, `AudioPlayer`, `AccessibilityTrust`; `TerminalOpener` for Terminal), implemented in `Carrier/Platform/`; the models over them are `AudioPlayback` (`AudioPlaybackTests`) and `AccessibilityState` (`AccessibilityStateTests`), tested with a fake.
Firm and tentative: `DictationEvent.partial`, `TentativeText.tentativeRange`, `GlobalDictation.split`.
The page is `Carrier/Features/Dictation/DictationTab.swift` (`reset(.dictation)` restores the keys the schema (`design/preferences.json`) gives the page); views untested.

### Global dictation

See [dictation](../docs/macos/dictation.md#global-dictation). The machine is `CarrierCore/GlobalDictation.swift` (`GlobalDictationTests`, scripted recognizer; Hold is `.up`); shortcut `DictationShortcut.swift`; paste or copy `PasteDecision.swift`; box or widget `DictationRoute.swift` (box side `MessageBox.dictateRequest`).
`Carrier/Features/Dictation/GlobalDictationController.swift` wires a `GlobalShortcut`, `DictationWidget` and a `Clipboard` (fakes in `GlobalDictationControllerTests`; the real ones are `GlobalHotKey` and `SystemClipboard`, `SystemClipboardTests`); views untested.

### History, statistics and cleanup

[History](../docs/macos/dictation.md#history) and [statistics](../docs/macos/dictation.md#statistics): `DictationRecords.swift` (fake clock, fed by `DictationSession.take`; `load()` is async), `DictationAudio.swift`, `DictationStatistics.swift`; the player is untested.
Cleanup: `DictationCleanup.swift` (`TextModelClient`, `CleanupRun`) and `LocalModelClient.swift`; the `.cleaning` state of `DictationSession` is in `DictationSessionTests`; `CleanupController.swift`, `CleanupGroup.swift` untested.

## Embedded terminal

Where it lives in the code and what is tested: [terminal](../docs/macos/terminal.md#where-it-lives-in-the-code).
