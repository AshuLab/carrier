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
The chat host's, with its notice, are in `CarrierCore/StartChatHost.swift` (`chatHostAtOpen`, `startChatHostCommand`, `chatHostNotice`); `Carrier/ChatHostStarter.swift` reuses the engine's spawn and alert (wiring, views untested).
The sequence is tested on a real socket with a scripted engine (`EngineReplacementTests`).

## Dev build and release build

`build-app.sh` with no version makes the dev build, with a version the release build; the differences are in [CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder).
The plist says which it is: `CarrierChannel` is `dev` or `release`, and `isDevBuild` (`Carrier/AppDelegate.swift`) reads it for the Dock badge and the toolbar mark in `PanelView`.
A dev build has no `SUFeedURL`, so `AppUpdater.start` does not start the updater.
`scripts/check-app.sh` asserts id, channel and missing feed for both; a new difference goes into `build-app.sh` and that script.

## Epics

What the person sees: [the app shell](../docs/macos/app-shell.md#resume-card).

The words and request are tested; the sheet, its "Resuming…" state and layout not.

### The epic's Agent output

What the person sees: [the app shell](../docs/macos/app-shell.md#slices-and-findings-in-an-epics-log).

The rows, words and marks are two pure functions, `sliceCard(lane:)` in `CarrierCore/SliceCard.swift` (`SliceCardTests`) and `findingsCard(_:stage:round:)` in `CarrierCore/FindingsCard.swift` (`FindingsCardTests`, which also reads the golden epic reply); the views only for their heights (`LaneHeaderTests`).
The session row's words are `sessionRowText` and `RoleIdentities` (`SessionRowTests`); the epic's events become the chat's calls in `flowItems` (`EpicTranscriptAdapterTests`).

## Icons

What the person sees: [the app shell](../docs/macos/app-shell.md#file-icons).

The SVGs and the upstream licence text are in `CarrierCore/Resources/FileIcons` (release pinned in `SOURCE.txt`, notice in `THIRD-PARTY-NOTICES.md`, line in About).
`build-app.sh` copies SwiftPM's `Carrier_CarrierCore.bundle` into `Contents/Resources` and fails when an icon or the licence is missing from it.
Interface icons: `AppIcon` in three sets (`IconSets.swift`, `IconsTests`), drawn by `Glyph`.

## Settings

The window is `Carrier/SettingsWindow.swift`, a page's shared pieces `SettingsTabs.swift` ([settings](../docs/macos/settings.md)); `SettingsIndexDriftTests` keeps the search's `settingsIndex` in step with them.

### Providers page

What the person sees: [settings-app](../docs/macos/settings-app.md#providers).

The rows are `providersPage(_:config:chat:)` and the list's `providersDirectory` (`CarrierCore/ProvidersPage.swift`, `ProvidersDirectory.swift`; `Providers{Page,Directory}Tests`); views untested; `providers.json` is in `ProvidersFileTests` and `FixtureServerTests`.

### Projects file

`projects.json` is read, checked, edited and added to by `CarrierCore/ProjectsFile.swift` (`ProjectsFileTests`, `ProjectsListTests`); the same rules as `src/config/projects.ts` are run over `Tests/Fixtures/projects.json` by `ContractTests`.

### Projects page

What the person sees: [settings](../docs/macos/settings.md#projects-page).

The rows, last active and the order of the list (`projectsWithLastActive`, `ProjectOrder`), identity rules, actions, sheet model, the remote read from `.git/config`, the add, the new project form (`NewProjectForm`, `ProjectsModel.createProject`, the host's `newProject`; `chat-new-project.json` is its golden reply), the edits (`ProjectsModel.setDefault` writes `defaults` through `applyingProjectDefaultsEdit`, which `NewSessionModel.projectDefaults` reads when a project is chosen: `NewSessionTests`, `ProjectsFileTests`; `ProjectsModel.setHidden` writes `hidden`, which only the sheet New session opens and the list's Hidden chip, `ProjectFilter.hidden`, read), the Carrier switch (`ProjectWatch.swift`: `projectWatchRow` for its words and problems, `saveWatch` over the Repos page's `applyingRepos`/`saveConfig`, `projectsWithWatched` and `ProjectFilter.watched` for the list's Carrier column and Watched chip; tests in `RepoListTests` and `ProjectsListTests`) and the removal (`applyingProjectRemoval`, `ProjectsModel.remove`: only the entry and its image copy) or, for what Carrier made, its deletion to the Trash (`ProjectDeletion.swift`: `canDeleteFromDisk`, `deleteFromDiskWords`, `projectDeletionCheck`, `moveProjectToTrash`, `ProjectsModel.deletionCheck`/`deleteFromDisk`; `ProjectDeletionTests`, the Trash itself tried by hand; `ConversationModel.folderGone` in `ChatConversationTests`), a folder that is not a git repository (`isGitRepository`, `ProjectRow.isGit`, and `ProjectPage`, which says which groups its page has and the one-line why) and a folder that is gone (`ProjectStatus`, `projectFolderExists`) and Locate… (`applyingProjectLocation`, `ProjectsModel.locate`: only `path` changes) are pure functions in `CarrierCore/ProjectsList.swift`, `ProjectSheet.swift`, `ProjectIcon.swift`, `ProjectIconStore.swift`, `ProjectActions.swift`, `WorkspaceSources.swift` (`projectFolderRefusal`, sharing `Tests/Fixtures/project-folder.json` with `src/chat/folder.ts`) and `ProjectsFile.swift` (`ProjectsListTests`, `ProjectSheetTests`, `ProjectIconTests`, `ProjectIconStoreTests`, `ProjectActionsTests`, `ProjectsFileTests`), and `projectIdentity(path:in:)` / `projectIdentity(repo:in:)` / `projectTile(path:in:fallback:)` / `projectTile(repo:in:fallback:)` (`ProjectIcon.swift`, `ProjectIconTests`) give the tile and group title wherever a project shows, the fallback being what the place drew before projects, `retitled(_:projects:)` (`ChatSessions.swift`, `ChatSessionsTests`) titles the sidebar's groups with them and `ProjectsModel.shared` is the app's one reading of the file for those views; a project's worktrees (`ProjectWorktrees`, `worktreeRows` in `ProjectWorktrees.swift`, the `projectWorktrees` request behind `projects`, `ProjectsModel.worktrees(of:)`; the Remove button's state (`WorktreeRow.hasRemove`, `removeBlockedBy`) and the Clean up words (`ProjectCleanup`, `cleanUpWords`, `cleanUpReport`) are pure functions there too, over the `removeProjectWorktree` and `cleanProjectWorktrees` requests and `ProjectsModel.removeWorktree`, `cleanUpWorktrees`; `ProjectWorktreesTests`, `chat-project-worktrees.json` and `chat-project-cleanup.json` are the fixture host's answers), what a project takes on disk (`ProjectDisk.swift`: `formatDiskSize`, the Disk column's `projectsWithDisk`, the bar's `diskShares`, `diskTotalWords`, the `projectDisk` request behind `projects` and `ProjectsModel.refreshDisk`, which the follow loop runs; `ProjectDiskTests`, `chat-project-disk.json` is the fixture host's answer) and the clones the host runs (`ProjectClone`, the `cloneProject`, `projectClones` and `dismissClone` requests behind the `projects` capability in `ChatHost.swift`, `ChatHostTests`; their rows and model in `ProjectsList.swift`, `ProjectClonesTests`) and the sheet's repository results (`ProjectSheetGithub`, `ProjectSheetTests`), the sheet's New session mode (`ProjectSheetMode.newSession`, `NewSessionModel.choose(_:)`, which only fills the plan, `NewSessionTests`), and `ProjectsModel` follows the file (including a write by another process, a file that does not match, and refused folders); `--fixture` writes its projects in `FixtureServer.writeProjects` (`FixtureServerTests`); the views `Carrier/ProjectsTab.swift` and `Carrier/AddProjectSheet.swift` (which New session's chip opens too) are untested, only drawn by `--selftest`, and the page is in `SettingsIndexDriftTests`'s reach by its name.

### Agents page

What the person sees: [settings-carrier](../docs/macos/settings-carrier.md#agents).

`agentsPage`, `agentsReadiness`, `AgentRole.stages` (`CarrierCore/AgentsPage.swift`, `AgentsReadiness.swift`; `AgentsPageTests`, `AgentsReadinessTests`); views untested.

### Sessions page

What the person sees: [settings](../docs/macos/settings.md#sessions-page).

The functions are tested in `SessionAgesTests` and `IdleCloseTests`; the view is untested.

### Health tab

What the person sees: [settings-health](../docs/macos/settings-health.md#health-tab).

The rows are one pure function, `healthSections(host:facts:)` (`CarrierCore/HealthRows.swift`, `HealthRowsTests`); the view is untested.
The decoding, outcomes, command and store are tested (`DoctorChecksTests`), not the process runner.

## New session

What the person sees: [new session](../docs/macos/new-session.md).

The logic is `NewSessionModel` (`choose(_:)`, `choose(repo:)`, `choose(folder:)`, `choose(newProject:)`, `watch`), which the shared `Carrier/AddProjectSheet.swift` drives in New session's mode (`ProjectSheetMode.newSession`; the chooser popover, `WorkspaceSheet`, is gone) (`NewSessionTests`, a fake host).
The rule, the host client's decoding and the draft are tested (`HealthTests`, `ChatHostTests`, `NewSessionTests`); `AppDelegate`'s wiring is not.
The list, script and opener are tested in `HealthFixTests` (hostile values run nothing); the button not.
The worktree choice is `CarrierCore/WorktreeChoice.swift` (pure values over the `workspace` reply; `WorktreeChoiceTests`, golden files).

## Conversation

What the person sees: [sessions](../docs/macos/sessions.md#conversation).

The words are tested; the Finder and pasteboard calls not.
`CarrierCore/ChatLink.swift` reads the chat host ([how](../docs/macos/sessions.md#how-the-app-reads-the-chat-host); `ChatLinkTests`).
A subagent's row is `Subagent` (`CarrierCore/ChatToolGroups.swift`), built by `chatFeed` from `task` events (`ChatConversationTests`, `SubagentRowTests`).

## Usage

What the person sees: [usage](../docs/macos/usage.md).

## Dictation

What the person sees: [dictation](../docs/macos/dictation.md).

The logic is `CarrierCore/Dictation.swift`, `DictationSession.swift`, `TentativeText.swift` and `DictationPresentation.swift`, tested with `ScriptedDictation.swift`; `DictationController` holds the switch both boxes read.
Readiness: `speechModelStep`, `ModelSlot`, run by `DictationController.warmUp` (`DictationReadinessTests`); `DictationSession.run` captures before `prepare`.
Firm and tentative: `DictationEvent.partial`, `TentativeText.tentativeRange`, `GlobalDictation.split` (`TentativeTextTests`).
The page is `Carrier/DictationTab.swift` (a first screen, six `DictationScreen`s); `dictationReadiness` words its card (`DictationReadinessModelTests`); `reset(.dictation)` restores `AppPreferences.keys(of:)`; views untested.

### Global dictation

See [dictation](../docs/macos/dictation.md#global-dictation). The machine is `CarrierCore/GlobalDictation.swift` (`GlobalDictationTests`, scripted recognizer; Hold is `.up`).
Shortcut: `CarrierCore/DictationShortcut.swift` (`recordShortcut`, `DictationShortcutTests`); the recorder row is untested.
`CarrierCore/PasteDecision.swift` (`PasteDecisionTests`) picks paste or copy from `Carrier/FocusedField.swift` (untested).
`Carrier/GlobalDictationController.swift` wires `GlobalHotKey`, `DictationWidget` and `ClipboardPaste` (`ClipboardPasteTests`); the rest untested.
Box or widget: `CarrierCore/DictationRoute.swift` (`DictationRouteTests`); the box side is `MessageBox.dictateRequest`.
Sounds: `DictationSounds.swift` (`DictationSoundsTests`); widget look: `DictationWidgetLook.swift` (`DictationPresentationTests`); their views untested.

### History

See [dictation](../docs/macos/dictation.md#history).
`CarrierCore/DictationRecords.swift` (`DictationRecordsTests`), fed by `DictationSession.take`.
Audio: `DictationRecords` (fake clock), `DictationAudio.swift`; the player is untested.

### Statistics

See [dictation](../docs/macos/dictation.md#statistics). Counters: `DictationRecords`; figures, hours, week and records: `DictationStatistics.swift` (`DictationStatisticsTests`); `StatisticsGroup` untested.

### Cleanup

`CarrierCore/DictationCleanup.swift` (`TextModelClient`, `CleanupRun`; `CleanupRunTests`) and `LocalModelClient.swift` (`LocalModelClientTests`); `CleanupController.swift` and `CleanupGroup.swift` are untested.
In the boxes and the widget: the `.cleaning` state of `DictationSession` (`DictationSessionTests`, `GlobalDictationTests`).

## Embedded terminal

What the person sees: [terminal](../docs/macos/terminal.md).

Pure rules (`Terminal{Core,SplitTree,Persistence,Settings,ZshBottomPromptShim}.swift`) live in `CarrierCore` (`TerminalCoreTests`, `TerminalZshBottomPromptShimTests`).
Continue in Terminal's launch (`EmbeddedResumeLaunch`, `embeddedResumeLaunch`) is in `CarrierCore/ContinueInTerminal.swift` (`ContinueInTerminalTests`).
The AppKit runtime (`Carrier/Terminal{Host,Appearance,ProcessInspector,ConfirmationCopy}.swift`, `Carrier/CarrierTerminalView.swift`) owns the `paneId`-keyed `GhosttyKit` surface cache, live settings reload, `ZDOTDIR` bottom-prompt preparation, `⌘K` scrollback clear and close confirmation.
The sidebar, overview, workspace, tab bar, settings page, menu bar, middle-click close and drawer views are the `Terminal*View.swift` files, `MainMenu.swift`, `MiddleClickModifier.swift`, `ContinueInTerminalView.swift`, `SessionSectionsView.swift`, `EpicView.swift` and `PanelView.swift`.
Window selection and drawer state live in `CarrierCore/WindowShell.swift`, tested with layout, shortcuts and middle-click in `TerminalWorkspaceLayoutTests`, `MainMenuShortcutsTests`, `MiddleClickModifierTests` and `WindowShellTests`.
Session deletion cleanup and process-activity guards use `CarrierCore/ChatArchive.swift`, `ChatSessions.swift`, `Carrier/WindowController.swift` and `AppDelegate.swift` (poller and store tested, view wiring not).
`libghostty-spm` (`GhosttyTerminal`) is linked by the `Carrier` target only; `build-app.sh` and `scripts/check-app.sh` bundle and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md` (`ThirdPartyNoticesTests`).
