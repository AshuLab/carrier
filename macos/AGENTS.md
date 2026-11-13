# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [macos-ui](../docs/macos-ui.md).

## Packages

A SwiftPM package for macOS 26 or later: `CarrierCore` (library), `Carrier` (the AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).

## Tests

The gated tests of Apple's recognizer (`AppleRecognizerTests`, with the clip `Tests/CarrierTests/Resources/hola-es.wav` made by `say`) and of FluidAudio's models (`FluidAudioRecognizerTests`, one run per entry: the Spanish clip, or an English one made with `say` (`hello-en.wav`) for the English-only models, gives text, and partial text first for the native ones, twice in a row with the same loaded model; no speech gives an empty final; a Parakeet folder with a file removed fails with its cause and is not downloaded again) run only with `CARRIER_IT_DICTATION` set; for FluidAudio it names a folder laid out as the app keeps its models (`<folder>/fluidaudio/<model>/<repository>`, e.g. `<folder>/fluidaudio/parakeet-tdt-v3/parakeet-tdt-0.6b-v3`); Whisper's (`WhisperKitRecognizerTests`, in the same folder under `<folder>/whisper/<model>/models/...`) give text from the Spanish clip for each of the four models and an empty final for no speech, and a copy of the tiny folder with a model file or the tokenizer removed fails with its cause and fetches nothing.

## Starting Carrier and the chat host

What the person sees: [lifecycle](../docs/macos/lifecycle.md).

The decision and the command line are in `CarrierCore/StartCarrier.swift`; the spawn and the alert have no automated test.
The decision, the command line and the notice are in `CarrierCore/StartChatHost.swift` (`chatHostAtOpen`, `startChatHostCommand`, `chatHostNotice`); `Carrier/ChatHostStarter.swift` reuses the engine's spawn and alert, and neither the wiring nor the views have an automated test.
The rule is tested; the replacement itself is not.
The sequence is tested against a scripted engine on a real socket (`EngineReplacementTests`).

## Epics

What the person sees: [the app shell](../docs/macos/app-shell.md#resume-card).

The words and the request are tested; the sheet, the "Resuming…" state and the layout have no automated test.

## File icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and the upstream licence text are in `Sources/CarrierCore/Resources/FileIcons` (about 12 KB; release pinned in `SOURCE.txt`, notice in `THIRD-PARTY-NOTICES.md`, line in About).
`build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when an icon or the licence text is missing from it.

## Settings

### Providers page

What the person sees: [settings-app](../docs/macos/settings-app.md#providers).

The rows are one pure function, `providersPage(_:config:chat:)` in `CarrierCore/ProvidersPage.swift`, tested in `ProvidersPageTests`; the view has no automated test.

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
The logic is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply, tested against the golden files in `WorktreeChoiceTests`) and `NewSessionModel` (tested with a fake host).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls are not.

## Usage

What the person sees: [usage](../docs/macos/usage.md).

The store holds `snapshot`, `isLoading`, `isRefreshing`, `error`, the filters (`metric`, `days`, `providerFilter`, `sourceFilter`, `searchText`) and `expandedProviders`.

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic is `CarrierCore/Dictation.swift` (the boundary and the registry), `DictationSession.swift`, `TentativeText.swift` and `DictationPresentation.swift`, tested with the scripted recognizer and capture of `ScriptedDictation.swift`.
`DictationController` holds the switch so both boxes read it.

## Embedded terminal

The embedded terminal UI chrome and triggers are not yet wired in `Carrier.app`, so `CarrierTerminalStore.shared` is dormant until the UI PR mounts the first surface ([the spec](../docs/specs/embedded-terminal-core.md), [ADR 0027](../docs/adr/0027-embedded-terminal-runs-in-process-with-ghosttykit.md)).

The pure domain model (`TerminalOwner`, `TerminalTab`, `TerminalPane`, `SplitNode`, `TerminalRegistry`, directory validation, URL policy), persistence (`TerminalWorkspaceFileStore` writing `<Carrier folder>/app/terminals.json` at `0600` without `envVars`), settings (`TerminalSettings` on `AppPreferences.terminal`) and light/dark palette profiles (`terminalAppearanceProfile` in `Theme.swift`) live in `CarrierCore` (`TerminalCore.swift`, `TerminalSplitTree.swift`, `TerminalPersistence.swift`, `TerminalSettings.swift`) and are tested in `TerminalCoreTests`.
`Carrier/TerminalHost.swift` (`CarrierTerminalStore`), `Carrier/TerminalProcessInspector.swift` (`GhosttyTerminalProcessInspector`), `Carrier/TerminalConfirmationCopy.swift` and `Carrier/CarrierTerminalView.swift` (`CarrierTerminalView`, `MountedTerminalSurface`) cache live `GhosttyKit` surfaces by `paneId`, hot-reload settings and handle batched off-main-thread process inspection and close confirmation; these are tested in `CarrierTerminalStoreTests`, while the live login-shell smoke test is gated behind `CARRIER_IT_TERMINAL`.
Session removal, authoritative pruning and app quit hooks live in `CarrierCore/ChatArchive.swift` (`SessionActions`), `CarrierCore/ChatSessions.swift` (`ChatSessionsPoller.onAuthoritativeSessionIds`), `Carrier/WindowController.swift` (`PanelModel`) and `Carrier/AppDelegate.swift` (`applicationShouldTerminate`, `applicationWillTerminate`), tested in `ChatSessionsTests` and `CarrierTerminalStoreTests`.
`libghostty-spm` (`GhosttyTerminal`) is linked by the `Carrier` target only, and `build-app.sh` / `scripts/check-app.sh` copy and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md` (`ThirdPartyNoticesTests`).
