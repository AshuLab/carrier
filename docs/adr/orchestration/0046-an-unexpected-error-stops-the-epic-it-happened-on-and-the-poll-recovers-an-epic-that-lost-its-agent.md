# 0046 - An unexpected error stops the epic it happened on, and the poll recovers an epic that lost its agent

- Status: accepted
- Date: 2026-11-22

## Context

A review of the engine found that an epic can sit in `running` with no agent alive and nothing scheduled to move it, and that one unexpected error can stop the whole engine or freeze every epic's poll.

The work of a stage ends in a handler that settles the result, retries, fails over or parks the epic.
An exception inside it is logged and then rethrown by `track`, nothing outside the chat host handles an unhandled rejection, and the engine is started detached with nothing to start it again.
`settlePending`, `retryPending` and the recovery at start catch only a refusal by GitHub, so any other exception aborts the poll before it reserves or launches anything for any epic.
A stage that ended on a usage limit, or on a failure that fails over, is stored without an error, so the retry never sees it and only the recovery at start moves it.
If handling that ending throws, the epic stays in `running` with its last execution failed, the recovery at the next start throws the same way, and the engine cannot start.
`carrier restart` refuses such an epic because it is not in needs-human.

## Decision

An unexpected error in the path of one epic (the stage's work, settling its result, a retry, a failover, its recovery) is caught where it happens, logged with the epic's context, and parks that epic in needs-human with a new kind, `engine_error`, whose reason is the error as one redacted line.
The epic can be resumed like any other stopped epic, and the others go on untouched.
An error about the whole engine, such as SQLite or the config, still stops the engine, with a clear message.

The poll recovers a `running` epic that has no live execution and nothing scheduled, with the same per-epic recovery the start runs and the same guards as a launch (the runs the engine holds, a launch in flight, a retry in flight, the epic's epoch).
It does it at most three times in a row for one epic, and the next failure parks the epic in `engine_error`.
Each recovery leaves an event in the epic's history.
`carrier recover` ([0044](0044-recover-continues-an-epic-from-its-real-state-and-no-command-sets-one.md)) is the same recovery asked for by a person, at once.

## Alternatives considered

Letting the engine crash and relying on a supervisor lost, because nothing restarts a detached engine and the crash comes back at every start when the recovery throws the same error.
A global handler for uncaught exceptions that carries on lost, because it leaves SQLite and the running agents in a state nobody checked.
Only the manual `carrier recover` lost, because an epic would sit stuck until someone noticed.
Retrying the failing work without a limit lost, because a deterministic error would loop and spend agent runs.

## Consequences

A bug of the engine shows as a stopped epic with its error in the reason, and not as a crash, so the reason has to be visible in the app and the log has to carry the stack.
The automatic recovery runs on a live engine, which the start-time recovery was not written for: a launch in flight looks like a cut one, so every guard needs its own test.
`engine_error` is a new kind of stop, with its reason label and its line in the app's resume card like the others.
An epic that keeps failing the same way ends in needs-human after three recoveries, instead of looping.
