# A session is prepared when the first message is sent

Status: implemented (v0.1.0)

## Problem

Choosing where a session works already does things. Picking a repository in the workspace chooser clones it on the spot and, with "Let Carrier watch" on (the default), writes it into the engine's `repos`; New project makes its folder at "Create and use". Nothing has been said to an agent, and a person who changes their mind has no way back: the draft is one long-lived object that keeps its workspace, its worktree choice and its name, so opening New session again shows the same thing, the + does nothing while the draft is open, and after a message is sent only the text is cleared, so the next send would ask for the same worktree name again.

The owner wants sessions to be nearly disposable: the person chooses everything and nothing exists until the first message, which is when everything the session needs happens, in the open, step by step, until the agent answers. We know it works when opening New session always shows a blank draft, choosing anything in it changes nothing on the machine, and sending the first message shows a list of steps that ends with the agent's answer, and a failed step can be read and retried.

## Solution

The draft is a plan and the host prepares it, as [0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) decides; the terms are in the glossary (New session draft, Preparation). It replaces the sentence of the [workspace sources spec](workspace-sources.md) that has the clone happen when the repository is chosen.

**The draft.** The plan is a value: a folder that exists, a repository to clone, or a new project; the branch to be checked out, the worktree and its name; the agent and its options; the text. Choosing and editing it does nothing on the machine: no clone, no project folder, no write to the engine's config. Every opening of New session, including the + while it is open, starts from a blank plan, and the workspace chip has a ✕ that clears the choice. After a message is sent the draft is blank again. For a repository to clone the draft offers a worktree from a branch like any other: the branches come from the host asking GitHub with the person's `gh` login (a new read-only request), the worktree name is left empty and said to be generated when the message is sent, and there is no uncommitted-changes line, since a fresh clone has none. A repository that is already on disk is read locally as today. A new project offers neither branch nor worktree, as it has no commits.

**The send.** The first message is one `open` carrying the plan. The host creates the session at once, in a `preparing` state, so it shows in the sidebar, and returns it; then, in the background and independent of the connection that asked, it runs only the steps the plan needs, in this order: `clone` (or `fetch` when the repository is already in the projects folder) or `project`; `worktree` or `checkout`; `agent`; `message`. The conversation shows the steps as a list that fills in: each is running, done or failed, with a line in words, and the list ends when the agent answers (the `message` step is done at the first answer). While the clone runs, the line under it follows git's own progress ("Receiving objects: 45%"), so a large repository is seen to move. The host does not exit its idle close while a session is preparing.

**A step fails.** The preparation stops, the session stays with the failed step and its reason in words, and the first message is kept. The session is idle and not live, which is all the lifecycle clock ([#636](https://github.com/AshuLab/carrier/issues/636)) looks at, so a session that never prepared is archived and deleted like any other, with the same check for unsaved work. "Try again" repeats the steps that did not finish and reuses the clone, the fetch, the project folder and the worktree already made, never making them twice. The list is persisted with the session: after a restart of the host the person still sees which step failed, and a session that was preparing when the host stopped comes back with its running step failed as interrupted.

**Cancel.** While preparing, Cancel stops the step that is running and deletes the session as any other delete does: a half clone is removed (a clone that finished stays in the projects folder, as a cache), the worktree of this send goes with the session. The app puts the plan and the text back in the draft so nothing typed is lost.

**The checkout.** It follows what the person picked whenever the workspace is a git repository. A repository just cloned and a worktree are Carrier's own, so they always follow the pick. A folder that already existed follows it too, unless it has uncommitted changes: then the `checkout` step fails with the reason, because Carrier never takes the branch from under unsaved work, and the person can save the work and try again. The draft says beforehand that the folder's branch will change, and when the folder has uncommitted changes that this step will fail.

**Watching.** "Let Carrier watch the repo I choose" stays as a choice in the plan. The app adds the repository to the engine's `repos` when the `message` step is done, never before, and says Carrier applies it now or will listen from the next start, depending on whether the engine lists `reload`. Deleting the session undoes neither the clone nor the watch.

**The older host.** The host lists a capability `plan` in its hello for the `open` that carries a plan and for the two requests below, and `repoBranches` for the branches. The `open` that exists, a folder and a worktree, keeps working for an older app. An app that finds a host without `plan` does not offer the new draft: it says the host is older and to restart it, as the Health tab does, since the app already replaces an old idle host. The old eager path in the app is deleted, not kept. The requests `cloneRepo` and `createProject` stay for older apps; the app stops calling them.

What lost, besides what 0018 lists: a draft that keeps its side effects when an older host is found, which would keep two draft behaviours in the app for a case the host replacement already covers.

## Scope

1. As a person, opening New session, by the menu or the + while it is open, always shows a blank draft, and choosing a repository, a project or a folder in it changes nothing on my machine.
2. As a person, the workspace chip has a ✕ that clears what I chose.
3. As a person, sending the first message shows the session in the sidebar at once and, in its conversation, a list of steps that fills in and ends when the agent answers.
4. As a person, the clone step shows git's progress while it runs, and a repository that is already in the projects folder is fetched instead.
5. As a person, I can choose a worktree from a branch for a repository that is not on my disk yet, with the branches read from GitHub with my login and the name generated when I send.
6. As a person, the branch I picked is the one checked out; if the folder already existed and has uncommitted changes the draft warns me beforehand and the step fails with the reason instead of changing my branch.
7. As a person, when a step fails I read why, my message is still there, and Try again repeats only what did not finish; it is still so after the host restarts.
8. As a person, Cancel while preparing stops the running step, leaves no half clone, deletes the session with its worktree, and gives me back the draft with my text.
9. As a person, a repository I let Carrier watch is added to the engine's `repos` only when the agent has answered, and a clone stays in the projects folder when I delete the session.
10. As a person, a new project is created when I send, not when I choose it, and offers no worktree.
11. As a person, a session whose preparation failed and was left alone is archived and deleted by the clock like any other.
12. As a person reading the docs, I find that New session does nothing until the first message, what the steps are and what Try again and Cancel do.

## Decisions

The plan, as the host's strict request takes it (it replaces `agent`, `folder`, `options` and `worktree` of the old `open`, which is still accepted on its own and never together with `plan`):

```ts
const branch = z.string().min(1).max(1000).regex(/^[^-\s][^\s]*$/); // never a leading dash (it would be an option of git) nor whitespace
const workspace = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('folder'), folder: z.string().min(1) }),
  z.strictObject({ kind: z.literal('repo'), repo: z.string().regex(repoNamePattern) }),
  z.strictObject({ kind: z.literal('project'), name: z.string().regex(projectNamePattern) }),
]);
const plan = z.strictObject({
  workspace, agent: z.string().min(1), options: z.record(z.string(), z.string()).optional(), text: z.string().min(1),
  branch: branch.optional(), worktree: z.strictObject({ name: z.string().max(1000).optional() }).optional(),
}).refine((p) => p.workspace.kind !== 'project' || (p.branch === undefined && p.worktree === undefined)); // a project has no commits
// open: z.strictObject({ id, cmd: z.literal('open'), plan })   next to the old open
// cancelPreparation, retryPreparation: z.strictObject({ id, cmd, sessionId })
// repoBranches: z.strictObject({ id, cmd: z.literal('repoBranches'), repo: z.string().regex(repoNamePattern) }) -> { default, branches: string[], hasMore }
```

Run against the inputs the stories take: `text: ""`, `branch: "-x"`, `"a b"` and `""`, `repo: "a/../b"` and `""`, a project with a branch or a worktree, and a request with both `plan` and `folder` are all refused; `"main"` and `"feat/x"` are accepted. The host's text limit (`chatCaps.message`) applies to `text` as it does to `send`.

The steps are events of the session, one `chat_events` row per transition, kind `step`, with `data` of this shape. The progress of the clone is not stored (as a `delta` is not): the `events` reply carries the latest line in `progress`, null when there is none, and only lines that match git's progress (`Counting`, `Compressing`, `Receiving`, `Resolving` or `Updating` followed by `…: <n>%`) are passed on, one per second at most, since git's stderr can hold a URL and is never forwarded as it is.

```ts
type Step = 'clone' | 'fetch' | 'project' | 'worktree' | 'checkout' | 'agent' | 'message';
type StepEvent = { kind: 'step'; step: Step; status: 'running' | 'done' | 'failed'; detail?: string }; // detail: the reason in words, never git's raw stderr
```

The session row gains `plan` (the plan as stored, with the text, cleared when the `message` step is done; the migration is generated with `pnpm db:generate`), and the state `preparing`; its summary says `preparation: 'running' | 'failed' | null`. The host's `Git.run` gains an `onProgress` callback for the clone, and `cloneRepo` takes the signal of each preparation as one more waiter, as it already does for a request, so two preparations of the same repository share one clone and the clone stops only when nobody waits for it. The `repoBranches` request uses the person's `gh` login and the same listing port as `githubRepos`.

The lifecycle epic also adds a migration to `chat.db`: the two are built one after the other, the lifecycle first, or their migrations collide.

Testing seams, per story:

- 1 and 2: `NewSessionTests` with the fake host those tests use: the draft is blank after `load()` and after a send, ✕ clears the workspace, and choosing a repository or a project makes no call to the host's `cloneRepo` or `createProject` and no write to the engine's config.
- 3, 5, 6, 7, 8, 10 and 11: `createSessions` in `sessions.test.ts` with the fake clock, `FakeGit` and the fake runner those tests use: the steps recorded for each kind of plan, a failure at each step and the retry that reuses what was done, the dirty and the clean folder at the checkout, a cancel in the middle of a clone and of the worktree, a session preparing when the host stops, the old `open` unchanged, and that a failed session reads `idle` and not live. This is the broadest seam and carries most of the behaviour.
- 4: `projects.test.ts` with a `FakeGit` that feeds progress lines: the allowlist, the rate and a fetch instead of a clone.
- 5 (branches): `projects.test.ts` or `github-repos.test.ts` for `repoBranches` with the fake GitHub port.
- The requests: `server.test.ts` for the strict union, with the values above, and the hello's `plan` and `repoBranches` capabilities.
- 3, 7 and 8 (the app): the pure function that turns step events into the rows of the list, in `ChatConversationTests` or beside `TranscriptItems`; the model's send, retry and cancel, and the plan coming back to the draft, in `NewSessionTests`; the decoding of `step` events and `preparation` in `ChatHostTests`. The views have no automated test.
- 9: `NewSessionTests` with the fake config writer: nothing is written before the `message` step is done, and the repository is written once after it.
- 12: no tests, docs.

## Out of scope

Running a repository's own setup (installing dependencies, a script of its own): it is another decision with other questions. Progress for steps other than the clone. Deleting clones, with or without sessions: the projects folder is the person's. Creating the GitHub repository for a new project. The aging and deleting of sessions by time, which is [its own epic](session-lifecycle.md). Changing what a session does after the agent answers.
