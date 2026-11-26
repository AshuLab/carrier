# Worktree state says where the work is

Status: spec

## Problem

The Worktrees and disk group of a project's page gives each worktree one chip, the first that applies of Session open, Uncommitted changes, Merged, Not pushed and Clean, and the person cannot trust it.
On 2026-11-25 in AshuLab/carrier, `fix/session-clock-current-turn` said Clean while its pull request #1495 was merged, `tactical-firebat-academy` said Clean with everything it held already in `origin/main`, and `nuclear-goliath-nydus` said Session open and so hid that its pull request #1496 was still open.
Diego knew which were merged and the list did not agree, so he cannot use it to decide what to remove.

Two causes, both read from the code and the chat database.
First, "Merged" comes only from the pull request state saved on the session (`found?.prState === 'merged'`, `src/chat/sessions.ts`), and that state goes stale: the sweep that refreshes it runs only for sessions that are not archived (`if (archived === false) data.kick(found)`) and only for pull requests saved as open, so the archived session of #1495 kept `open` from 18:32.
Second, one chip mixes two different things, what is happening now (a session is open, files are uncommitted) and where the work stands (merged, pushed, only local), so an open session hides whether its work is already in main, and Clean means "nothing to lose" without saying whether it is integrated.

## Solution

The state of a worktree becomes two things shown apart, an activity and an integration, and the integration is read from git first and from the pull request second, with the pull request refreshed when the page asks.

**Activity** is Session open or Uncommitted changes, shown only when it applies (Session open first when both do), and it still blocks Remove and Clean up as today.

**Integration** is exactly one chip, the first that applies: Merged · #N (the session's pull request is merged), In main (the worktree's HEAD is an ancestor of the remote default branch), Not pushed (commits no other branch holds), PR open · #N (open or draft), PR closed · #N, and Pushed (its commits are held by another branch, in practice the remote's, with no pull request).
The number is a link to the pull request.
In main is a git fact and says nothing about why: the work was merged without a squash, or the worktree never had commits of its own (a new session, or one cut from the tip of main).
That is why it is its own word and not Merged, which stays for a pull request GitHub says is merged; a squash merge is never an ancestor, so for it the pull request is the only signal.
The remote default branch is what `refs/remotes/origin/HEAD` points at; with no `origin/HEAD` the host does not guess `main` and In main is never offered.
A stale local `origin/main` can only under-report In main, never over-report it, and the page does not fetch.
A detached HEAD has no branch to hold its commits, so its commits that no branch holds count as Not pushed, which keeps Pushed from reassuring about work that is held nowhere.

**The pull request is refreshed when the page asks** (`projectWorktrees` and `cleanProjectWorktrees`, with or without `run`): for the sessions of the project's worktrees that have a pull request saved as open or draft, archived ones included, in one request as the sweep's `refreshStates` already does, before the state is computed; if GitHub cannot answer, the failure is logged and the saved state is used.
`removeProjectWorktree` does not refresh, it only needs the block.

**Clean up** takes every worktree that has a session, whose integration is Merged or In main, and that has no activity; one with uncommitted changes or an open session is skipped with its reason, as today.
A worktree with no session is still never in Clean up, though it can be removed by hand: with no session nothing brings its folder back.
Only the folder goes, and the branch and session stay (ADR 0035), so a session made a moment ago and idle that shows In main loses its folder and gets it back with its next message.
The row is reworded because Clean up as both the title and the button repeats itself: the title is "Finished worktrees", the detail says "Merged or already in main, nothing blocks them: 3 worktrees, 2.91 GB", and the button stays Clean up with its question and its report as they are.

**Remove** is a trash icon button with no text: its meaning is the icon, the tooltip ("Remove this worktree's folder", or its reason while it is disabled) and the accessibility label stay.

What lost.
Calling every ancestor of main Merged, because a worktree that never had work would read as merged.
Showing Merged only when the saved state says so and fixing only the refresh: it leaves squash merges and the never-had-work case saying Clean.
Sweeping every archived session's pull request from the host on its own clock: it changes the GitHub cost of the whole host and also covers the automatic cleanup of `afterPrMerged`, so it is left as its own issue.
Keeping Clean up to pull-request-merged worktrees only: firebat and the archived #1495 are exactly the ones a person expects it to take.
Making Pushed mean "a remote holds it": it needs a second count of commits per worktree, and the repo already reads Not pushed as "no other branch holds" (`previewWorktree`), so Pushed is its complement.

## Scope

1. Each worktree of `projectWorktrees` says its activity, its integration and its pull request (number and link), and the single `state` is gone.
2. A worktree whose HEAD is already in the remote default branch says In main, with or without a pull request or commits of its own; with no `origin/HEAD` it never says it.
3. A worktree whose session's pull request GitHub says is merged says Merged · #N when the page opens, even when the session is archived and its saved state was open; when GitHub cannot be reached the saved state shows and a line is logged.
4. A detached HEAD with commits no branch holds says Not pushed, and one whose HEAD is held by a branch does not.
5. Clean up lists and removes the worktrees with a session whose integration is Merged or In main and that have no activity, skips with the reason those with uncommitted changes or an open session, and never takes one with no session.
6. A row shows the activity chip when there is one, then the integration chip with its pull request number as a link, in the words of the person's language.
7. Remove is an icon-only trash button, still disabled with its reason while the session is open and still named for a screen reader.
8. The row that Clean up sits in says Finished worktrees and what it takes, and appears when the host says any worktree can be taken.
9. Deleting a project from disk still lists a worktree's uncommitted changes and unpushed commits as unsaved work and still refuses while a session is open.
10. The projects documentation and the glossary say the two chips and what each word means.

## Decisions

**The reply.** `projectWorktrees` answers each worktree with these fields in place of `state`, and `main` keeps its own `state`, because the Trash check reads it.
A new capability `worktreeIntegration` is listed and gated as `projects` is, so a host without it makes the group say what a host that predates `projects` says (`projectsNeedNewerHost`) and the app never draws a wrong chip.

```ts
type ProjectWorktree = {
  path: string; branch: string | null; session: { id: string; title: string | null } | null; lastActiveAt: number;
  activity: 'sessionOpen' | 'uncommitted' | null;
  integration: 'merged' | 'inMain' | 'notPushed' | 'prOpen' | 'prClosed' | 'pushed';
  pullRequest: { number: number; url: string } | null; // the session's saved one; null with no session or none linked
};
const activity = family?.live ? 'sessionOpen' : dirty > 0 ? 'uncommitted' : null;
const integration = pr === 'merged' ? 'merged' : inMain ? 'inMain' : unpushed > 0 ? 'notPushed' : pr === 'open' || pr === 'draft' ? 'prOpen' : pr === 'closed' ? 'prClosed' : 'pushed';
```

Run against the worktrees the page meets: with no session `pr` is undefined and the chain falls to In main, Not pushed or Pushed; with no `origin/HEAD` `inMain` is false; a detached HEAD gets `unpushed` from `rev-list HEAD --not --branches --remotes` in `readProjectWorktrees` and not from `previewWorktree`, which the deletion flows share and which stays as it is.
The reply for one worktree carries `pullRequest` whatever the integration, so Merged, PR open and PR closed can link, while In main, Not pushed and Pushed link too when the session has one.

**Refresh.** `createSessionData` exposes one call that runs `refreshStates` for the given rows regardless of `STATE_TTL_MS`, and `readProjectWorktrees` takes a flag, set by `projectWorktrees` and `cleanProjectWorktrees`, to call it for the sessions of the listed worktrees and then read their rows again before computing the states.
The page asks both requests when it opens, so a project with a worktree to clean makes two small refreshes; the preview and the run can also disagree if a pull request merges between them, and the report says what went, as today.

**The app.** `ProjectWorktree` decodes the new fields; `WorktreeRow` carries `activity`, `integration` and the pull request, and `worktreeRows` says them in words (`projectsWorktreeState*` copy keys in `design/copy/en.json` and `es.json`, with In main, PR open, PR closed, Pushed new, and Clean removed); `ProjectDeletion` reads `activity == uncommitted` and `integration == notPushed` where it read the old states, and `activity == sessionOpen` where it read the old session-open state.
`loadWorktrees` asks the Clean up preview when any worktree with a session is Merged or In main.
The pull request number opens its page as the pull request chip of a session does.
The layout is decided when the view is built against fixtures (`macos-ui-change`): every chip and the link must show at the narrowest width with nothing cut, and the activity chip may move to the row's second line.

**Testing seams.**
Stories 1 to 5 go through `createSessions` in `src/chat/git.integration.test.ts` with real git, the seam that already pins `projectWorktrees` and `cleanProjectWorktrees`: the existing listing test changes its `state` expectations to activity and integration and gains a worktree in main (with `origin/HEAD` set by `symbolic-ref` and `update-ref`), a squash-merged one by pull request, a detached one with a commit no branch holds, and one archived session whose saved `open` becomes Merged when a `FakePulls` answers it merged; the clean-up test gains an In main worktree and keeps the orphan out; a repo with no `origin/HEAD` never says In main.
The unreachable-GitHub case of story 3 goes through the same seam with a `FakePulls` that throws, asserting the saved state and the logged line.
Stories 6 and 8 go through the pure `worktreeRows`, `cleanUpWords` and their Spanish renderings in `ProjectWorktreesTests.swift` and `ProjectsSpanishTests`, and the reply's shape through `ChatHostTests` against `macos/Tests/Fixtures/chat-project-worktrees.json` and `capabilities.json`, the fixtures both sides already read.
Story 9 goes through the deletion check's tests in `ProjectDeletion`'s test file.
Story 7 and the layout have no unit test: they are a view, checked in the running app against the fixture in every state (`macos-ui-change`).
Story 10 has no test: `SettingsIndexDriftTests` and the copy keys are the nearest check.

## Out of scope

Sweeping archived sessions' pull requests on the host's clock, and with it the automatic cleanup of `afterPrMerged` reading a frozen state (to file as an issue).
Fetching the remote when the page opens.
Changing what Remove does, what a worktree row says about its session and age, or the disk bar and sizes.
The main clone's state, which stays uncommitted, not pushed or clean because the Trash check reads it.
