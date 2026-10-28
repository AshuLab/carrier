# Workspace sources for a new session

Status: spec

## Problem

Choosing where a new session works offers recent folders and Open folder…, and that is all. Diego opens New session wanting to talk to an agent about a project and either has it in some folder he has to go and find, has it only on GitHub, or has nothing yet; in the last two he must prepare a folder by hand before the draft lets him start. The config's six repositories, which he expected to find in the picker, are not an answer: they carry only `owner/name`, the clones that exist for them are the engine's and the chat host refuses them by design, and they are the list of what Carrier watches, not of what he talks about.

What hurts is the distance between "I want to work on this" and a folder the chat can use, for a project that is on GitHub or does not exist yet. We would know it is fixed when a session can start from a GitHub address, from a repository picked in a list of his own, or from a new empty project, in the draft and with no step outside the app.

The sessions spec deferred exactly this ("Clone, new repository and empty-folder workspaces, and repositories from Carrier's list in the picker"), and the glossary's Workspace already promised "a GitHub clone"; this is that deferred piece.

## Solution

Choosing the workspace opens one popover that drills in ([the prototype](../research/macos-app-design/explorations/workspace-sources-options.html), option A): recent folders, what is in the projects folder, and four sources, each a step inside the same popover with a way back: a local folder (the system's panel, as today), a GitHub URL, the person's GitHub repositories, and a new project. A sheet with a tab per source and a card that unfolds under the sentence were drawn and lost: the sheet leaves the draft for what is, most of the time, picking a recent folder, and the card is a new idiom that pushes the box around, while a popover is what the branch picker already is.

What the chat brings onto the Mac lives in one projects folder, `<CARRIER_HOME>/chat/projects` by default and changeable in the config, a clone at `<owner>/<repo>` and a new project at `local/<name>`, the layout the session worktrees already have ([0015](../adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)). Carrier fetches there and never deletes. The popover's footer says where the folder is and offers to change it; the change is written to the config and the next clone or new project already uses it, with no restart.

The clone happens when the repository is chosen, not when the first message is sent, so the sentence can show the branch, the uncommitted changes and the worktree choice the draft already has. While it runs the sentence says "Cloning…" and the box waits; when it fails the chip stays orange and the reason is in words (not found or not visible to this login, `gh` missing or signed out, no network, too slow). Cancel stops it and leaves nothing behind. A repository already in the projects folder is fetched and opened, not cloned again.

GitHub is reached with the person's own login, the account that is active in `gh`, to list and to clone, never with the engine's profile. The list is every repository that login can read, newest push first, thirty at a time with a Load more button, a notice that the list is partial and a search over what is loaded, as the Repos tab's Add repo picker already does; for a repository that is not loaded the URL step is the way to it. The chat host does the listing and the cloning, as its own requests with capabilities, so the chat does not depend on the engine running. Repositories already in the config carry a "watched" tag in the list.

Carrier watching a repository is a choice made at the moment of bringing it in: a checkbox "Let Carrier watch this repo", on by default, in the URL step and under the list. Choosing it adds the repository to the config's `repos`, which the engine reads when it starts, so the app says it will listen from the next start and restarts nothing. The checkbox is off, with the reason, when the repository cannot be added (it is already watched, or its folder name is the one of another watched repo, which Solve's worktree paths forbid), exactly as the Repos tab's picker refuses it. A new project has no checkbox: it has no GitHub repository, and creating one is left out. The config's repositories are not offered in the picker; a person who has one of them cloned finds it through the list or the URL like any other.

A new project is asked for a name only, shows the path it will create, makes the folder, runs `git init` on `main` and opens it as the workspace; having no commits, it offers no worktree until it has one.

It is one epic, built so that a slice of it can ship alone: the projects folder with the URL step and the new project first, the list after.

## Scope

1. As Diego, choosing the workspace chip opens a menu with the recent folders, what is in the projects folder, Open local folder…, From a GitHub URL…, My GitHub repositories… and New project…, and a footer that says where the projects folder is.
2. As Diego, Open local folder… and the recent folders work as they do today.
3. As Diego, in the URL step I can write `owner/repo` or a github.com address (with or without `.git`, a trailing slash or `https://`), and the button stays off until the text is one repository.
4. As Diego, choosing "Clone and use" clones the repository into the projects folder, the sentence says "Cloning…" while it runs, and when it ends the draft shows the branch, the uncommitted changes and the worktree choice for it, as for any folder.
5. As Diego, a repository that is already in the projects folder is fetched and opened, and the step says so beforehand instead of cloning again.
6. As Diego, a clone that fails tells me why in words (not found or not visible to my login, `gh` missing or signed out, no network, too slow), keeps the chip orange and lets me try again; Cancel stops a clone and leaves no partial folder.
7. As Diego, My GitHub repositories shows the login I am signed in with and every repository it can read, newest push first, thirty at a time with Load more, a notice while the list is partial, a search over what is loaded, a lock on private ones and a "watched" tag on the ones in the config; choosing one clones it as in story 4.
8. As Diego, when the list cannot be read (`gh` missing, signed out, offline) the step says so in words, and a page that fails after the first keeps what is loaded and offers to try again.
9. As Diego, New project asks for a name, shows the path it will create, refuses a name that is taken or not a plain folder name, makes the folder with `git init`, and opens it as the workspace without offering a worktree.
10. As Diego, "Let Carrier watch this repo" is on in the URL step and under the list, adds the repository to the config's `repos` when I go on, and the draft says Carrier will listen from its next start; it is off, with the reason, for a repository that is already watched or that cannot be added, and absent in New project.
11. As Diego, the footer's Change… lets me pick another projects folder, writes it to the config, and the next clone or new project goes there while what is in the old one stays.
12. As Diego, the chat host refuses a projects folder that lies inside the shared root's `repos`, `worktrees` or `orchestrator`, and says why.

## Decisions

The host gets three requests, each with its own capability so an older host is told apart (the app asks for the capability before showing the step, as it does for the engine's):

```ts
z.strictObject({ id, cmd: z.literal('cloneRepo'), repo: z.string().regex(repoNamePattern) }),
z.strictObject({ id, cmd: z.literal('githubRepos'), page: z.int().min(1).max(100) }),
z.strictObject({ id, cmd: z.literal('createProject'), name: z.string().regex(/^\w[\w.-]{0,99}$/) }),
```

`repoNamePattern` is the config's (`owner/name`, no `..` part), so an empty, dotted or slashed value is refused at the socket and a path never leaves the projects folder; the project name pattern refuses empty, `.`, `..`, a leading dot and a slash. `cloneRepo` answers `{ folder, repo, fetched }` (`fetched` is true when the repository was already there); `githubRepos` answers `{ repos: [{ name, private, pushedAt }], hasMore }` and, on page 1 only, the `login`; `createProject` answers `{ folder }`. The app turns what the person types into `owner/repo` (the URL forms of story 3) before it asks; the host takes only that form.

The listing is the engine's `ghReposArgs` made a function of what it keeps: `affiliation` adds `collaborator` (owner, collaborator, organization member, which is what `user/repos` returns by default) and the `permissions.push` filter is dropped for the chat, so every readable repository comes, still thirty a page and still `hasMore` from the raw page. The engine's own picker keeps its filter and its code path. The host takes the call as a dependency, as it does `git`, so its tests inject a fake.

The clone and the fetch use the person's token from `gh auth token`, handed to git in the environment (`GIT_CONFIG_*` with `http.extraHeader`), never in argv, in a file or in a log, as `git-workspaces.ts` does for the engine; git's own stderr, which can hold a URL, is not forwarded as it is. `Git.run` gains an `env` and a `signal` for this. Each git command gets the engine's ten minutes. A clone runs on the request's own connection: when the client closes it (Cancel, or the app going away) the host aborts git and removes the destination only if this request made it. The same repository asked twice while it clones shares one clone.

The projects folder is `chat.projectsFolder` in the config, absolute once `~` is expanded, default `<CARRIER_HOME>/chat/projects`; the `chat` block's `agents` becomes optional so the block can hold either. The host reads it from the config file at each `cloneRepo` and `createProject` (it learns the file's path when it starts), which is what lets a change in the app apply without a restart; a value inside the engine's `repos`, `worktrees` or `orchestrator` is refused with a reason (`checkFolder`'s rule applied to the projects folder). A folder is a repository clone when it has `.git` and its `origin` is that repository; any other thing at that path stops the clone with a reason instead of being overwritten.

The app writes the config in place as it already does for Behavior and Repos: it reads the file just before writing, `applyingRepos` adds `{ "name": … }` and refuses what `reposProblem` refuses, and a key the app does not know is left as it was. Changing the projects folder is the same write on `chat.projectsFolder`.

Testing seams, by story. The host's are the existing ones: `server.test.ts` drives a request through the socket with fakes (stories 3 to 9, 11 and 12: strict shapes, capabilities, replies, refusals), the `Git` port with `FakeGit` in `fake.ts` covers the clone, the fetch, the cleanup after a failure or an abort, and the shared clone (4 to 6), `folder.test.ts` covers the engine-folder rule on the projects folder (12), and the config's own `load.test.ts` covers `chat.projectsFolder` and the optional `agents`. A `git.integration.test.ts` case against a local bare repository checks that a real clone and a real abort leave what the tests say, and a gated test with the real `gh` (skipping itself without its variables, as the others) checks that the listing returns private and organisation repositories (7). The app's are the existing ones too: a pure `repoReference(_:)` in CarrierCore turns the URL forms into `owner/repo` or nil (3), the picker's model (states of each step, the watch checkbox and its reason, the clone and the failure, `AvailableReposList`'s paging reused for the list) is tested against a fake `ChatHost` in `NewSessionTests`' style (3 to 10), the new requests are checked against golden files in `DevFixtures` served by `FixtureServer` as `ChatHostTests` does for the others (4, 7, 9), and the config writes are tested like `EngineConfigTests` and `BehaviorSaveTests` (10, 11). The popover's views have no automated test, like the rest of the shell's layers; `--smoke-window` prints what the picker offers, as it does for the draft.

## Out of scope

Creating the GitHub repository for a new project, and so watching it. Showing or choosing among the config's repositories as workspaces. Moving, renaming or cleaning what is in the projects folder, and deleting a clone when a session is deleted. Choosing among several `gh` accounts: it is the active one. Cloning private repositories with credentials other than the person's `gh` login. A search against GitHub for a repository that is not in the loaded pages. Changing how the engine clones or what it watches, beyond adding a repository to the config's `repos`. Anything in the draft that is not the workspace: the agent chip, the options and the first message.
