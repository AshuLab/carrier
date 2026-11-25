# A new worktree starts from the remote branch

Status: spec

## Problem

A session opened in a new worktree is cut from the person's local branch, and the local branch is whatever it was the last time the person updated it.
`createWorktree` (`src/chat/worktree.ts`) starts from `refs/heads/<name>` unless the person picked a remote branch by hand, and Carrier's own fetch (the "Update the repository" step and the picker's "Fetch now", both `git fetch origin --prune`) only moves `origin/*`, never the local `main`.
So a worktree can be cut from a `main` that is far behind `origin/main` even right after a fetch.

It showed up in the sidebar: a session in which nothing had been done yet listed +13,769 −3,024 on 549 files.
The worktree had been cut from a `main` 143 commits behind, and the sidebar counts a session's lines from the merge-base with the local `main` (`baseOf` in `src/chat/session-data.ts`), so everything that had landed on `origin/main` since counted as the session's work.
The person sees a diff they did not make, and the agent starts on code that is already out of date, which comes back later as conflicts.

The same stale `main` is what the person gets whenever they have not pulled lately, and nothing in the new-session screen says so: the picker lists local branches first, shows no hint of how far behind they are, and a folder that is not a GitHub project Carrier cloned is never fetched at all when the message is sent.

## Solution

A new worktree is cut from the remote copy of the branch, `origin/<branch>`, by default, and the person can choose the local branch instead.
Where it starts is one setting with a per-session override, so the behaviour the person wants is the one they get without choosing it each time.

**The setting.** `worktreeStart` in `chat.json`, `remote` or `local`, `remote` when the file does not say.
It lives in `chat.json` and not in the app's preferences because the chat host is who fetches and cuts and the host cannot read the app's preferences ([config levels](../glossary.md): a setting lives where its reader is, and no process reads another's level).
The host reads it fresh at each preparation of a plan, the way it reads the session ages (`currentAges`): a change of the file between two sends is honoured without a restart, and a file that is wrong keeps the last value that was good.

**The plan.** The `worktree` of a session's plan (`src/chat/plan.ts`) gets an optional `startFrom`, `remote` or `local`, next to the `name` it has.
When it is absent the host applies the setting; when it is present it wins, so a session's own choice never writes the setting.
The plan's `branch` stays the name of the branch to start from as `workspace` lists it: with `startFrom: remote` the host cuts from `origin/<branch>`, with `local` from `<branch>`.
A `branch` that already carries `origin/` (a remote branch named by hand, as today) is cut from that ref and `startFrom` is ignored.
The host advertises a new capability, `worktreeStart`, because the plan schema is strict and an older host would refuse the field: the app asks for the capability the way it does for the host's other features, and, for a host without it, sends no `startFrom` and names a remote start the way it always could, as `branch: origin/<name>`.
The older `open` request, which carries its own `worktree: { from, name }`, is not changed: its `from` already names the exact ref.

**The cut.** With a remote start, sending checks, for a folder the person already had, that the last fetch of `origin` is within the freshness window and, when it is not, runs it first as the plan's `fetch` step, which that kind of workspace gets for the first time.
A GitHub project already has its own step (`bring`, which fetches or clones) and keeps it exactly as it is, including that a fetch that fails fails the step.
The worktree is then cut with `git worktree add --no-track -b carrier/<name> <path> refs/remotes/origin/<branch>`.
The freshness window is five minutes, one constant of the host (the engine's own default poll is five), and the fetch keeps `fetchFolder`'s timeout and its refusal to prompt for credentials.

**The fallback.** For a folder the person already had: if the fetch fails or times out, or `origin/<branch>` does not exist, the worktree is cut from the local branch, the `fetch` step ends as done (a failed step would end the preparation, and the app only shows the reason of a failed one), the send goes ahead, and the session stores a `notice` (the kind the host already stores when it cannot reach the agent's tools or finds a conversation lost) that says the worktree started from the local branch and why, with how many commits it is behind `origin/<branch>` when that is known (counted by the host's own `rev-list --count` of the two refs).
A folder's session is never refused because the remote could not be reached.
A branch that exists only locally, never pushed, is cut from local with no notice, since there is nothing else to start from.

**What a session records.** `worktreeFrom` holds what was cut from (`origin/main` or `main`), and `baseOf` takes the merge-base with the most recent of the local and the remote copy of that branch, and accepts a name that already carries `origin/`, so the sidebar's count starts at zero for a session cut from the remote.
That also fixes sessions that were already cut from a stale `main`, which no new default reaches.

**Choosing a project.** Selecting a project that is a git repository with an `origin` fetches it in the background.
The `fetch` request gets an optional `ifStale`, and the host a capability `fetchIfStale` for it (the schema is strict, so the app sends it only to a host that lists it): when it is true and the last fetch is within the window the host skips the git call, and either way it answers with the current `workspace` reply.
The app asks with `ifStale: true` when a project is chosen: the branches show at once from what is on disk, the spinner that already marks branches loading runs next to the project's chip, and the picker is current when it ends.
A fetch that cannot reach the remote says so in the picker's footer ("Could not reach origin", with when the branches were last fetched) and nothing else: no error, no prompt.
This is the one place where choosing a folder writes to it, and only `FETCH_HEAD` and the `origin/*` refs, never a branch, the index or the working tree ([0037](../adr/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md)). "Fetch now" stays as it is and ignores the window.

**Behind and not pushed.** A local branch that has a counterpart on `origin` carries in the `workspace` reply how many commits it is `behind` and how many are `ahead` (not pushed); one without a counterpart carries neither, which is how the picker knows it is "not on origin".
A repository with hundreds of branches must not make `workspace` slow: the counts are computed in one pass where git allows it and measured on a large repository before the slice is done.

**Settings.** In Settings > Sessions > New sessions a row "Start from", under "Work in", with "Remote branch (latest)" and "Local branch", detail "Where a new worktree is cut".
It is off, with its reason ("Only for a new worktree"), while "Work in" is the base folder.
The group's footer adds that Remote fetches the branch first and falls back to the local one if it cannot be reached.
The page's Reset puts the row back to Remote, as it does "Work in".
The key is written the way the session ages are (`applyingSessionAges`'s family in `CarrierCore`): the file's other keys are kept, a value equal to its default is left out, a file that is not a JSON object is never overwritten.

**The picker.** In `BranchSheet` the two sides are tabs, Remote and Local, under the search field: one list at a time, so a branch is never offered twice.
The setting decides which tab is open when the picker opens, and the tab the person leaves it on is the session's choice, sent as `startFrom`.
A local branch with a counterpart on `origin` shows "N behind origin" and "N not pushed" when they are not zero; one without it is only in the Local tab, marked "not on origin".
The summary under the list names the ref the branch will be cut from and, with Local chosen, warns when the branch is behind.
The "from" chip of the sentence says `origin/main` or `main`, in the colour of the side it means, and the send steps gain "Bring the latest origin/main" ahead of "Create a branch of its own" when the start is remote.
For a repository that is not on this Mac yet (the branches come from GitHub and a fresh clone follows the pick) there is no local side to choose, so there are no tabs and the list is the one the sheet shows today.

What lost: keeping the local branch as the start and only warning (the drift stays); remote with no way to choose local (a person with commits not pushed could not start from them without naming a branch by hand); a toggle inside the picker over a merged list, prototyped (it repeats what choosing `origin/main` already means, and the toggle and the name can disagree); two sections with no control, as the picker is today (the remote copy is a scroll away and the default cannot be chosen); fetching only the chosen branch (a second fetch mechanism next to the one that exists); refusing to send when the fetch fails (it blocks offline work for a problem the notice explains); a start recorded as a fixed commit at creation (it breaks the moment `main` is merged in); a setting per repository (nothing asks for it); the app's preferences as the setting's place (the host cannot read them).

## Scope

1. A person who has not set anything gets new worktrees cut from `origin/<branch>`, and the sidebar shows +0 −0 for a session in which nothing has been done yet.
2. A person can set `worktreeStart` to `local` in `chat.json`, and new worktrees are then cut from the local branch with no fetch; any other value or type is refused by the config's load with the reason, as the file's other keys are.
3. The `worktree` of a plan accepts `startFrom`, and the host reports the capability `worktreeStart`; without the field the setting decides, with it the field does.
4. Sending a plan with a remote start for a folder the person already had fetches `origin` first when the last fetch is older than five minutes, and does not fetch when it is newer; a GitHub project's own fetch or clone step is as it was.
5. When that fetch of a folder fails or times out, or `origin/<branch>` does not exist, the worktree is cut from the local branch, the fetch step ends as done, the send goes ahead, and the session shows a notice that says so with how far behind the branch was; a branch that exists only locally is cut from local with no notice.
6. A `fetch` request with `ifStale: true` skips the git call within the window and answers with the current `workspace` reply either way; without `ifStale` it fetches as it does today.
7. The `workspace` reply says, for each local branch that has a counterpart on `origin`, how many commits it is behind and how many are not pushed, and says nothing of either for one that has none.
8. The sidebar counts a session's lines from the merge-base with the most recent of the local and the remote copy of its start branch, for a worktree whose `worktreeFrom` is `main` as well as for one whose is `origin/main`.
9. Settings > Sessions > New sessions has a "Start from" row that reads and writes `worktreeStart`, is off while "Work in" is the base folder, and is put back by the page's Reset.
10. Choosing a git project in the new-session screen fetches it in the background, shows the branches at once and the spinner while it runs, and says in the picker's footer when the remote could not be reached.
11. The branch picker has the Remote and Local tabs, opens on the one the setting says, marks local-only branches "not on origin", shows how far behind or ahead a local branch is, and sends the tab it was left on as `startFrom`; the sentence's chip and the send steps say where the worktree will start.
12. The docs say it: `docs/macos/settings.md` (the new row and Reset), `docs/macos/new-session.md` (the picker, the chip, the steps, the fetch on choosing), `docs/specs/session-worktrees.md` (the plan's `startFrom`, `fetch`'s `ifStale`, the `workspace` counts and the capability) and `docs/configuration.md` (`worktreeStart`).

## Decisions

Implementation calls above are the spec's; the ones a ticket must not reopen:

- The setting is `chat.json`'s `worktreeStart` and the per-session choice is the plan's `worktree.startFrom`; the app never writes the setting from a session's choice. [0037](../adr/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md) records why.
- The freshness window is five minutes, one constant in the host, used by the send step and by `fetch`'s `ifStale`; the app does not keep its own copy of it.
- The fallback is a `notice` of the session, as the host's other notices are, and never a refused send for a folder; the `fetch` step it falls back from ends as done.
- The host reads `worktreeStart` fresh at each preparation, through the same path as the session ages.
- `baseOf` ships as its own slice, independent of the default: it needs no other part of this epic and no part needs it.
- The shape of the `workspace` additions: `ahead` and `behind` optional on a local `branches` entry, absent when there is no `origin` counterpart.

```ts
// plan.ts: the worktree of a plan
worktree: z.strictObject({ name: z.string().max(1000).optional(), startFrom: z.enum(['remote', 'local']).optional() }).optional()
// chat config
worktreeStart: z.enum(['remote', 'local']).default('remote')
// server.ts: the fetch request
z.strictObject({ id, cmd: z.literal('fetch'), folder: z.string().min(1), ifStale: z.boolean().optional() })
```

These are strict: a value other than `remote` or `local`, or a non-boolean `ifStale`, is refused by the schema, and a missing field means the old behaviour.

Testing seams, by story:

- Story 2: `src/chat/config.test.ts`, the config's load test (default, `local`, a value that is neither, a wrong type, an unknown neighbour key kept).
- Stories 1, 3, 4, 5: the host through the interface its socket uses, with the fake runner and `FakeGit` (`src/chat/sessions.test.ts`, `host.test.ts`): the plan in, the steps and the `git` calls out (which ref the worktree was cut from, whether a `fetch` ran, the notice after a failed one).
  This is the broadest seam and carries the behaviour.
  `src/chat/worktree.test.ts` covers `createWorktree`'s start ref alone, and `src/chat/server.test.ts` the strict schemas and the capability.
- Story 1 against real git: one case in `src/chat/git.integration.test.ts` with a clone whose local `main` is behind, checking the worktree's first commit is `origin/main`'s.
- Stories 6, 7: `src/chat/workspace.test.ts` (`fetchFolder` skipping inside the window, `inspectFolder` with and without a counterpart) and `server.test.ts` for the request.
- Story 8: `src/chat/session-data.test.ts`, its fake git keyed by arguments, which already has the merge-base cases.
- The capabilities `worktreeStart` and `fetchIfStale` are in the host's list (`server.ts`), in the app's `ControlClient.Capability` and in the fixture server's hello, so fixture mode behaves as a current host.
- Stories 9, 10, 11, in the app's logic: `macos/Tests/CarrierCoreTests` (`WorktreeChoiceTests` for the picker's tabs and badges, `NewSessionTests` for the model's default, `startFrom` and send steps, the writer of the key beside `SessionAgesTests`).
  The SwiftUI views themselves have no tests of their own: they are checked by the `macos-ui-change` procedure against fixtures, every state of the row and the picker, and `docs/ui.md` is updated if a pattern changes.
- Story 12: no tests; the docs are read in review.

## Out of scope

"Current folder" is not touched: Carrier does not pull, merge or switch the branch of the person's folder to bring it up to date (its branch switch stays as [0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) has it).

No per-repository setting for where a worktree starts.

A worktree that already exists is not moved or rebased onto the new `origin/<branch>`; only the sidebar's count of its lines changes, through `baseOf`.

Updating the person's local `main` (a fast-forward of `refs/heads/main`) is not done, here or at fetch time.

The engine's own worktrees and lanes, which are cut from what the epic says.

The `open` request's own `worktree: { from, name }`, which cuts from exactly the ref it names, as today.

A GitHub project's own fetch or clone step: it keeps failing the session when it cannot reach GitHub, and does not fall back to the copy on disk.
