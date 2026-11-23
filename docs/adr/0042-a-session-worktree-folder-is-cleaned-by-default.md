# 0042 - A session's worktree folder is cleaned by default

- Status: accepted; amends [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) (the defaults of `worktreeCleanup`)
- Date: 2026-11-22

## Context

[0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) made the cleanup of a session's worktree folder opt-in, both rules off.
Nobody turns it on, so the folders pile up under `<folder>/chat/worktrees`.
One measured Carrier folder held 3.3 GB in a single worktree, 3.26 GB of it `macos/.build`, the build output git ignores.
Its session was archived and its pull request still open, idle for 0.2 days.
Twenty-one other sessions with a worktree had no folder left on that machine, so what filled the disk was one open-PR session, not the merged ones.
`afterPrMerged` alone would not have freed it: the rule that covers a session with an open pull request is `afterInactiveDays`.

## Decision

`worktreeCleanup` is on by default: `afterPrMerged: true` and `afterInactiveDays: 14`.
The rules, the checks and what goes are those of 0035: only the folder, never a session that is working, waiting or open, never a worktree with uncommitted changes.
The check is `git status --porcelain`, which does not list ignored files, so the whole folder goes with every file git ignores: build output and dependencies, and also a local `.env` or config kept inside the worktree.
Untracked files that are not ignored count as uncommitted work and keep the folder.
The folder is kept too when its HEAD is detached (also mid-rebase) or on another branch than the session's, because a commit made there is held by no branch the cleanup keeps.
The session, its recorded path, its branch (with any commit not pushed) and its pull request stay, and the next message brings the folder back on its branch.
14 days count from the last activity, like `archiveAfterDays`, and need the session archived.
A session the clock archives after 15 days is therefore cleaned in the pass that archives it.
One archived by hand is cleaned once it has been untouched for 14 days, whatever its pull request says.
A person who wants the old behaviour sets `"afterPrMerged": false` and `"afterInactiveDays": "never"` in `chat.json`.

## Alternatives considered

Cleaning only build output inside the worktree.
It keeps the folder and the dependencies, but needs each repository to say what its builds are; that belongs to how projects are set up, left for later.

A size cap per worktree, or a total for the folder.
It needs a rule for which one goes first, and a worktree in use would be a candidate.

Cleaning when a session is archived.
An archive is often temporary, and the person may resume it the next day; 14 days of silence says the work is parked.

`afterPrMerged` alone.
It leaves the case measured above, a session with an open pull request that nobody touches.

## Consequences

The disk of a parked or merged session is freed within one hourly pass of the chat host, once it is archived.
A cleaned session opens again after a `git worktree add` and without its dependencies or builds, so the first build or install pays again.
A gitignored file that exists only in that folder (a local `.env`, a config) is lost with it and does not come back; the project's actions can recreate one, but Carrier does not copy ignored files itself.
No allowlist of files to spare was built: it would need each repository to say which ignored files matter, which belongs to how projects are set up.
The person who keeps such files in a worktree turns the cleanup off.
A session archived by hand and untouched for 14 days loses its folder though its pull request is open; its branch and commits stay in the clone.
