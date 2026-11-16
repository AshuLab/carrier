# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [macos-ui](../docs/macos-ui.md).

## Packages

A SwiftPM package for macOS 26 or later: `CarrierCore` (library), `Carrier` (the AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).

## Tests

The gated tests of Apple's recognizer (`AppleRecognizerTests`, with the clip `Tests/CarrierTests/Resources/hola-es.wav` made by `say`), of FluidAudio's models (`FluidAudioRecognizerTests`: per entry the Spanish clip, or `hello-en.wav` for English-only ones, gives text, partial first for the native ones; no speech gives an empty final; a damaged Parakeet folder fails with its cause, never downloads again) and of Whisper's (`WhisperKitRecognizerTests`: text from the Spanish clip for each of the four models, an empty final for no speech, and a tiny folder with a model file or the tokenizer removed fails with its cause and fetches nothing) run only with `CARRIER_IT_DICTATION` set, naming a folder laid out as the app keeps its models (`<folder>/fluidaudio/<model>/<repository>`, e.g. `<folder>/fluidaudio/parakeet-tdt-v3/parakeet-tdt-0.6b-v3`; Whisper's under `<folder>/whisper/<model>/models/...`).
The embedded-terminal live shell integration test (`liveGhosttySurfaceSupportsSearchInterruptAndProcessDetection` in `CarrierTerminalStoreTests`) spawns a real Ghostty surface and shell process in an offscreen `NSWindow` and runs only when `CARRIER_IT_TERMINAL=1` is set.

## Starting Carrier and the chat host

What the person sees: [lifecycle](../docs/macos/lifecycle.md).

The decision and the command line are in `CarrierCore/StartCarrier.swift`; the spawn and the alert have no automated test.
The decision, the command line and the notice are in `CarrierCore/StartChatHost.swift` (`chatHostAtOpen`, `startChatHostCommand`, `chatHostNotice`); `Carrier/ChatHostStarter.swift` reuses the engine's spawn and alert, and neither the wiring nor the views have an automated test.
The sequence is tested against a scripted engine on a real socket (`EngineReplacementTests`).

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build; the differences are in [CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder).
The plist says which it is: `CarrierChannel` is `dev` or `release`, and `isDevBuild` (`Carrier/AppDelegate.swift`) reads it for the Dock badge and the toolbar mark in `PanelView`.
A dev build has no `SUFeedURL`, and `AppUpdater.start` does not start the updater without one.
`scripts/check-app.sh` asserts id, channel and missing feed for both; a new difference between the two goes into `build-app.sh` and into that script.

## Epics

What the person sees: [the app shell](../docs/macos/app-shell.md#resume-card).

The words and the request are tested; the sheet, the "Resuming…" state and the layout are not.

### The epic's Agent output

What the person sees: [the app shell](../docs/macos/app-shell.md#slices-and-findings-in-an-epics-log).

The rows, the words and the marks are two pure functions, `sliceCard(lane:)` in `CarrierCore/SliceCard.swift` (`SliceCardTests`) and `findingsCard(_:stage:round:)` in `CarrierCore/FindingsCard.swift` (`FindingsCardTests`, which also reads the golden epic reply); the views (`SliceCardView`, `FindingsCardView`) are checked only for their heights (`LaneHeaderTests`).
The session row's words are `sessionRowText` and `RoleIdentities` (`SessionRowTests`), and the epic's events become the chat's calls in `flowItems` (`EpicTranscriptAdapterTests`).

## File icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and the upstream licence text are in `Sources/CarrierCore/Resources/FileIcons` (about 12 KB; release pinned in `SOURCE.txt`, notice in `THIRD-PARTY-NOTICES.md`, line in About).
`build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when an icon or the licence text is missing from it.

## Settings

### Providers page

What the person sees: [settings-app](../docs/macos/settings-app.md#providers).

The rows are one pure function, `providersPage(_:config:chat:)` in `CarrierCore/ProvidersPage.swift`, tested in `ProvidersPageTests`; the view is not.

#### Sign in and Update

The buttons have no automated test.

#### `providers.json`

Tested in `ProvidersFileTests` and `FixtureServerTests`.

#### Account editor

The views have no automated test.

### Sessions page

What the person sees: [settings](../docs/macos/settings.md#sessions-page).

The functions are tested in `SessionAgesTests`; the view has no automated test.

### Health tab

What the person sees: [settings-legacy](../docs/macos/settings-legacy.md#health-tab).

The rows are one pure function, `healthSections(host:facts:)` in `CarrierCore/HealthRows.swift`, tested in `HealthRowsTests`; the view has no automated test.
The decoding, the outcomes, the command, the store and the rows are tested (`DoctorChecksTests`, `HealthRowsTests`); the process runner and the view have no automated test.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`showRepos`, `loadRepos`, `repoRows`, `choose(repo:)`) and `githubRepoRows`, tested with a fake host in `NewSessionTests`.
The rule, the host client's decoding and the draft are tested (`HealthTests`, `ChatHostTests`, `NewSessionTests`); the wiring in `AppDelegate` has no automated test.
The list, the script and the opener are tested in `HealthFixTests` (a replaceable opener, like `ContinueInTerminalTests`, and hostile values that run nothing); the button has no automated test.
The logic is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply, tested on the golden files in `WorktreeChoiceTests`) and `NewSessionModel` (tested with a fake host).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls not.

## Usage

What the person sees: [usage](../docs/macos/usage.md).

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic is `CarrierCore/Dictation.swift` (the boundary and the registry), `DictationSession.swift`, `TentativeText.swift` and `DictationPresentation.swift`, tested with the recognizer and capture of `ScriptedDictation.swift`.
`DictationController` holds the switch both boxes read.
The page is `Carrier/DictationTab.swift`, a list of one view per group (`DictationGroup`, `GlobalDictationGroup`, `CleanupGroup`, `SpeechModelsGroup`, `StorageGroup`; a new group is a file and a line there), and `reset(.dictation)` restores the keys in `AppPreferences.keys(of:)`, one per line (Dictate in any app on; Cleanup off, no server, no model, default prompt); the views are untested (`SettingsPageTests` and `DictationSettingsTests` hold the rules).

### Global dictation

See [dictation](../docs/macos/dictation.md#global-dictation). The machine is `CarrierCore/GlobalDictation.swift` (`GlobalDictationTests`, real session, scripted recognizer).
`Carrier/GlobalDictationController.swift` wires it to `GlobalHotKey`, `DictationWidget` and `ClipboardPaste` (`ClipboardPasteTests`, own pasteboard); keys, panel and real ⌘V untested.
Box or widget: `CarrierCore/DictationRoute.swift` (`DictationRouteTests`); the box side is `MessageBox.dictateRequest` (`MessageBoxDictationTests`).

### Cleanup

`CarrierCore/DictationCleanup.swift` (the `TextModelClient` port, `CleanupRun`; `CleanupRunTests`, scripted client) and `LocalModelClient.swift` (loopback HTTP; `LocalModelClientTests`, stub on a real socket); the group is `Carrier/CleanupController.swift` and `CleanupGroup.swift`, untested.

## Embedded terminal

What the person sees: [terminal](../docs/macos/terminal.md).

Pure domain rules (`TerminalCore.swift`, `TerminalSplitTree.swift`, `TerminalPersistence.swift`, `TerminalSettings.swift`, `TerminalZshBottomPromptShim.swift`) live in `CarrierCore` and are tested in `TerminalCoreTests` and `TerminalZshBottomPromptShimTests`.
Validated Continue in Terminal launch construction (`EmbeddedResumeLaunch`, `embeddedResumeLaunch`) lives in `CarrierCore/ContinueInTerminal.swift` and is tested in `ContinueInTerminalTests`.
The AppKit runtime (`Carrier/TerminalHost.swift`, `Carrier/TerminalAppearance.swift`, `Carrier/TerminalProcessInspector.swift`, `Carrier/TerminalConfirmationCopy.swift`, `Carrier/CarrierTerminalView.swift`) owns the `paneId`-keyed `GhosttyKit` surface cache, live settings reload, `ZDOTDIR` bottom-prompt preparation, `⌘K` scrollback clear and close confirmation.
The sidebar, overview, workspace, tab bar, settings page, menu bar, middle-click close and drawer views are the `Terminal*View.swift` files, `MainMenu.swift`, `MiddleClickModifier.swift`, `ContinueInTerminalView.swift`, `SessionSectionsView.swift`, `EpicView.swift` and `PanelView.swift`.
Window selection and drawer state live in `CarrierCore/WindowShell.swift`, tested with layout, settings, shortcuts and middle-click in `TerminalWorkspaceLayoutTests`, `SettingsPageTests`, `MainMenuShortcutsTests`, `MiddleClickModifierTests` and `WindowShellTests`.
Session deletion cleanup and process-activity termination guards connect through `CarrierCore/ChatArchive.swift`, `CarrierCore/ChatSessions.swift`, `Carrier/WindowController.swift` and `Carrier/AppDelegate.swift` (poller and store tested, view wiring not).
`libghostty-spm` (`GhosttyTerminal`) is linked by the `Carrier` target only, and `build-app.sh` / `scripts/check-app.sh` bundle and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md` (`ThirdPartyNoticesTests`).
