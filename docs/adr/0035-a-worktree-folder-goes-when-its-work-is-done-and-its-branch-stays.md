# 0035 - A worktree's folder goes when its work is done, and its branch stays

- Status: accepted; amends [0014](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md) (a session worktree); the per-repo setup it left for later is [0039](0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)
- Date: 2026-11-18

## Context

Most of the disk under the Carrier folder is worktrees, and most of a worktree is what git ignores: builds and dependencies, gigabytes each, against megabytes of git objects.
Nothing removed the engine's reviewer checkouts, so they piled up one per epic, and Solve's author worktrees stayed after the epic ended.
A session worktree went only with its session ([0014](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)), after `deleteAfterDays`.

## Decision

When an epic is merged or cancelled, the engine removes its reviewer checkout, the author's worktree of the epic's branch and Solve's `<that path>--lane-N` worktrees beside it, always, with no setting.
It then deletes the epic's local branches (the epic branch and, for `<prefix>/epic`, its slices under `<prefix>/`) whose tip is on the remote, and keeps and logs any that is not.
It keeps, and logs, an author or lane worktree that holds uncommitted files or commits on no branch, since a cancelled epic's work may be there only.
It only removes paths `git worktree list` reports for its clone, does it at the next poll (also for epics that ended earlier), records it on the epic, and retries a failure at the next poll without blocking anything.

A session worktree's folder can go before the session does, by the opt-in `worktreeCleanup` of `chat.json`: `afterPrMerged`, `afterInactiveDays`, both off by default.
Only the folder goes, with what git ignores; the session, its recorded path and its branch stay, and the next message brings the folder back on that branch.
It never touches a session that is working, waiting or open, nor a worktree with uncommitted changes.

## Alternatives considered

Removing the engine's branches too even when not pushed. The code of a merged epic is on GitHub, but a cancelled one may hold commits nowhere else; keeping those costs nothing.

A setting to keep the engine's worktrees. Nothing reads them after the epic ends, and a person who wants one can check out the branch.

Cleaning only build output inside a session worktree (a per-repo hook). It keeps the folder, but needs each repo to say what its builds are; that belongs to how projects are set up, left for later.

## Consequences

The disk of an ended epic is freed within one poll.
A cleaned session opens again only after git checks out its branch, and without its dependencies until something installs them.
