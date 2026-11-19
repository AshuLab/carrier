# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [macos-ui](../docs/macos-ui.md).

## Packages

A SwiftPM package for macOS 26 or later: `CarrierCore` (library), `Carrier` (the AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).

## Tests

The gated recognizer tests (`{Apple,FluidAudio,WhisperKit}RecognizerTests`) run only with `CARRIER_IT_DICTATION` naming a folder laid out as the app keeps its models ([layout](../docs/macos/dictation.md#speech-models)).
The live shell test (`liveGhosttySurfaceSupportsSearchInterruptAndProcessDetection`, `CarrierTerminalStoreTests`) spawns a real Ghostty surface offscreen, only with `CARRIER_IT_TERMINAL=1`.

## Starting Carrier and the chat host

What the person sees: [lifecycle](../docs/macos/lifecycle.md).

The decision and command line are in `CarrierCore/StartCarrier.swift` (spawn and alert untested).
The decision, command line and notice are in `CarrierCore/StartChatHost.swift` (`chatHostAtOpen`, `startChatHostCommand`, `chatHostNotice`); `Carrier/ChatHostStarter.swift` reuses the engine's spawn and alert (wiring, views untested).
The sequence is tested on a real socket against a scripted engine (`EngineReplacementTests`).

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build; the differences are in [CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder).
The plist says which it is: `CarrierChannel` is `dev` or `release`, and `isDevBuild` (`Carrier/AppDelegate.swift`) reads it for the Dock badge and the toolbar mark in `PanelView`.
A dev build has no `SUFeedURL`, and `AppUpdater.start` does not start the updater without one.
`scripts/check-app.sh` asserts id, channel and missing feed for both; a new difference goes into `build-app.sh` and that script.

## Epics

What the person sees: [the app shell](../docs/macos/app-shell.md#resume-card).

The words and the request are tested; the sheet, its "Resuming…" state and layout are not.

### The epic's Agent output

What the person sees: [the app shell](../docs/macos/app-shell.md#slices-and-findings-in-an-epics-log).

The rows, words and marks are two pure functions, `sliceCard(lane:)` in `CarrierCore/SliceCard.swift` (`SliceCardTests`) and `findingsCard(_:stage:round:)` in `CarrierCore/FindingsCard.swift` (`FindingsCardTests`, which also reads the golden epic reply); the views are checked only for their heights (`LaneHeaderTests`).
The session row's words are `sessionRowText` and `RoleIdentities` (`SessionRowTests`); the epic's events become the chat's calls in `flowItems` (`EpicTranscriptAdapterTests`).

## Icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and the upstream licence text are in `CarrierCore/Resources/FileIcons` (release pinned in `SOURCE.txt`, notice in `THIRD-PARTY-NOTICES.md`, line in About).
`build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when an icon or the licence text is missing from it.
The interface's icons are `TablerIcon` (`TablerIconsTests`), drawn by `Glyph`, checked the same.

## Settings

The window is `Carrier/SettingsWindow.swift`, a page's shared pieces `SettingsTabs.swift` ([settings](../docs/macos/settings.md)); `SettingsIndexDriftTests` keeps the search's `settingsIndex` in step with them.

### Providers page

What the person sees: [settings-app](../docs/macos/settings-app.md#providers).

The rows are `providersPage(_:config:chat:)` and the list's `providersDirectory` (`CarrierCore/ProvidersPage.swift`, `ProvidersDirectory.swift`; `Providers{Page,Directory}Tests`); views untested; `providers.json` is in `ProvidersFileTests` and `FixtureServerTests`.

### Sessions page

What the person sees: [settings](../docs/macos/settings.md#sessions-page).

The functions are tested in `SessionAgesTests`; the view is untested.

### Health tab

What the person sees: [settings-health](../docs/macos/settings-health.md#health-tab).

The rows are one pure function, `healthSections(host:facts:)` (`CarrierCore/HealthRows.swift`, `HealthRowsTests`); the view is untested.
The decoding, outcomes, command and store are tested (`DoctorChecksTests`), not the process runner.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`showRepos`, `loadRepos`, `repoRows`, `choose(repo:)`) and `githubRepoRows`, tested with a fake host in `NewSessionTests`.
The rule, the host client's decoding and the draft are tested (`HealthTests`, `ChatHostTests`, `NewSessionTests`); the `AppDelegate` wiring is not.
The list, the script and the opener are tested in `HealthFixTests` (replaceable opener, hostile values that run nothing); the button is untested.
The logic is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply, tested on golden files in `WorktreeChoiceTests`) and `NewSessionModel` (tested with a fake host).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls not.
A subagent's row is `Subagent` (`CarrierCore/ChatToolGroups.swift`), built by `chatFeed` from `task` events (`ChatConversationTests`, `SubagentRowTests`).

## Usage

What the person sees: [usage](../docs/macos/usage.md).

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic is `CarrierCore/Dictation.swift` (boundary and registry), `DictationSession.swift`, `TentativeText.swift` and `DictationPresentation.swift`, tested with `ScriptedDictation.swift`; `DictationController` holds the switch both boxes read.
Readiness: `speechModelStep`, `ModelSlot`, run by `DictationController.warmUp` (`DictationReadinessTests`); `DictationSession.run` captures before `prepare`.
Firm and tentative: `DictationEvent.partial`, `TentativeText.tentativeRange`, `GlobalDictation.split` (`TentativeTextTests`).
The page is `Carrier/DictationTab.swift` (a first screen, six `DictationScreen`s); `dictationReadiness` words its card (`DictationReadinessModelTests`); `reset(.dictation)` restores `AppPreferences.keys(of:)`; views untested.

### Global dictation

See [dictation](../docs/macos/dictation.md#global-dictation). The machine is `CarrierCore/GlobalDictation.swift` (`GlobalDictationTests`, scripted recognizer; Hold is `.up`).
Shortcut and activation: `CarrierCore/DictationShortcut.swift` (`recordShortcut`, `DictationShortcutTests`) and the recorder row in `GlobalDictationGroup`, untested.
`CarrierCore/PasteDecision.swift` (`pasteDecision`, `PasteDecisionTests`) picks paste or copy from `Carrier/FocusedField.swift`, which reads the focus (untested).
`Carrier/GlobalDictationController.swift` wires it to `GlobalHotKey`, `DictationWidget` and `ClipboardPaste` (`ClipboardPasteTests`, own pasteboard); the rest untested.
Box or widget: `CarrierCore/DictationRoute.swift` (`DictationRouteTests`); the box side is `MessageBox.dictateRequest`.
Sounds: `CarrierCore/DictationSounds.swift` (`DictationSoundsTests`); the group and player untested.
Widget look and place: `CarrierCore/DictationWidgetLook.swift` (`DictationPresentationTests`); `DictationWidget` untested.

### History

See [dictation](../docs/macos/dictation.md#history).
`CarrierCore/DictationRecords.swift` (`DictationRecordsTests`), fed by `DictationSession.take`.
Audio: `DictationRecords` (fake clock), `DictationAudio.swift`; `AudioPlayerView` untested.

### Statistics

See [dictation](../docs/macos/dictation.md#statistics). Counters: `DictationRecords`; figures, hours, week and records: `DictationStatistics.swift` (`DictationStatisticsTests`); `StatisticsGroup` untested.

### Cleanup

`CarrierCore/DictationCleanup.swift` (the `TextModelClient` port, `CleanupRun`; `CleanupRunTests`, scripted client) and `LocalModelClient.swift` (`LocalModelClientTests`, stub socket); the group is `Carrier/CleanupController.swift` and `CleanupGroup.swift`, untested.
In the boxes and the widget: the `.cleaning` state of `DictationSession` (`DictationSessionTests`, `GlobalDictationTests`).

## Embedded terminal

What the person sees: [terminal](../docs/macos/terminal.md).

Pure rules (`Terminal{Core,SplitTree,Persistence,Settings,ZshBottomPromptShim}.swift`) live in `CarrierCore` (`TerminalCoreTests`, `TerminalZshBottomPromptShimTests`).
Continue in Terminal launch construction (`EmbeddedResumeLaunch`, `embeddedResumeLaunch`) is in `CarrierCore/ContinueInTerminal.swift` (`ContinueInTerminalTests`).
The AppKit runtime (`Carrier/Terminal{Host,Appearance,ProcessInspector,ConfirmationCopy}.swift`, `Carrier/CarrierTerminalView.swift`) owns the `paneId`-keyed `GhosttyKit` surface cache, live settings reload, `ZDOTDIR` bottom-prompt preparation, `⌘K` scrollback clear and close confirmation.
The sidebar, overview, workspace, tab bar, settings page, menu bar, middle-click close and drawer views are the `Terminal*View.swift` files, `MainMenu.swift`, `MiddleClickModifier.swift`, `ContinueInTerminalView.swift`, `SessionSectionsView.swift`, `EpicView.swift` and `PanelView.swift`.
Window selection and drawer state live in `CarrierCore/WindowShell.swift`, tested with layout, shortcuts and middle-click in `TerminalWorkspaceLayoutTests`, `MainMenuShortcutsTests`, `MiddleClickModifierTests` and `WindowShellTests`.
Session deletion cleanup and process-activity guards connect through `CarrierCore/ChatArchive.swift`, `ChatSessions.swift`, `Carrier/WindowController.swift` and `AppDelegate.swift` (poller and store tested, view wiring not).
`libghostty-spm` (`GhosttyTerminal`) is linked by the `Carrier` target only; `build-app.sh` and `scripts/check-app.sh` bundle and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md` (`ThirdPartyNoticesTests`).
