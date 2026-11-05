# 0019 - Sessions age by the clock, and an automatic delete never removes unsaved work

- Status: accepted
- Date: 2026-11-04

## Context

A user session can be archived and deleted by the person ([0014](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)), and a deleted session takes its worktree with it. Nothing ages: sessions, worktrees and branches pile up until someone clears them. The owner wants sessions nearly disposable, with a clear life: created by the first message, worked on, then archived or deleted, by the person or by time.

Deleting by hand shows what would be lost (uncommitted changes, and commits that exist nowhere else) and asks first. An automatic delete has nobody to ask.

## Decision

Two ages, counted from the session's last activity (the last message or event, and also restoring it from the archive): a session idle for 15 days is archived, and an archived one idle for 30 days is deleted. Both are numbers of days in the chat's own config, `chat.json`, `archiveAfterDays` and `deleteAfterDays`, each a whole number or `"never"`; with the first at `"never"` nothing is deleted by the clock, and the second has to be greater than the first.

The chat host applies them when it starts and again every hour while it runs, in one pass, by the clock: a host that was not running for 40 days archives and deletes what is due when it next starts. There is no background service. A session that is working or waiting for an approval is skipped, as archive and delete already refuse it.

The automatic delete never removes a session whose worktree has uncommitted changes or commits that exist nowhere else. That session stays archived, marked as kept because of unsaved work, and the person deletes it by hand with the usual confirmation. Archiving loses nothing, so it has no such guard.

## Alternatives considered

Delete anyway, for sessions to be truly disposable. It is the simplest and the most surprising: a person comes back to a branch they never pushed and finds it gone with no warning.

Count from creation. A session someone keeps coming back to would be archived and deleted underneath them.

Count the 30 days from the archive date. It gives a fixed grace period after archiving, but a session archived by hand on day 3 would live 33 days and the rule would need two clocks per session.

A launchd service so the clock runs with the app closed. [0010](0010-carrier-runs-in-the-background-as-a-detached-process.md) already rejected a service for the engine; the host applying the clock at its start gives the same result for a person who opens the app, which is the only way sessions are seen.

## Consequences

A person who leaves a session for a month and returns finds it in the archive, and for 15 more days can still open it. After that, it is gone, with its worktree and branch, unless it held work that was never pushed, in which case it is still there and says why.

Restoring a session from the archive counts as activity, or it would be archived again on the next pass.

The settings are in `chat.json` and are edited from a Sessions section of the app's Settings; a wrong value stops the host with the key named, like the rest of that file.

Disk and branches stop growing without limit, at the price that a deleted session cannot be recovered; the clones in the projects folder are not part of it and stay.
