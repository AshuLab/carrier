# Settings

Settings in its own window, its sidebar, its search and where each group of pages is described.

Settings is a window of its own (`Carrier/SettingsWindow.swift`: an `NSWindow` hosting a `NavigationSplitView`, as the main window is), not a sheet: it does not stop the main window being used, it keeps its place, size and last page (`CarrierSettingsWindow` autosave, `SettingsNavigator`), and ⌘W closes it.
The sidebar lists sixteen pages in four groups, each page a colored tile with its symbol (`SettingsPage`, `SettingsSidebar`): App (General, Providers, Appearance, Notifications, Keybindings, Dictation; no heading, and Providers is here because both the engine and the chat host read its accounts), Workspace (Chat, Sessions, Sidebar, Terminal), Carrier (Agents, Repos, Behavior) and System (Engine, Health, About, last).
The chosen page is on the right under the window's toolbar: the page's name as its title and its line as its subtitle, ‹ › to go back and forward through the pages visited (⌘[ and ⌘], `SettingsHistory`), the page's note (Behavior's "Saved" or why it cannot save, with Ask Carrier again) and a ⋯ menu with Reset this page….
The menu's Settings…, ⌘, and the sidebar's Settings row open it on the page it was left on (`WindowController.showSettings`; it opens the main window too when it was closed, since the pages read what Carrier answers to it), or on the page a caller asks for (the Open Settings button of the stopped-Carrier view asks for Engine, and a reason that points to Health opens Health).

## Search

The field at the top of the sidebar (⌘F) finds a page, a group or a row by the words of its title, its group, its page or its description, all of them, in any order, ignoring case and accents (`settingsResults`); the results are listed in the sidebar under their pages, the words found marked, and choosing one opens its page, scrolls to the row and shows it for a moment.
What can be found is `settingsIndex` (`CarrierCore/SettingsIndex.swift`, `SettingsIndexTests`): a row finds its place from its page, its group and its title (`settingsAnchor`), so a new row is added to the index and nothing else.
`SettingsIndexDriftTests` reads the views as text and fails when a title a page draws is not in the index, or one in the index is no longer written in the sources (a title that is only a value, such as an account's, is listed in the test as not searched).

## Reset

A page with many controls gives its Reset to the window (`SettingsPageBody(reset:)`), and the ⋯ menu of the toolbar asks "Reset <page>?" before it runs (an alert: Cancel, or Reset in red).
The menu item is off while the open page has none (Providers, Repos, Health, Engine and About have nothing to reset).
Behavior and Sessions keep what a Reset did before (the engine's eight values back to `EngineConfig()`, the preferences and the two ages of `chat.json`), now from the same menu.

## Where something that needs fixing shows

What Carrier is missing (`carrier` or `node` not found, or being looked for) shows as a banner on the Engine and Health pages only, and as a badge on their rows in the sidebar; it no longer sits over every page.

## The pages

- App: [settings-app](settings-app.md) (General, Providers, Appearance, Notifications, Keybindings) and [dictation](dictation.md#the-dictation-page) (Dictation, after Keybindings: it is global, not of the chat).
- Workspace: [Sessions](#sessions-page) below (Chat, Sessions, Sidebar) and [Terminal](settings-app.md#terminal).
- Carrier: [settings-carrier](settings-carrier.md) (Agents, Repos, Behavior).
- System: [settings-carrier](settings-carrier.md) (Engine), [settings-health](settings-health.md) (Health) and About.
- About (`Carrier/AboutTab.swift`, last of the sidebar): the app's icon, name and version with the links of the About panel (`aboutLinks`: Release notes, Documentation, GitHub) and a row Star Carrier on GitHub with its button (it opens the repository, `repositoryURL`); Updates (Check now or the step of an update found, Check by itself, Install by itself and Update delay: None, 1, 3, 7, 14 or 30 days, `updates.delayDays`, `updateDelayChoices`); and the engine's own update with Try again.
The delay holds back, for that many days after its date in the appcast, a release that Sparkle finds on its own (`UpdateDelay`, the updater's delegate, ending that check as "no update" and not as a failure, so the pill shows nothing); Check now and a critical update ignore it, and a release with no date is offered.

## Sessions page

Settings has a Sessions page (`Carrier/SessionsTab.swift`, `SettingsPage.sessions`, in the Chat group after Sidebar, "How sessions start and age out") with everything a person sets about how a session starts, ages and is deleted; the Chat page keeps only the message box and the conversation.
Its groups are New sessions ("Starts with", the provider, model, reasoning and access a new session opens with, and "Work in", the base folder or a new worktree), Archive and delete, With these ages and Reset.
Archive and delete has the session clock's two ages, `archiveAfterDays` and `deleteAfterDays` of the chat's `<folder>/chat.json`: each a number of days or Never, shown with the values the file has (15 and 30 when it has none), and "Ask before deleting a session".
A change of an age is saved as it is made (`applyingSessionAges` in `CarrierCore/SessionAges.swift`, as `applyingProjectsFolder` does: the file's other keys are kept, an age equal to its default is left out, a file that is not a JSON object is never overwritten); the host reads the file each pass, so nothing is restarted.
Delete is off, with the reason, while archive is Never, and an age that breaks the host's rule (a number under 1, or delete not greater than archive) is not saved and the field says why (`sessionAgeProblems`, `deleteAgeOffReason`).
With these ages says in dates what the ages do to a session left alone from today (`sessionAgesLine` in `CarrierCore/SessionAges.swift`, given the date of the day: "Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity", with the year only for a date that is not in this year; never archived or deleted with Archive at Never; archived and never deleted with Delete at Never; not shown while an age is refused), and, always, that a session that is working, waiting for you or open is looked at again later.
Reset (the toolbar's, with its question) puts back "Starts with", "Work in", the delete question and the two ages to 15 and 30 days in `chat.json`; the Reset of Chat does not touch them.

## Changes apply without a restart

Nothing here restarts Carrier: every writer of `engine.json` or `providers.json` (the Behavior and Repos tabs, `GlobalRoleSave`, `RepoRoleSave`, `RoleDetailsSave`, `LeadReviewerSwitch`, the Engine page's GitHub identity (`saveOrchestratorProfile`), the Providers page and the new session's watch) asks the engine after its own successful write, off the main thread and off the cooperative pool (`reloadInBackground`, which hands the ask to `ReloadStatus.shared` in `CarrierCore/EngineReload.swift`; the new session and the Providers store use `ReloadStatus.answer`, which keeps the answer in the same place and gives it back for their own line).
The answer is a `ReloadOutcome` (applied, nobody to ask, an engine that does not list `reload`, refused with the engine's words, or no answer); `ReloadStatus` keeps the last one for every page, drops the answer of an older ask when a newer one was made and forgets it when Carrier stops or starts (`PanelView`), `reloadWords` says what a page shows (`ReloadNote` in Repos and Agents, with Ask Carrier again for a problem, which is said to VoiceOver every time it comes, as are the refusals of a repo's role form (`ProblemLine`); the Behavior header, which has Ask Carrier again too; the Providers lines, whose Add button waits while `ProvidersStore.busy` (Save, Remove and Add account close at once and the answer comes after), and where an older engine is a grey `editNote` and not an `editProblem`); an older engine's "reads it when it starts" is a quiet note, not a problem, and the Repos page's note follows the engine's `reload` capability and that outcome (`CarrierCore/SettingsNote.swift`, tested in `SettingsNoteTests` and `ReloadStatusTests`).
