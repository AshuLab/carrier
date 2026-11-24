# macos

The code map of `Carrier.app`: where each area lives in the code and what is tested.
How to build, test and run it is in [README.md](README.md); what each area does for the person is in `docs/macos/` ([the list](README.md#what-the-app-does)); how it looks is in [macos-ui](../docs/macos-ui.md).

## Packages

A SwiftPM package for macOS 26+: `CarrierCore` (library), `Carrier` (AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing).

## Tests

The gated recognizer tests (`{Apple,FluidAudio,WhisperKit}RecognizerTests`) run only with `CARRIER_IT_DICTATION` naming a folder laid out as the app keeps its models ([layout](../docs/macos/dictation.md#speech-models)).
The live shell test (`CarrierTerminalStoreTests`) spawns a real Ghostty surface offscreen, only with `CARRIER_IT_TERMINAL=1`.

## Starting Carrier and the chat host

What the person sees: [lifecycle](../docs/macos/lifecycle.md).

The decision and command line are in `CarrierCore/StartCarrier.swift` (spawn and alert untested); the chat host's, with its notice, in `StartChatHost.swift`, and `Carrier/ChatHostStarter.swift` reuses the engine's spawn and alert. Tested on a real socket with a scripted engine (`EngineReplacementTests`).
`CarrierCore/EngineLink.swift` reads the engine ([how](../docs/macos/app-shell.md#how-the-app-reads-the-engine); `EngineLinkTests`).

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build ([CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder)).
`CarrierChannel` in the plist is `dev` or `release`; `isDevBuild` (`Carrier/AppDelegate.swift`) reads it, and a dev build has no `SUFeedURL`, so `AppUpdater.start` does not start the updater.
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

The window is `Carrier/SettingsWindow.swift`, a page's shared pieces `SettingsTabs.swift` ([settings](../docs/macos/settings.md)); `SettingsIndexDriftTests` keeps the search's `settingsIndex` in step with them.

### Providers page

What the person sees: [settings-app](../docs/macos/settings-app.md#providers).

The rows are `providersPage(_:config:chat:)` and `providersDirectory` (`ProvidersPage.swift`, `ProvidersDirectory.swift`; `Providers{Page,Directory}Tests`); views untested; `providers.json` is in `ProvidersFileTests` and `FixtureServerTests`.

### Projects file

`projects.json` is read, checked, edited and added to by `CarrierCore/ProjectsFile.swift` (`ProjectsFileTests`, `ProjectsListTests`); the same rules as `src/config/projects.ts` are run over `Tests/Fixtures/projects.json` by `ContractTests`.

### Projects page

What the person sees: [settings](../docs/macos/settings.md#projects-page).

The pure rules live in `CarrierCore` (`ProjectsList`, `ProjectSheet`, `ProjectIcon`, `ProjectIconStore`, `ProjectActions`, `ProjectDeletion`, `ProjectWatch`, `ProjectWorktrees`, `ProjectDisk`, `WorkspaceSources`, `ProjectsFile`), each with a `*Tests` of its name; `ProjectsModel` follows the file (another process's write, a file that does not match, refused folders) and `ProjectsModel.shared` is the app's one reading of it.
Gotchas:
- An edit changes only its own key: `setDefault` writes `defaults` (`applyingProjectDefaultsEdit`, read by `NewSessionModel.projectDefaults`), `setHidden` `hidden`, `locate` only `path`, `remove` only the entry and its image copy.
- The Carrier switch edits the Watching page's config (`saveWatch` over `applyingRepos`/`saveConfig`).
- Deleting what Carrier made goes to the Trash (`moveProjectToTrash`, tried by hand) after `projectDeletionCheck`.
- `projectFolderRefusal` shares `Tests/Fixtures/project-folder.json` with `src/chat/folder.ts`.
- `projectIdentity`/`projectTile` (`ProjectIcon.swift`) give the tile and title wherever a project shows; `retitled(_:projects:)` (`ChatSessions.swift`) does it for the sidebar.
- The host requests are behind the `projects` capability (`ChatHost.swift`, `ChatHostTests`); the fixture host answers with the `chat-new-project.json` and `chat-project-*.json` goldens, and `--fixture` writes its projects in `FixtureServer.writeProjects`.
- The sheet's New session mode (`ProjectSheetMode.newSession`) only fills the plan (`NewSessionModel.choose(_:)`).
- Views (`Carrier/ProjectsTab.swift`, `AddProjectSheet.swift`) are untested, only drawn by `--selftest`.

### Agents page

What the person sees: [settings-carrier](../docs/macos/settings-carrier.md#agents).

`agentsPage`, `agentsReadiness`, `AgentRole.stages` (`CarrierCore/AgentsPage.swift`, `AgentsReadiness.swift`; `AgentsPageTests`, `AgentsReadinessTests`); views untested.

### Sessions page

What the person sees: [settings](../docs/macos/settings.md#sessions-page).

Tested: `SessionAgesTests`, `IdleCloseTests`; the view not.

### Health tab

What the person sees: [settings-health](../docs/macos/settings-health.md#health-tab).

The rows are `healthSections(host:facts:)` (`HealthRows.swift`, `HealthRowsTests`); view untested. Decoding and outcomes: `DoctorChecksTests`.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`choose(_:)`, `choose(repo:)`, `choose(folder:)`, `choose(newProject:)`, `watch`), which the shared `AddProjectSheet.swift` drives in `ProjectSheetMode.newSession` (`NewSessionTests`); `AppDelegate`'s wiring is untested.
The health fix list, script and opener are tested in `HealthFixTests` (hostile values run nothing); the button not.
The worktree choice is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply; `WorktreeChoiceTests`, golden files).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls not.
`CarrierCore/ChatLink.swift` reads the chat host ([how](../docs/macos/sessions.md#how-the-app-reads-the-chat-host); `ChatLinkTests`).
A subagent's row is `Subagent` (`ChatToolGroups.swift`), built by `chatFeed` from `task` events (`SubagentRowTests`).

## Usage

What the person sees: [usage](../docs/macos/usage.md).

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic: `CarrierCore/Dictation.swift`, `DictationSession.swift`, `TentativeText.swift`, `DictationPresentation.swift`, tested with `ScriptedDictation.swift`; `DictationController` holds the switch both boxes read; `LaunchPhases`: after the first frame.
Readiness: `speechModelStep`, `ModelSlot`, run by `DictationController.warmUp`; `DictationSession.run` captures before `prepare`.
Firm and tentative: `DictationEvent.partial`, `TentativeText.tentativeRange`, `GlobalDictation.split`.
The page is `Carrier/DictationTab.swift` (`reset(.dictation)` restores `AppPreferences.keys(of:)`); views untested.

### Global dictation

See [dictation](../docs/macos/dictation.md#global-dictation). The machine is `CarrierCore/GlobalDictation.swift` (`GlobalDictationTests`, scripted recognizer; Hold is `.up`); shortcut `DictationShortcut.swift`; paste or copy `PasteDecision.swift`; box or widget `DictationRoute.swift` (box side `MessageBox.dictateRequest`).
`Carrier/GlobalDictationController.swift` wires `GlobalHotKey`, `DictationWidget`, `ClipboardPaste`; views untested.

### History, statistics and cleanup

[History](../docs/macos/dictation.md#history) and [statistics](../docs/macos/dictation.md#statistics): `DictationRecords.swift` (fake clock, fed by `DictationSession.take`; `load()` is async), `DictationAudio.swift`, `DictationStatistics.swift`; the player is untested.
Cleanup: `DictationCleanup.swift` (`TextModelClient`, `CleanupRun`) and `LocalModelClient.swift`; the `.cleaning` state of `DictationSession` is in `DictationSessionTests`; `CleanupController.swift`, `CleanupGroup.swift` untested.

## Embedded terminal

What the person sees: [terminal](../docs/macos/terminal.md).

Pure rules (`Terminal{Core,SplitTree,Persistence,Settings,ZshBottomPromptShim}.swift`) are in `CarrierCore` (`TerminalCoreTests`, `TerminalZshBottomPromptShimTests`); Continue in Terminal's launch is `ContinueInTerminal.swift` (`embeddedResumeLaunch`).
The AppKit runtime (`Carrier/Terminal{Host,Appearance,ProcessInspector,ConfirmationCopy}.swift`, `CarrierTerminalView.swift`) owns the `paneId`-keyed `GhosttyKit` surface cache, live settings reload, `ZDOTDIR` bottom-prompt preparation, `⌘K` scrollback clear and close confirmation; the views are the `Terminal*View.swift` files, `MainMenu.swift`, `PanelView.swift` and friends.
Window selection and drawer state: `CarrierCore/WindowShell.swift` (`WindowShellTests`).
`libghostty-spm` (`GhosttyTerminal`) is linked by `Carrier` only; `build-app.sh` and `scripts/check-app.sh` bundle and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md`.
