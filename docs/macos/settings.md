# Settings

The Settings sheet, its rail and where each group of pages is described.

Settings is a sheet over the window (`Carrier/SettingsSheet.swift`, the shape of the workspace chooser: a rail of fifteen pages in four groups, App (General, Providers, Notifications, Appearance, Keybindings, Updates; no heading, and Providers is here because both the engine and the chat host read its accounts), Chat (Chat, Sidebar, Sessions, Dictation), Carrier (Repos, Agents, Behavior, Engine) and Legacy (Health), `RailHeader` and `RailRow` of `SheetParts.swift`, the chosen one on the right, closed by an ✕ at the top right or Esc).
The menu's Settings…, ⌘, and the sidebar's Settings row open it over whatever page is selected (`WindowShell.showSettings`, `settingsShown`; it is not a `Selection`), on General unless a caller asks for another (`openHealth` asks for Health, and the Open Settings button of the stopped-Carrier view asks for Engine).

## The rail

- App: [settings-app](settings-app.md) (General, Providers, Notifications).
- Chat: [Sessions](#sessions-page) below and [dictation](dictation.md#the-dictation-page) (Dictation).
- Carrier: [settings-carrier](settings-carrier.md) (Repos, Agents, Behavior, Engine).
- Legacy: [settings-legacy](settings-legacy.md) (Health).

## Sessions page

Settings has a Sessions page (`Carrier/SessionsTab.swift`, `SettingsPage.sessions`, in the Chat group between Sidebar and Dictation, "How sessions start and age out") with everything a person sets about how a session starts, ages and is deleted; the Chat page keeps only the message box and the conversation.
Its groups are New sessions ("Starts with", the provider, model, reasoning and access a new session opens with, and "Work in", the base folder or a new worktree), Archive and delete, With these ages and Reset.
Archive and delete has the session clock's two ages, `archiveAfterDays` and `deleteAfterDays` of the chat's `<folder>/chat/chat.json`: each a number of days or Never, shown with the values the file has (15 and 30 when it has none), and "Ask before deleting a session".
A change of an age is saved as it is made (`applyingSessionAges` in `CarrierCore/SessionAges.swift`, as `applyingProjectsFolder` does: the file's other keys are kept, an age equal to its default is left out, a file that is not a JSON object is never overwritten); the host reads the file each pass, so nothing is restarted.
Delete is off, with the reason, while archive is Never, and an age that breaks the host's rule (a number under 1, or delete not greater than archive) is not saved and the field says why (`sessionAgeProblems`, `deleteAgeOffReason`).
With these ages says in dates what the ages do to a session left alone from today (`sessionAgesLine` in `CarrierCore/SessionAges.swift`, given the date of the day: "Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity", with the year only for a date that is not in this year; never archived or deleted with Archive at Never; archived and never deleted with Delete at Never; not shown while an age is refused), and, always, that a session that is working, waiting for you or open is looked at again later.
Reset ("Restore the defaults") puts back "Starts with", "Work in", the delete question and the two ages to 15 and 30 days in `chat.json`; the Reset of Chat does not touch them.

## Changes apply without a restart

Nothing here restarts Carrier: every writer of `config.json` or `providers.json` (the Behavior and Repos tabs, `GlobalRoleSave`, `RepoRoleSave`, `RoleDetailsSave`, `LeadReviewerSwitch`, the Engine page's GitHub identity (`saveOrchestratorProfile`), the Providers page and the new session's watch) asks the engine after its own successful write, off the main thread and off the cooperative pool (`reloadInBackground`, which hands the ask to `ReloadStatus.shared` in `CarrierCore/EngineReload.swift`; the new session and the Providers store use `ReloadStatus.answer`, which keeps the answer in the same place and gives it back for their own line).
The answer is a `ReloadOutcome` (applied, nobody to ask, an engine that does not list `reload`, refused with the engine's words, or no answer); `ReloadStatus` keeps the last one for every page, drops the answer of an older ask when a newer one was made and forgets it when Carrier stops or starts (`PanelView`), `reloadWords` says what a page shows (`ReloadNote` in Repos and Agents, with Ask Carrier again for a problem, which is said to VoiceOver every time it comes, as are the refusals of a repo's role form (`ProblemLine`); the Behavior header, which has Ask Carrier again too; the Providers lines, whose buttons, Remove and Cancel included, wait while `ProvidersStore.busy`, and where an older engine is a grey `editNote` and not an `editProblem`); an older engine's "reads it when it starts" is a quiet note, not a problem, and the Repos page's note follows the engine's `reload` capability and that outcome (`CarrierCore/SettingsNote.swift`, tested in `SettingsNoteTests` and `ReloadStatusTests`).
