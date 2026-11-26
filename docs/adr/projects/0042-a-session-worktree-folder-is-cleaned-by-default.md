# 0042 - A session's worktree folder is cleaned by default

- Status: accepted; amends [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) (the defaults of `worktreeCleanup`) and [0006](../orchestration/0006-agent-events-stored-in-sqlite-with-bounded-output.md) (the raw log is capped)
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
The folder is kept too when its HEAD is detached (a rebase or a bisect in progress detaches it), because a commit made there is held by no branch.
A HEAD on another branch than the session's does not keep it: branches live in the clone every worktree shares, so that branch and what was committed on it survive the removal of the folder.
The recorded branch is the one the session comes back on, and the folder is cleaned whichever branch it was on.
It is kept as well when git cannot show everything it holds: a submodule (its repository lives in the worktree's own git dir, which goes with the folder), a file marked `--assume-unchanged` or `--skip-worktree` that is there (edited with no line in `status`), and a commit made on a detached HEAD and then left by switching back to the branch, which only the worktree's reflog holds.
`status` is asked for untracked files whatever `status.showUntrackedFiles` says.
A commit of the branch itself that was amended or rebased away does not keep it: its new version is the branch's.
The cleanup gives git three minutes to remove a folder, so a big one is not stopped halfway.
A folder git cannot read (no `.git`, or one that is a link to nothing) is not a worktree to Carrier: the pass logs a warning, deletes nothing and tries again on the next pass.
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
The person who keeps such files in a worktree turns the cleanup off, or has the project's `newWorktree` actions copy them back: those run again on every restore, so `cp "$CARRIER_PROJECT/.env" .` brings a file back.
An action with no `onFail` only warns when it fails, and the session goes on without the file; with `"onFail": "stop"` the open is refused, the folder stays and the next open goes on from the failed action.
The raw output log of an agent run is capped at 50 MiB per stream, which amends [0006](../orchestration/0006-agent-events-stored-in-sqlite-with-bounded-output.md): `stdout.log` was there the complete output and the replay source, and now holds the newest part (with `stdout.log.1`), so `pnpm replay:events` sees only that tail; the events in SQLite stay the record of the run.
A session archived by hand and untouched for 14 days loses its folder though its pull request is open; its branch and commits stay in the clone.

Known limits.
A removal killed halfway (power loss, `SIGKILL`) can leave a half-removed folder.
Git deletes in the order the folder lists its entries, so `.git` can survive or not; Carrier does not finish such a folder, as it has no way to tell leftovers from work someone put there.
The remedy is by hand: `git -C <clone> worktree prune`, then remove the folder (see [troubleshooting](../../troubleshooting.md#a-sessions-worktree-folder-is-gone)).
A worktree with an initialised submodule keeps its folder forever, even with no edits, since its repository lives in the worktree's git dir; one whose submodule was never initialised is cleaned.
The removal can take up to three minutes, during which resuming that session waits and a stop of the chat host can wait for it.
With `core.logAllRefUpdates=false` the HEAD reflog is empty and the check for a dangling commit sees nothing.
A marked file that is there keeps the folder even when it is unchanged, since telling would mean hashing each one.
A commit made detached and later cherry-picked onto the branch keeps the folder, as only the reflog and not the patch is compared, and the reflog is read only for `commit`, `cherry-pick` and `revert` entries (a commit made by a rebase that was then aborted is not looked for).
Reflogs expire (90 days by default for reachable entries, 30 for unreachable ones), and a worktree kept for that long has lost the trace of a dangling commit, so the check is a guard and not a guarantee.
Deleting a session by hand and removing a worktree by hand from a project's page are as they were: they do not look for hidden work and give git its default time.
The same guards there are a separate decision.
