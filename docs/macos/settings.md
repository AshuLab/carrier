# Settings

Settings in its own window, its sidebar, its search and where each group of pages is described.

Settings is a window of its own (`Carrier/SettingsWindow.swift`: an `NSWindow` hosting a `NavigationSplitView`, as the main window is), not a sheet: it does not stop the main window being used, it keeps its place, size and last page (`CarrierSettingsWindow` autosave, `SettingsNavigator`), and ⌘W closes it.
The sidebar lists eighteen pages in four groups, each page a colored tile with its symbol (`SettingsPage`, `SettingsSidebar`): App (General, Providers, Appearance, Notifications, Keybindings, Dictation, Keep awake; no heading, and Providers is here because both the engine and the chat host read its accounts), Workspace (Chat, Sessions, Projects, Sidebar, Terminal), Carrier (Agents, Repos, Behavior) and System (Engine, Health, About, last).
The chosen page is on the right under the window's toolbar: the page's name as its title and its line as its subtitle, ‹ › to go back and forward through the pages visited (⌘[ and ⌘], `SettingsHistory`), the page's note (why Behavior cannot save, with Ask Carrier again) and, on a page that has a Reset, a ⋯ menu with Reset this page….
The menu's Settings…, ⌘, and the sidebar's Settings row open it on the page it was left on (`WindowController.showSettings`; it opens the main window too when it was closed, since the pages read what Carrier answers to it), or on the page a caller asks for (the Open Settings button of the stopped-Carrier view asks for Engine, and a reason that points to Health opens Health).

## Search

The field at the top of the sidebar (⌘F) finds a page, a group or a row by the words of its title, its group, its page or its description, all of them, in any order, ignoring case and accents (`settingsResults`); the results are listed in the sidebar under their pages, the words found marked, and choosing one opens its page, scrolls to the row and shows it for a moment.
What can be found is `settingsIndex` (`CarrierCore/SettingsIndex.swift`, `SettingsIndexTests`): a row finds its place from its page, its group and its title (`settingsAnchor`), so a new row is added to the index and nothing else.
`SettingsIndexDriftTests` reads the views as text and fails when a title a page draws is not in the index, or one in the index is no longer written in the sources (a title that is only a value, such as an account's, is listed in the test as not searched).

## Reset

A page with many controls gives its Reset to the window (`SettingsPageBody(reset:)`), and the ⋯ menu of the toolbar asks "Reset <page>?" before it runs (an alert: Cancel, or Reset in red).
The ⋯ menu is only there on a page that has a Reset: Providers, Agents, Repos, Health, Engine and About have nothing to reset and show no menu.
The Dictation page has its Reset on its first screen only ([dictation](dictation.md#the-dictation-page)); on its screens the ⋯ menu is not drawn.
Behavior and Sessions keep what a Reset did before (the engine's eight values back to `EngineConfig()`, the preferences and the two ages of `chat.json`), now from the same menu.

## Where something that needs fixing shows

What Carrier is missing (`carrier` or `node` not found, or being looked for) shows as a banner on the Engine and Health pages only, and as a badge on their rows in the sidebar; it no longer sits over every page.

## The pages

- App: [settings-app](settings-app.md) (General, Providers, Appearance, Notifications, Keybindings), [dictation](dictation.md#the-dictation-page) (Dictation, after Keybindings: it is global, not of the chat) and [keep-awake](keep-awake.md) (Keep awake, last of the group).
- Workspace: [Sessions](#sessions-page) below (Chat, Sessions, Sidebar), [Projects](#projects-page) and [Terminal](settings-app.md#terminal).
- Carrier: [settings-carrier](settings-carrier.md) (Agents, Repos, Behavior).
- System: [settings-carrier](settings-carrier.md) (Engine), [settings-health](settings-health.md) (Health) and About.
- About (`Carrier/AboutTab.swift`, last of the sidebar): the app's icon, name and version with the links of the About panel (`aboutLinks`: Release notes, Documentation, GitHub) and a row Star Carrier on GitHub with its button (it opens the repository, `repositoryURL`); Updates (Check now or the step of an update found, Check by itself, Install by itself and Update delay: None, 1, 3, 7, 14 or 30 days, `updates.delayDays`, `updateDelayChoices`); and the engine's own update with Try again.
The delay holds back, for that many days after its date in the appcast, a release that Sparkle finds on its own (`UpdateDelay`, the updater's delegate, ending that check as "no update" and not as a failure, so the pill shows nothing); Check now and a critical update ignore it, and a release with no date is offered.

## Chat text

The Chat page's Conversation group has Message text size (11 to 20 pt, 13 by default), Line spacing (Tight, Normal, Loose) and Message spacing (Compact, Comfortable, Spacious: 8, 12 and 20 pt between messages), each apart from the app's Text size and Density (user defaults `chat.textSize`, `chat.lineSpacing` and `chat.messageSpacing`).
Text size and Density in Appearance no longer reach the messages' text or the gap between them; the rest of a conversation (tool rows, times, notices, the fields of a structured report) still follows the app's Text size, and the command pills of the bubble keep their fixed size.
The agent's answer (`MarkdownView`, its tables at 12.5/13 of the size, and its link hit areas, laid out again when a setting changes), the person's bubble and a subagent's brief read them through `.chatText()` (`ScaledFont.swift`); the two bubbles add no room between their lines at Normal, as before, and only what Loose has over it; the preview under the group follows each change, and Reset on the page restores them.

## Sessions page

Settings has a Sessions page (`Carrier/SessionsTab.swift`, `SettingsPage.sessions`, in the Chat group after Sidebar, "How sessions start and age out") with everything a person sets about how a session starts, ages and is deleted; the Chat page keeps only the message box and the conversation.
Its groups are New sessions ("Starts with", the provider, model, reasoning and access a new session opens with, "Work in", the base folder or a new worktree, and "Start from", where a new worktree is cut), Idle sessions, Archive and delete, With these ages and Reset.
"Start from" is the chat's `worktreeStart` in `chat.json`: Remote branch (latest), which is what the row shows when the file does not say, or Local branch.
A change is saved as it is made (`applyingWorktreeStart` in `CarrierCore/WorktreeStart.swift`, written the way the ages are: the file's other keys are kept, Remote is left out of the file, a file that is not a JSON object is never overwritten), and `worktreeStart(chatJSON:)` reads it back (`remote` when the key is missing or is not one of the two values).
The row is off, with the words "Only for a new worktree", while "Work in" is the base folder (`worktreeStartOffReason`), and on again when it is a new worktree; it stays in the search while it is off.
The group's footer says that Remote fetches the branch first and falls back to the local one when it cannot be reached.
Idle sessions has "Sleep after", the chat's `idleCloseMinutes` in `chat.json`: 10 minutes (what the row shows when the file does not say), 30 minutes or 1 hour (`IdleClose` in `CarrierCore/IdleClose.swift`).
It is how long a session nobody opens keeps its agent running before the host closes it; the session stays in the list as asleep and a message wakes it, and the one you have open is read all the time and stays.
A change is saved as it is made (`applyingIdleClose`, written the way the start is: the file's other keys are kept, 10 minutes is left out of the file, a file that is not a JSON object is never overwritten), and `idleClose(chatJSON:)` reads it back (10 minutes when the key is missing or is not one of the three values the host accepts); the host reads the file every few seconds, so nothing is restarted.
The row is in the search by what a person would type for it (sleep, idle, memory, asleep, close, agent, timeout, inactive, minutes, hour).
Archive and delete has the session clock's two ages, `archiveAfterDays` and `deleteAfterDays` of the chat's `<folder>/chat.json`: each a number of days or Never, shown with the values the file has (15 and 30 when it has none), and "Ask before deleting a session".
A change of an age is saved as it is made (`applyingSessionAges` in `CarrierCore/SessionAges.swift`, as `applyingProjectsFolder` does: the file's other keys are kept, an age equal to its default is left out, a file that is not a JSON object is never overwritten); the host reads the file each pass, so nothing is restarted.
Delete is off, with the reason, while archive is Never, and an age that breaks the host's rule (a number under 1, or delete not greater than archive) is not saved and the field says why (`sessionAgeProblems`, `deleteAgeOffReason`).
With these ages says in dates what the ages do to a session left alone from today (`sessionAgesLine` in `CarrierCore/SessionAges.swift`, given the date of the day: "Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity", with the year only for a date that is not in this year; never archived or deleted with Archive at Never; archived and never deleted with Delete at Never; not shown while an age is refused), and, always, that a session that is working, waiting for you or open is looked at again later.
Reset (the toolbar's, with its question) puts back "Starts with", "Work in", "Start from" (to Remote, in `chat.json`), "Sleep after" (to 10 minutes, in `chat.json`), the delete question and the two ages to 15 and 30 days in `chat.json`; the Reset of Chat does not touch them.

## Projects page

Settings has a Projects page (`Carrier/ProjectsTab.swift`, `SettingsPage.projects`, in the Workspace group between Sessions and Sidebar, "The folders you work in"), the list of the projects a person works on ([the spec](../specs/projects.md), [0038](../adr/0038-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)).
It is a full-width list, found in the search by its name.
With no projects it shows an empty state with Add project; with some it shows a row each, in the order of `projects.json`, with the project's tile (its chosen image, its chosen colour and mark, or initials on a colour made from its name when none is chosen), its name (the folder's name when none is set), the GitHub `owner/name` of its `origin` or else its path, a pin mark when pinned, and a chevron, and an Add project button above them.
The remote is read from the repository each time (`originRepo(ofFolder:)` in `CarrierCore/ProjectsList.swift`, the `origin` of its `.git/config`) and is never stored; an `origin` that is not GitHub's, or no repository, shows the path.
Add project opens the system's folder panel and writes the chosen folder as an entry with `origin` `added` and the folder's name (`ProjectsFile.add`: the file is read again just before, and every other entry and key is kept); it shows in the list at once.
A folder inside Carrier's own folders (`engine`, `chat/state`, `chat/logs`, `chat/worktrees`, `chat/pending`, `chat/sessions`, with symlinks resolved), a file, a folder that cannot be read, or a worktree linked to another project is refused with the reason in orange (`projectFolderRefusal` in `CarrierCore/WorkspaceSources.swift`, `ProblemLine`), and writes nothing.
A folder that already is a project, written any way (`~`, a trailing slash, a symlink), writes nothing and opens that project's page.
Choosing a row opens the project as a screen of its own, a place of the window's history (‹ goes back to the list) in a centred column, with the project's name and its remote or path in the toolbar, and a Pin button in the page's header.
Its Identity group holds Name (emptied, it goes back to the folder's name, and a blank name is never written), Icon (Change… opens a popover of eight colours, eight existing `AppIcon` marks stored by the icon's name, and Choose image… to pick an image copied at most 256 points into `app/project-icons` as a PNG, cleared and deleted when a colour or mark is chosen afterwards, with a missing copy falling back to colour and mark) and Tags (Return adds a tag, trimmed, lower case and without repeats, and a cross removes it), each change written at once while keeping every other key.
The screen has an Actions row showing how many actions are set ("None" or "N actions") and a chevron, which opens an Actions screen of its own with the project's name under Actions in the toolbar.
The Actions screen has two groups, New worktree and After clone, each listing its actions in order and ending in Add action, where each action has a name, an on switch, a delete button, a monospaced command field and an "If it fails" choice of Warn and continue or Stop the session.
Each valid edit writes at once to the project's `actions` in `projects.json` (omitting `on` when on and `onFail` when Warn and continue), while a blank name or command is not written and is shown as a problem.
The screen also shows the folder with Reveal in Finder (off when the folder is not there) and the remote with Open on GitHub, only when there is one.
The list and each project's screen follow the file while the page is open: `ProjectsModel.follow` reads it again every second, so what the chat host or an editor writes shows without reopening the page.
A file that does not match its schema, or cannot be read, shows each problem on the page with its field named (`projects.json: projects.0.name must not be blank`) in place of the list, and the page writes nothing while it is wrong.
`--fixture` has five projects: one pinned with tags, a colour and a mark, two actions and a GitHub origin, one whose name and remote are very long, a folder with a colour that is not a repository, one that is not there with a missing image copy that falls back to colour and mark, and one with a copied icon image.

## Changes apply without a restart

Nothing here restarts Carrier: every writer of `engine.json` or `providers.json` (the Behavior and Repos tabs, `GlobalRoleSave`, `RepoRoleSave`, `RoleDetailsSave`, `LeadReviewerSwitch`, the Engine page's GitHub identity (`saveOrchestratorProfile`), the Providers page and the new session's watch) asks the engine after its own successful write, off the main thread and off the cooperative pool (`reloadInBackground`, which hands the ask to `ReloadStatus.shared` in `CarrierCore/EngineReload.swift`; the new session and the Providers store use `ReloadStatus.answer`, which keeps the answer in the same place and gives it back for their own line).
The answer is a `ReloadOutcome` (applied, nobody to ask, an engine that does not list `reload`, refused with the engine's words, or no answer); `ReloadStatus` keeps the last one for every page, drops the answer of an older ask when a newer one was made and forgets it when Carrier stops or starts (`PanelView`), `reloadWords` says what a page shows (`ReloadNote` in Repos and Agents, with Ask Carrier again for a problem, which is said to VoiceOver every time it comes, as are the refusals of a repo's role form (`ProblemLine`); the Behavior header, which has Ask Carrier again too; the Providers lines, whose Add button waits while `ProvidersStore.busy` (Save, Remove and Add account close at once and the answer comes after), and where an older engine is a grey `editNote` and not an `editProblem`); an older engine's "reads it when it starts" is a quiet note, not a problem, and the Repos page's note follows the engine's `reload` capability and that outcome (`CarrierCore/SettingsNote.swift`, tested in `SettingsNoteTests` and `ReloadStatusTests`).
