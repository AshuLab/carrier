# The engine never leaves an epic stuck

Status: spec

## Problem

An epic got stuck after a quota error, in a state that no supported action could move.
The way out was to run an external agent that edited SQLite by hand so that Carrier would take the epic again.
Nobody knows the exact state it was in, and that is part of the problem: when an epic stops advancing, the person has no safe first move and no way to see why.

A review of the engine ([the findings](../research/engine-review-2026-11.md), level 1) found that this was not one bug.
An epic can sit in `running` with no agent alive and nothing scheduled to move it, and the only things that move it run when the engine starts.
One unexpected error can stop the engine, or freeze the poll of every epic, and the engine cannot start again while an epic keeps throwing the same error in its recovery.
A resumed epic carries the failures of its previous attempt and can stop again with no retries.
Nothing detects a process that hangs, and a process that ended can still be waited on.

Two smaller things hurt around it.
Resume restarts an epic from ship with the review rounds reset, so an epic that stopped on the review limit loses its round count and pays an agent run of `ship` that has nothing left to do.
When an agent's quota runs out and no failover is left, the epic stays stopped until a person resumes it, even when the provider says the window comes back in minutes.

It hurts whoever runs Carrier on real epics, today Diego, and we know because it happened and the recovery was manual.
This is the first of four epics that come out of that review, and the other three start from `main` once this one is merged: [the rest, in order](carrier-engine-improvements.md).

## Solution

One epic in three parts, in this order, because the attempt rule of the first is under the others and the wake-up needs the resume from a stage.

### Never stuck

The decisions are [ADR 0046](../adr/0046-an-unexpected-error-stops-the-epic-it-happened-on-and-the-poll-recovers-an-epic-that-lost-its-agent.md) and these.
An unexpected error in an epic's path parks that epic in needs-human with the new kind `engine_error`, whose reason is the error as one redacted line, and never stops the engine or the other epics; an error about the whole engine still stops it, loudly.
The poll recovers a `running` epic that has no live execution and nothing scheduled, with the same guards as a launch, at most three times in a row, and each recovery is an event; the count starts again when the epic's next execution finishes or its stage changes, and the next failure parks the epic in `engine_error`.
An epic whose issue answers 404 or 410 while its repo answers normally is cancelled with the reason that the issue no longer exists, so the engine starts and its repo's queue is not blocked; when the repo does not answer normally (GitHub also answers 404 for a repo the token lost access to) it is a refusal of the repo, shown with its reason and tried again at the next check, and no epic of it is cancelled.
Resume starts a new attempt: only the executions since the epic's current start count for recovery and for the retry budget, and the retries are back to the maximum.
A process is never waited on past its exit, and its whole process group is killed after the grace and once more after the exit; an idle watchdog, `limits.idleMinutes`, is off by default and, when set, kills a silent process and treats it as a technical failure that retries with the session.
Smaller, with no decision needed: the recovery gets a branch for `timed_out` and checks the stage on `interrupted`, each item of `settlePending` and `retryPending` isolates its own error, and every guard of the recovery on a live engine has a test.

### Recover and resume from a stage

`recover` is a per-epic request that makes the engine continue one running epic whose agent is not alive, from its real state, as it does at start.
It refuses when an execution of that epic is really alive or the epic is not running, and no request sets a status, stage or round the caller picked ([ADR 0044](../adr/0044-recover-continues-an-epic-from-its-real-state-and-no-command-sets-one.md)).
Resuming an epic in needs-human at `review` or `fix` keeps its round, pull request, worktree and blockers, where today it always restarts from ship and resets the rounds; resuming at `ship` stays as it is.
When the epic stopped on the review limit, resuming gives it more rounds counted from the current one, by default as many as `maxReviews`, and a flag adjusts that number, so the app's promise of new rounds stays true.
It needs the pull request to be open and its head to be the one stored, and refuses otherwise.
A resume still goes through the queue, as it does today: the epic remembers the stage it resumes at and the rounds granted (new fields of the epic), takes a slot like any other epic, and the command answers when it has started or refuses at the thirty seconds it already has.
The cap of review rounds is kept per epic, because today it is read only from the live settings and a resume that grants rounds needs a number of its own.
The poll reads the `ready` label of a stopped epic before the reconciliation takes it off, so the label a resume puts is not removed before it is seen.
Each manual transition leaves an epic event, like `option_switched` does.
The CLI (`carrier recover <repo>#<issue>`, `carrier restart --from`) and, later, the app use the same requests over the control socket.

### Wake up when the quota comes back

The decision is [ADR 0049](../adr/0049-a-quota-stop-wakes-up-by-itself-when-the-provider-says-the-window-is-back.md).
It is off until the person turns it on with `limits.autoResume`, because it spends credits with nobody watching.
An epic that stops in needs-human with the kind `usage_limit` keeps that status, and when the provider tells when the exhausted window comes back it also keeps `resumeAt`, that time, shown in the panel and in the CLI as when it resumes.
The time comes from the quota probes `carrier usage` already uses, for the account of the option that ran out: the latest `resetsAt` of the windows that are at 100%, and, when the epic had failover options, the earliest of those over the options it tried.
For `agy` the windows are those of the group of the option's model.
The poll that already runs finds the epics whose `resumeAt` has passed, asks the probe again without its cache, and resumes the epic only if the window is below 100%; if it is not, the epic waits for the next poll.
The resume is the resume from a stage (the part above): the stage where it stopped, with its round, pull request, worktree and session, on the option that came back, through the queue, taking a slot like any epic.
It does nothing when the wait is longer than `limits.autoResumeMaxHours` (12 by default, so a 5-hour window is covered and a weekly one is not): the epic stays stopped and says when the window comes back.
It guesses nothing: with no reset time (the account has no Codex access, a credit balance that does not reset, a probe that fails or is rate limited, a provider with no probe) the epic stays stopped as today and says why.
It resumes an epic at most three times in a row; the count starts again when the epic's stage changes or one of its executions ends with anything but `usage_limit`, and the next stop stays in needs-human.
Each schedule and each wake-up is an event.
A person who resumes the epic, or any change of its status, clears `resumeAt`; with the engine paused nothing resumes; and `resumeAt` is saved, so an engine that restarts keeps it.

### What was cut, and why

A command that sets any state lost, because it would let a person leave SQLite in combinations the engine never produces, which is what the manual edit did, now with a button; if `recover` cannot move a real case, that case tells us which verb is missing.
Restarting the engine as the answer lost, because it interrupts every other epic's agents.
Letting the engine crash and rely on a supervisor lost, because nothing restarts a detached engine.
A timer from the text of the error lost, because Codex gives its time as a local-time string, Claude and `agy` give none, and the probe gives it exactly.
Resuming without looking at the probe again lost, because a reset that moved would spend the retries of the epic and stop it again.
A new status for the epic that waits lost, because it keeps no slot, the reason label already exists and the app needs one line more.
On by default lost, because it spends credits unattended and the person should choose it.

## Scope

1. As the person running Carrier, when an unexpected error happens on one epic's path, only that epic stops, in needs-human with the kind `engine_error` and the error in one redacted line, and the other epics keep going.
2. As the person, an exception in a stage's handler (settling a result, a retry, a failover) does not end the engine and does not leave an execution `running` or an epic with nothing to move it.
3. As the person, an error on one finished execution or one retry does not stop the poll for the other epics and repos.
4. As the person, an error about the whole engine, like SQLite or the config, still stops it with a clear message.
5. As the person, a running epic with no live execution and nothing scheduled is recovered by the next poll, at most three times in a row, each time as an event in its history, and then it stops in `engine_error`.
6. As the person, a recovery never starts a second agent on an epic: it respects the runs the engine holds, a launch in flight, a retry in flight and the epic's epoch.
7. As the person, the engine starts when an epic's issue answers 404 or 410 while its repo answers normally; that epic is cancelled with the reason that the issue no longer exists, and the other epics of its repo go on.
8. As the person, a repo that does not answer normally, a 404 for the whole repo included, is shown as that repo's refusal with its reason and tried again at the next check, no epic of it is cancelled, and the epics of other repos are not touched.
9. As the person, a resumed epic starts a new attempt: only the executions since its current start count for its recovery and its retry budget, and its retries are back to the maximum.
10. As the person, after a Resume, an old execution can no longer leave the epic with a claimed stage and no one to launch it, and an epic that timed out and was parked is moved by the recovery.
11. As the person, a process is never waited on past its exit, and its whole process group is killed after the grace period and once more after the exit.
12. As the person, with `limits.idleMinutes` set, a process that writes nothing for that long is killed and retried with its session as a technical failure, and without it nothing changes.
13. As the person, `carrier recover <repo>#<issue>` continues a running epic with no live agent from its real state, and it refuses with a reason when the epic is not running or an execution of it is really alive.
14. As the person, no request sets an epic's status, stage or round to a value I pick.
15. As the person, `carrier restart <repo>#<issue> --from review` or `--from fix` resumes an epic in needs-human keeping its round, pull request, worktree and blockers, and it refuses when the pull request is not open or its head is not the stored one.
16. As the person, resuming an epic that stopped on the review limit gives it more rounds counted from the current one, by default as many as `maxReviews`, and `--extra-rounds K` changes the number.
17. As the person, `--from ship`, or no `--from`, behaves as a resume does today, with the rounds reset.
18. As the person, each manual transition leaves an event in the epic's history saying what asked for it.
19. As the person, an older engine that does not list the new requests among its capabilities is not asked for them.
20. As the person, with `limits.autoResume` on, an epic that stops in `usage_limit` with a known reset keeps `resumeAt` (the latest reset of its exhausted windows, the earliest over the options it tried when it had failover) and the panel and the CLI show when it resumes.
21. As the person, at the first poll after `resumeAt` the engine asks the probe again without its cache and resumes the epic only when the window is below 100%, and otherwise waits for the next poll.
22. As the person, the wake-up resumes the epic from the stage where it stopped, with its round, pull request, worktree and session, on the option that came back, through the queue and taking a slot like any epic.
23. As the person, when the wait is longer than `limits.autoResumeMaxHours` (12 by default) the epic does not resume by itself and says when its window comes back.
24. As the person, when no reset time is known (no window, a credit balance, a failing or rate limited probe, no probe) the epic stays stopped as today and says why, and nothing is guessed.
25. As the person, an epic resumes by itself at most three times in a row, then stays in needs-human, and each schedule and wake-up is an event of the epic.
26. As the person, resuming the epic myself or any change of its status clears `resumeAt`, an engine in pause resumes nothing, and `resumeAt` survives a restart of the engine.
27. As the person, with `limits.autoResume` off, which is the default, a usage stop stays stopped until I resume it.

## Decisions

The shape of the config, as an example of the keys and not of values:

```json
{
  "limits": { "idleMinutes": 45, "autoResume": true, "autoResumeMaxHours": 12 }
}
```

`limits.idleMinutes` has no default: it is off until set.
`limits.autoResume` is false by default and `limits.autoResumeMaxHours` is 12.

The data. The kind of stop `engine_error` joins `needsHumanKinds`.
The epic carries the stage a resume asked for, the review rounds it granted and, with them, the cap of rounds the epic has (kept per epic, no longer read only from the live settings), and `resumeAt` and the count of automatic resumes in a row.
The epics' events gain `auto_resume_scheduled`, `auto_resumed`, `recovered` and one per manual transition, like `option_switched` is.
The attempt is not a new column: it is `executions.startedAt` at or after `epics.startedAt`, which the reserve sets and a restart clears.
The retry streak and the recovery read executions within that attempt.
A migration comes with `pnpm db:generate`, and an epic saved before this version is read with the defaults.

The control socket and the CLI. `recoverEpic` is a new request and capability, and `resumeEpic` takes an optional `from` (`ship`, `review`, `fix`) and `extraRounds`, announced as the capability `resumeFromStage`, so an engine that lacks it is not asked and the app only sends them when the hello lists it.
`carrier recover` and `carrier restart --from` use them, and the replies the app reads gain the new fields as optional, per the checklist of `src/control/AGENTS.md`.
Every change to a reply or a config field follows the checklists of `src/control/AGENTS.md` and `src/config/AGENTS.md`, including the fixtures under `macos/Tests/Fixtures`.

The engine reads the quota through a port with a fake, which answers with the probe's `QuotaSnapshot` (windows with `resetsAt`, and a fresh read that can fail or be rate limited), as the other ports do.

Documentation is part of the epic: `docs/configuration.md` (the `limits`), `docs/cli.md` (`recover`, `restart --from`), `docs/troubleshooting.md` (a stuck epic, `engine_error`, the wake-up), the CHANGELOG and the glossary, and `docs/specs/resume-a-stopped-epic.md` is amended where the rounds no longer always restart.

Testing seams, per story, preferring the seams the repo has:

- Stories 1 to 10 and 20 to 27: the engine through its public interface in `src/orchestration/engine.test.ts`, with the fake `GitHub`, the fake `AgentRunner` that writes, fails, hangs or is cut, the fake quota port, an injected clock and a real temporary SQLite; a restart of the engine on the same database covers recovery. The rule that takes the exhausted windows and the options tried to a `resumeAt` is a pure function with its own unit test.
- Stories 11 and 12: the process hygiene in `src/harnesses/host-runner.integration.test.ts`, gated as the others are, and the idle rule as a pure function of the clock and the time of the last output, in its own unit test.
- Stories 13 to 19: the request and its refusals in `src/control/server.test.ts`, the capabilities in `src/control/capabilities-contract.test.ts`, the replies as goldens in `src/control/replies.test.ts`, the commands in `src/terminal/cli/commands/restart.test.ts` and a new one for `recover`, and the engine side in `engine.test.ts`.
- The macOS side of the contract fixtures and the app's own views are out of this epic.

## Out of scope

The other three epics, in this order: a review to trust and the intake in order; the labels' new defaults and the skills the person names; and several reviewers with a lead.
They are in [the backlog](carrier-engine-improvements.md) and each is specced again from `main` when its turn comes.

Pausing one epic while the others run (`hold`), the label orders `carrier:restart*` and a `carrier enqueue` command, until someone needs to act from GitHub.

The macOS app (the recover action, the resume-from-stage choice, the wake-up line) and a CLI setter.

Waking up by itself for any kind of stop other than `usage_limit`.

Skipping the observations pass on resume, any command that sets a state, and the findings of the engine review that are only suspected: child processes that outlive their agent, a clone whose base is stale, and the environment a child inherits, until there is evidence.

The review of how Carrier treats text written by third parties that the agents read, and of updating the engine while epics are running.
