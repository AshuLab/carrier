# 0049 - A quota stop wakes up by itself when the provider says the window is back

- Status: accepted
- Date: 2026-11-23

## Context

When an agent runs out of quota and the epic has no failover left, it stops in needs-human with the kind `usage_limit` and stays there until a person resumes it, even when the window comes back in a few minutes.
A 5-hour window is the common case, so an epic can sit idle for hours that nobody had to spend.
The engine already has quota probes for Claude, Codex and `agy` (`carrier usage`), and each window carries the exact time it resets; the text of the error does not, since Codex gives a local-time string, `agy` none and Claude none.
Resuming spends credits with nobody watching, and a window that resets later than expected would spend the epic's retries and stop it again.

## Decision

An epic that stops in `usage_limit` keeps that status and, when the probe gives the time the exhausted windows come back, also keeps `resumeAt`.
The poll that already runs resumes the epic after that time, but only after asking the probe again without its cache and finding the window below 100%; otherwise it waits for the next poll.
The resume is the resume from a stage, so the epic goes on from where it stopped, with its round, pull request, worktree and session, on the option that came back, through the queue.
It is off until `limits.autoResume` is set, it does not resume when the wait is longer than `limits.autoResumeMaxHours` (12 by default), it guesses no time when the probe gives none, and it resumes at most three times in a row.
A person's own resume, or any change of status, clears the wait.

## Alternatives considered

A fixed timer or the time in the error text lost, because only the probe gives an exact time for every provider.
Resuming without checking the probe lost, because a reset that moved would burn the retries and stop the epic again.
A new status for the waiting epic lost, because it keeps no slot, the reason label exists and the app needs one line more.
On by default lost, because it spends credits unattended.
Waiting for the weekly window lost as a default, because it would hold an epic for days and the person may prefer to decide.

## Consequences

The engine depends on the quota probes, which have their own rate limits and can fail, so the wake-up is a best effort and the epic stays stopped when the probe cannot answer.
The epic carries `resumeAt` and a count, and two new events, and the panel and the CLI show the time.
It cannot ship before the resume from a stage and the attempt rule, or the epic would restart from ship with its rounds reset.
Credits are spent on a schedule the person does not watch, which is why it is off by default.
