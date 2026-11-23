# Projects

Status: spec

## Problem

A person who works with Carrier has no place to manage the projects they work on.
Today a project is only a folder: a path on a session's row, grouped in the sidebar by the last part of that path, with an icon whose colour comes from its name.
Nothing can be set on it, not a name, an order, tags, an icon, nor what a new session starts with there.
The only page about repositories in Settings is the engine's list of what Carrier watches, so "which projects do I work on" and "which does Carrier listen to" are one tangled idea, and the choice of where to work ("Work in" in a new session) reads as if it were tied to Carrier.

Agents now clone and make worktrees and hold several conversations in several worktrees, and the person cannot see where the disk goes: a worktree is gigabytes, mostly what git ignores, and nothing says which project holds how much, which worktrees are finished, or which have work that is not pushed.
There is nowhere to say "when a worktree is made here, install the dependencies", so every new session starts by finding out what is missing.
A project that is not wanted in the new session picker cannot be hidden, and removing one is a matter of Finder.

We would know it is fixed when a person can see all their projects in one place, set a name, icon, tags and the defaults of new sessions on each, see and clean what each takes on disk, have the first steps of a new worktree run by themselves, hide a project from the picker, and remove one choosing whether its files go, and when Carrier watching a project is one switch on it and no longer the reason the page exists.

## Solution

A project becomes a thing of the person's workspace, not of the engine ([0041](../adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)).
It is one entry of `projects.json`, at the top of the Carrier folder and read and written by both the app and the chat host, identified by its folder's path, holding only what the person sets: name, how it came to be, pinned, hidden, tags, icon, the defaults of a new session (agent, base folder or worktree, base branch, empty meaning the same as everywhere) and its actions.
The remote, the branch, the worktrees, their state and their size are derived and never stored; the size is cached apart by the host.

There is no folder where projects have to live and none is scanned.
Each project is added by its own folder, from one redesigned sheet that replaces today's Choose a workspace and is the same wherever a person chooses where to work: in Settings it is Add project and a choice acts at once, and in New Session a choice only fills the plan and nothing is cloned or written until the first message ([0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
It has one field that takes a pasted GitHub address, a search over the person's repositories and folders used lately, or a path; drag and drop, the keyboard, the clone destination shown at the action and changeable for that clone, "already a project" instead of a second entry, an error that says what to do when the login cannot see a repository, and, in Settings, a clone that runs in the list with its progress and does not hold the sheet. `projectsFolder` stays only as the default destination of a new clone or new project, and the Projects page ends with a line that says where new clones go, with Change…, which writes it as the old sheet's footer did.
The clones that exist from before are not imported: the list starts empty and the person adds what they want.

A project is born by hand from Settings, or when a new session's plan that clones or creates a workspace is prepared successfully at the first message ([0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
A folder chosen with Open a folder in a new session stays a plain workspace with an Add as project.
The sheet that New Session opens lists the projects that are not hidden first, with their icons, then the folders used lately that are not projects and the person's repositories.
A repository to clone there keeps the choice "Let Carrier watch this repo", on by default, as today, while Add project in Settings does not watch what it adds: watching is the switch on the project's page.
Hiding a project takes it out of that sheet and nowhere else.

The page is Projects, in the Workspace group of Settings, between Sessions and Sidebar.
It is a full-width list with a search, a chip for each tag, All, Watched, Local only and Hidden, a way to group by tag or by Carrier, and the columns Project, Tags, Last active, Disk and Carrier, each row ending in a chevron; the pinned come first, and then the list is in name order unless the person sorts by last activity (derived from the sessions that worked in the project, never stored) or by disk, with a click on the column's title.
A project that is cloning shows its progress and is not open yet, and one whose folder is gone shows as not found.
Choosing a row opens the project as a page of its own, in a centred column, with the toolbar's back returning to the list and the toolbar naming the project.

The project's page has these groups, in this order: Identity (name, icon colour and mark or image, tags); New sessions here (whether it shows when starting a session, agent, work in, base branch); Worktrees and disk (the total and a bar, the main clone and each worktree with its branch, the session that made it, its age, its state and its size; a button to clean up the merged ones and one to remove a worktree, which take only the worktree's folder as [0035](../adr/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) does, so the branch and the session stay and the next message brings the folder back and runs the actions; neither touches a worktree with uncommitted changes or one whose session is open); Carrier (only the watch switch, off and explained when there is no GitHub origin); Actions (one row with how many, opening a screen of its own); and Folder (path, remote and Remove).
A folder that is not a git repository is a project too, without Worktrees, base branch and Carrier, and says why.
A project whose folder is gone shows a notice with Locate… and hides the disk.
Watching writes the project's `owner/name` to `engine.json`'s `repos`, read as it is when the page opens; removing a project never touches it, and the Repos page is unchanged.

Actions are commands kept with the project in Carrier and never read from the repository ([0039](../adr/0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)).
They run in a new worktree or after a clone, as steps of the preparation between the worktree and the agent, and again when a cleaned worktree comes back; each has a name, a command, an on switch and what happens if it fails (warn and continue by default, or stop the session).
They are the setup that [0035](../adr/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) left for later.

A project's name and icon are used wherever the project shows, not only on its page: the sidebar's groups, the rows of a session, the new session's picker and the rows of an epic whose repository is the project's `origin`.
An icon that is not set is drawn as it is today, with initials on a hashed colour; one that is set is a colour and a mark or an image, and the image is copied small into the app's folder.

A project's worktrees are the sessions whose base folder is its path.
The layout of `worktrees/` is unchanged, and adding a project whose worktree directory would be another project's is refused with the reason.

Removing a project asks whether it leaves only Carrier or its files go too.
Deleting from disk is offered only for what Carrier made, moves the folder and its worktrees to the Trash, and stops at uncommitted changes or branches not pushed unless the person confirms after seeing them, and does not go ahead while a session of the project is working, waiting or open; the idle ones stay as history with a notice that their folder is gone ([0040](../adr/0040-deleting-a-project-from-disk-is-only-for-what-carrier-made-and-goes-to-the-trash.md)).

## Scope

1. Settings has a Projects page in the Workspace group, between Sessions and Sidebar, in the Settings search, and with no projects it offers Add project.
2. A person adds an existing folder (Open a folder…, or dropping it) and it becomes a project whose page opens; adding a path that is already a project opens that one instead.
3. A path that is a folder inside Carrier's own, a file, a folder that cannot be read or a worktree of another project is refused with the reason, from Add project, from Locate… and from a drop.
4. In Settings, a person adds a repository from the Add project sheet by pasting an address, by searching their repositories, and sees where it will be cloned and can change that for this clone; the project appears in the list as cloning with its progress, and a failed clone shows its reason in its row.
5. In Settings, a person creates a new project with a name and a place, and it becomes a project.
6. A repository cloned, or a new project created, by a new session's first message becomes a project when the preparation succeeds; a folder that was already there and was fetched becomes one as added, and a folder chosen with Open a folder stays a plain workspace that offers Add as project.
7. The list shows the columns Project, Tags, Last active, Disk and Carrier, and is searched by name, filtered by tag, Watched, Local only and Hidden, grouped by tag or by Carrier, and sorted by name, last activity or disk with the pinned first.
8. A project's page lets the person rename it, pin it, set its tags, and choose its icon's colour and mark or an image.
9. A project's name and icon, when set, are what the sidebar's groups, the session rows, the new session's picker and the epic rows of its repository show; when not set they are drawn as they are today.
10. A person turns off "Show when starting a session" and the project leaves the sheet New Session opens, among projects and among suggested folders, and stays in the sidebar and in the list as hidden.
11. The agent, work in and base branch a project sets fill a new session draft when the project is chosen, win over Settings > Sessions, and can be changed in the draft.
12. The sheet New Session opens to choose where to work is the same one as Add project, lists the projects that are not hidden first with their icons, then the suggested folders and the person's repositories, and replaces the old chooser together with its list of what is in the projects folder and its Projects folder footer.
13. A project's page shows what it takes on disk (a total and a bar, the main clone and each worktree with its branch, session, age, state and size), measured in the background, with the last known figure shown meanwhile, and a worktree whose session is gone shown as having no session.
14. A person removes a worktree from a project's page and only its folder goes; it is refused with the reason while its session is open or it has uncommitted changes, and the next message of its session brings the folder back.
15. A person cleans up the merged worktrees in one action that says how many and how much first, and it takes the folders of those whose session's pull request is merged and that nothing blocks.
16. A person sets actions on a project, each with a name, a command, when it runs (in a new worktree, or after a clone), an on switch and what happens if it fails, from an Actions row that opens a screen of its own.
17. Actions run in order as steps of the preparation, after a clone or after the worktree and before the agent, each one shown in the session's steps, a failure that warns going on and one that stops failing the step with the reason, and Cancel stopping the one that runs.
18. Actions run again when the folder of a cleaned worktree comes back.
19. The Carrier switch of a project turns watching on and off in `engine.json`, shows an orange problem on its row when the change is refused or the config is invalid, says Carrier reads it when it starts if Carrier is stopped, and is off and explained for a project with no GitHub origin; removing a project does not change it.
20. Removing a project asks whether it leaves only Carrier or its files go too, offers the second only for what Carrier made, stops with the reason at uncommitted changes, branches not pushed or an open session, and moves what it deletes to the Trash.
21. A project whose folder is gone shows as not found in the list and a notice with Locate… on its page, and its disk is hidden; a folder that is not a git repository shows a project without worktrees, base branch and Carrier, saying why.
22. `projects.json` is read by the app and the host, written by both without losing keys they do not know, refused with the problem named when it does not match its schema, and an absent file is an empty list.
23. In New Session a choice made in the sheet only fills the plan and nothing is cloned or written until the first message, a repository to clone keeps "Let Carrier watch this repo" on by default, and in Settings Add project acts at once and does not watch.
24. The Projects page ends with a line saying where new clones go, with Change…, which writes `projectsFolder`, and the sheet shows each clone's destination with Choose… for that clone only.

## Decisions

**The file.** `projects.json` is at `<folder>/projects.json` with `engine.json` and `providers.json` ([0034](../adr/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)): its path in `src/config/places.ts` and its Swift twin `CarrierPlaces.swift`, its strict schema, reader and atomic writer in `src/config/projects.ts`, steps in [`src/config/AGENTS.md`](../../src/config/AGENTS.md#adding-a-config-field), and `docs/configuration.md`.
A bad file stops nothing: the host reads it as no projects and the session says so in a notice (an action that would have run did not), never writes over it, and the page shows the problem and does not write either.
The shape, trimmed to the decision:

```ts
type ProjectEntry = {
  path: string; // absolute or ~; the identity, never repeated in the file
  name?: string; // the folder's name when absent
  origin: 'cloned' | 'created' | 'added';
  pinned?: boolean;
  hidden?: boolean;
  tags?: string[]; // trimmed, lower case, no repeats
  icon?: { color?: string; mark?: string; image?: string }; // image: a file name in the app's project-icons folder
  defaults?: { agent?: string; workIn?: 'baseFolder' | 'worktree'; baseBranch?: string };
  actions?: { name: string; command: string; when: 'newWorktree' | 'afterClone'; on?: boolean; onFail?: 'warn' | 'stop' }[];
};
```

The schema refuses a repeated path, an empty or blank name or command, an unknown key, a wrong-typed field and an empty path; its test is a table of those and of the well-formed entries, and it writes `macos/Tests/Fixtures/projects.json` for `ContractTests.swift`, as `engine-config-contract.test.ts` does for the engine's file, so that `ProjectsFile.swift` parses, checks and writes the same.

**Who writes what.** The app writes what the person edits, and adding an existing folder, and keeps the keys it does not know, reading the file again just before writing.
The host writes an entry when a preparation that cloned or created succeeds, and when a project is cloned from Settings. `origin` is `cloned` only when the clone step ran in that preparation, `created` for a new project, and `added` for everything else, including a folder that was already in the projects folder and was only fetched; only the first two can be deleted from disk.
The app watches the file, since the host can change it while Settings is open.

**What the host answers.** The chat host gets requests behind one capability (`projects`) in its hello, following [`src/control/AGENTS.md`](../../src/control/AGENTS.md#adding-a-request-to-a-socket): a project's worktrees with their branch, session, state and size; removing a worktree's folder; cloning a project into a folder, with its progress; and the clones in flight.
A worktree is listed from `git worktree list` of the project's folder, kept to those under the chat's `worktrees/`, and joined to the session whose `worktreePath` it is; one with no session is listed with none.
Removing one is `previewWorktree` and `clearWorktree` of [0035](../adr/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md), the same ones `cleanWorktrees` uses, so it keeps the branch and refuses a dirty worktree or a live session.
The app that finds a host without the capability says the host is older and to restart it, as [0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) does.

**Merged.** A worktree is merged when its session's `prState` is `merged`, the rule `worktreeCleanup.afterPrMerged` already uses, so a squash merge counts and a worktree with no session or no pull request never enters Clean up, though it can be removed by hand.

**Size.** The host sizes a project with a walk of its folder and its worktrees, one at a time and in the background, and keeps the figure and when it was taken in a table of `chat.db`, which is rebuilt if it is lost.
A project's page asks for a fresh figure when it opens, the list shows the last known one and asks again for those older than a day, and a project never measured shows a dash.
The first slice ships with that, and the age is tuned after measuring real projects, which is a check and not a question.

**Actions.** A plan's steps gain `action`, run by `openPlan` after `clone` for the `afterClone` ones and after `worktree` or `checkout` for the `newWorktree` ones, before `agent`; `restoreWorktree`, where a cleaned worktree's folder is made again, runs the `newWorktree` ones too.
A command runs through a new port with a fake (as `git.ts` has `FakeGit`): `sh -c` in the folder of the step, with the host's environment, which is the shell's `PATH` the app detects for it, plus `CARRIER_PROJECT` (the project's base folder) and `CARRIER_FOLDER` (the folder it runs in).
It has no time limit, since Cancel on a preparation aborts the running step; its last line of output is the step's progress, like a clone's, and a failure carries the end of the output through the same redact-then-cut limits as a transcript (`transcript.ts`).
A failing action with `onFail` of `warn` leaves its step done with a notice, one with `stop` fails the step and the retry repeats from it.
An action with its switch off is skipped, and a preparation gets an `action` step only when the project has at least one action on for that moment: with none, no step is added and nothing is shown.
Actions are read from `projects.json` at each preparation, so a change is for the next one.

**Add project.** The sheet has two modes, Settings (a choice acts at once) and New Session (a choice fills the plan), over one model and one set of rows; the old `WorkspaceSheet`, the scan of the projects folder (`projectFolders(in:)`) and the sheet's footer are removed, and `NewSessionModel` and `settleWatches` stay, pointed at the new rows.
The model is a pure function of the query and the lists (the pasted address or path recognised, the repositories and folders filtered, a repository or folder already a project told apart, the first result chosen), in `CarrierCore`, with the choice by the keyboard in the view.
A path is checked by `checkProjectFolder` in `src/chat/folder.ts`, beside `checkProjectsFolder`, for what the host registers, and by its Swift twin next to `projectsFolderRefusal` in `WorkspaceSources.swift` for what the app adds; both tests share one table of paths.
The worktree directory rule (`<owner>/<repo>` or `local/<folder name>`, as `worktreePath` in `names.ts` makes it) is checked when a project is added, and a clash is refused with the reason.

**Remove.** The app moves the folder and the worktrees to the Trash with `FileManager.trashItem`, after asking the host for the project's worktrees again at that moment, and refuses on what that answer shows (uncommitted changes, a branch not pushed, a session working, waiting or open) unless the person confirmed the first two after seeing them.
The dialog's words are a pure function of that answer and the project's `origin`.

**Where the identity shows.** A pure function gives a tile from a path and the list (`ProjectIcon.swift`, `ChatSessions.swift`'s group title, the new session picker, and the epic row by the `origin` of the repository); two projects with one name keep the parent folder added to the group title, as the sidebar does for folders.
The image is copied by the app, reduced to 256 points, into `<folder>/app/project-icons/<random>.png`, and the entry names the file; it is removed with the project, and a missing file draws the colour and mark.

**What the page is.** `SettingsPage.projects` with `usesForm` and `isColumn` false, as Repos and Health, and a project and its Actions are places of Settings with a path (`SettingsPlace`, `SettingsTitle`), as Providers and Agents have; a list row, a tile, a chip, a select and a sort title reuse the pieces of [macos-ui](../macos-ui.md), and a piece that is missing is added there.
The row goes into `settingsIndex`, and `SettingsIndexDriftTests` keeps it.

**The watch.** The switch uses the writers and the rules of the Repos page (`applyingRepos`, `reposProblem` in `RepoList.swift`, the folder-name rule of watched repos) and the reload answer the other pages show, so the two pages cannot disagree about the file.

**The plan's `{project}` kind** (a new empty folder) keeps its value on the wire, since an older host would refuse another; its names in TypeScript and Swift change to say "new project", and the glossary says so.

**No migration.** Nothing reads the projects folder, the sessions or the engine's repos to fill the list.

**Testing seams, by story.**
Stories 1, 7, 8, 9, 12, 21: pure functions in `CarrierCore` with Swift Testing in `CarrierCoreTests` (`ProjectRows` for the list's filter, grouping, sort, status and not-found; `ProjectIcon` for the tile; the picker's lists in `NewSession`); the views are not tested and are looked at in the app with the `macos-ui-change` procedure, with the long name, the missing folder, an error and the empty list.
Stories 2, 3, 6: `checkProjectFolder` and its Swift twin on one table (`folder.test.ts`, `WorkspaceSourcesTests`); the sheet's model in `CarrierCoreTests`; `openPlan` registering an entry on success and not on failure or cancel, with `FakeGit` and the fake runner in `sessions.test.ts`; `projects.test.ts` for a clone from Settings and its progress.
Stories 4, 5, 22: `src/config/projects.test.ts` for the schema and the writer, the contract fixture with `ContractTests.swift`, `ProjectsFileTests` for the Swift side keeping unknown keys, and `ChatHostTests` and `FixtureServerTests` for the requests.
Stories 10, 11, 12, 23: `NewSessionTests` for what the sheet lists, that choosing only fills the plan and nothing is cloned, the watch choice with `settleWatches`, and what the draft is filled with.
Story 24: `WorkspaceSourcesTests` for the write of `projectsFolder`, and the destination shown for a clone in the sheet's model.
Stories 13, 14, 15, 20: `sessions.test.ts` and `worktree` tests on a real repository with `git.integration.test.ts` for the list, the join to sessions, the refusals and that the branch stays; the size table in `db.test.ts`; `server.test.ts` for the requests, the hello and the golden replies; the Remove dialog's words in `CarrierCoreTests`; the Trash move is not tested and is tried by hand.
Stories 16, 17, 18: `sessions.test.ts` with the new port's fake for the order, the two failure modes, Cancel, the skipped action and the restore; the Actions screen's model in `CarrierCoreTests`.
Story 19: `RepoListTests` extended for the switch, and the problem and stopped-Carrier words as pure functions.

## Out of scope

Adding several projects at once, with several folders in the open panel or several repositories ticked.
Detecting that a repository is already cloned somewhere Carrier does not know.
Scanning any folder.
Running actions in the engine's worktrees for an epic.
Changing the Repos page, or moving the agents' roles out of it.
Ordering by how many sessions a project has, dragging to reorder, and managing tags as things of their own (colours, renaming for all).
Notes, environment variables or secrets on a project.
Showing pull requests or CI.
Keeping projects in sync between Macs.
Creating the repository on GitHub for a new project, which [0015](../adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) already left out.
Importing the clones and sessions from before this version.
