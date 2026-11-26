# Orchestration

**Carrier** - Application that discovers ready epics and coordinates implementation, review and fix agents until the final PR is ready for test or it reports that human intervention is needed. Agent Forge manages the identities and their authentication; Solve provides the skills. The name is inspired by the StarCraft ship that deploys multiple interceptors.

**Ready for test** - The final PR has a conclusive review with no blockers and repo checks confirmed by the agents on the same commit. In a repo without CI, the review and the test evidence reported by the skills are enough, and that absence is recorded. Diego still has to test it and decide the merge.
_Avoid_: approved for merge, delivered, epic finished.

**Execution retry** - A new execution after a technical failure of the process or infrastructure, once its effects have been checked. It is not a code fix or a new review. The agent timeout has its own human-intervention outcome and is not retried automatically.
_Avoid_: retry without specifying what failed.

**Test/CI fix** - Internal work by the author and its skills to resolve failed checks before reporting the state of its execution. The orchestrator does not count these attempts or add a loop to manage them.
_Avoid_: execution retry, orchestrator fix counter.

**Epic** - `solve:epic` issue with a spec and prepared tickets; the unit that Carrier queues, executes and delivers. It is identified by repo and issue, because different repos reuse numbers.
_Avoid_: feature, task, job.

**Stage** - Segment of an epic in charge of one role: implementation with `ship`, review or fix. The orchestrator combines the stage with the caller result to decide the next turn.
_Avoid_: step, phase, epic state.

**Execution** - One invocation of an agent (author or reviewer) with its session, time limit and result. It is the unit of the technical retry and of the timeout; it does not represent the duration of the epic.
_Avoid_: process (technical termination is something else), epic.

**Caller result** - Structured conclusion of an execution, in JSON: `completed`, `changes_requested` or `needs_human`. It is independent of whether the process ended well or badly.
_Avoid_: process success/failure, CLI state.

**Human intervention** - State of an epic that is stopped (`carrier:status:needs-human`) by `needs_human`, timeout, exhausted limit, inconclusive review or authentication error. Diego resolves it outside Carrier; Carrier takes it back only when he puts `solve:epic:ready` on the issue again.
_Avoid_: error, failure, pause.

**Control socket** - Local channel (a Unix socket, `engine/state/control.sock` in the Carrier folder) a running Carrier opens so another process can watch it and drive it: the snapshot and the agent's output come out, and pause, check now and stop go in. The macOS app is a client of it. See [0005](../adr/0005-engine-independent-of-the-macos-app.md).
_Avoid_: API, daemon, IPC.

**Slice progress** - How many of an epic's slices (its sub-issues) are closed out of the total, read from GitHub on every poll, when the agent runs a command that changes the slices, and once a minute for live epics. The list behind the count is kept in SQLite as a cache of GitHub, never as authority ([0008](../adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); the agent running `ship` works the slices inside its own session.
_Avoid_: ticket progress, issue status.

**Lane** - One of the up to three parallel worktrees inside a `ship` execution (`<epic worktree>--lane-N`). A lane is a place, not a worker: it is reused, so lane 1 builds one slice and then another, and the subagent that builds a slice runs in a lane. Solve decides the lanes; the engine does not know them, and a lane has no session of its own, so it cannot be resumed apart from the ship session.
_Avoid_: slot (that counts epics), thread, worker, subagent (a lane holds one at a time).

**Slot** - One of the places the engine has for running epics at once (`maxConcurrentEpics`). It is a counter with no identity, so the app shows how many are in use and which epics occupy them, never "slot 2".
_Avoid_: lane (that is inside one epic), thread, concurrency.

**Done** - The group of epics whose final PR was merged, shown for the finished window after the merge. Not Ready for test: nothing is waiting for a person any more. In the terminal panel it is a section of the same name.
_Avoid_: finished (the window and the snapshot field use it, the group does not), closed, completed.

**Cancelled** - The group of epics that ended without a merge (the final PR or the epic issue was closed), with the reason Carrier stored, shown for the finished window. Apart from Done so a fallen epic is never read as a delivered one.
_Avoid_: failed, aborted.

**Finished window** - How many days after an epic ends it stays listed under Done or Cancelled (`finishedWindowDays`, 15 by default, at most 30 because the retention purge deletes logs and sessions at 30). Counted from when the epic left `running`. After it the epic is only reachable by its issue and PR on GitHub; its row stays in SQLite.

**Detached run** - Carrier started with `carrier start`: its own session, no terminal, its output in a log under the engine's logs folder (`engine/logs/` in the Carrier folder), reached through its control socket (`carrier status`, `watch`, `stop`, or the macOS app). Nothing starts it but a person; it is not a login service and nothing restarts it if it dies.
_Avoid_: daemon, service (a launchd service is the alternative that was not chosen), background process.

**Resume (an epic)** - Putting an epic that stopped in needs-human back in the queue once a person has dealt with the cause.
It does what the person did by hand before: `solve:epic:ready` goes back on the issue, the `needs-human` mirror comes off, and the epic starts again from ship, reusing its worktree and its pull request, with the review rounds starting over (a resume that names a stage keeps them: see Resume from a stage).
Nothing checks that the cause is really fixed: if it is not, the epic stops again with the new error.
The macOS app asks the engine to do it, with a confirmation first; in a terminal it is `carrier restart`, which can also change the option of each role.
_Avoid_: retry (an execution retry is the automatic one after a technical failure), continue (continue in terminal is about a session).

**GitHub unavailable** - GitHub answered with a failure that clears by itself, so Carrier keeps its state and tries again on the next poll. It has a kind, which only diagnoses: `rate_limited` (HTTP 429, or 403 with a rate limit), `server_error` (5xx), `timeout` and `network`. The kind and its detail are in the error's message, so the log and the last check of a repo say why. An authentication error and any other HTTP failure are not GitHub unavailable.
_Avoid_: GitHub down, GitHub refused (that is the panel's section for the repos whose last check failed), the control socket's `github unavailable` reply (a different, fixed string).

**Failure kind** - Why an agent execution ended badly, one value from a closed list kept on the execution beside its status: `usage_limit`, `api_error`, `killed` (a signal from outside Carrier ended the process), `crashed` (a nonzero exit), `spawn_error`, `auth`, `session_lost`, `timeout`, `invalid_result` and `unknown`. It mostly diagnoses: only `usage_limit` changes anything, because it stops the epic at once in needs-human, naming the option that ran out, and spends no retry (like `timeout`, it does not count in the failure streak). It stays on the execution, so the history says why long after the epic's last error was cleared. An execution that ended `ok`, or that Carrier itself stopped, has none.
_Avoid_: error type, exit reason, technical failure kind (a technical failure is what an execution retry answers; the kind says which one it was), GitHub unavailable's kind (a different list, for GitHub calls).

**Reload** - The engine reading `engine.json` and `providers.json` again while it runs, when the app or `carrier reload` asks, and applying them if they are valid; if not, it keeps what it has and says why. What is running keeps what it started with (an agent run its agent and timeout, an epic the configuration it stored) and what starts later uses the new settings.
_Avoid_: restart (Carrier keeps running and nothing is interrupted), refresh, hot reload.

**Label role** - Each label Carrier reads or writes on an epic's issue has a role, and the config names the label of each role in `labels`: `epic` and `ready` are written by Solve and by people, `running`, `readyForTest` and `needsHuman` by Carrier.
No two roles, stages or reasons may share a label.
See [ADR 0043](../adr/0043-labels-are-named-by-who-writes-them-and-every-one-is-configurable.md).
_Avoid_: tag, state label (a status label is only the three Carrier writes).

**Status label** - The label Carrier puts on an epic's issue to mirror its status: `running`, `ready for test` or `needs human`, by default `carrier:status:*`.
Only Carrier writes it, and it takes off the ones that no longer apply.
_Avoid_: state label, epic label (that is the `epic` role, the marker Solve writes).

**Stage label** - An optional label, named in `labels.stages` for `ship`, `review` or `fix`, that Carrier puts beside `running` while the epic is in that stage.
It is off until named, because it is one more write to GitHub at every stage change.
_Avoid_: phase label, step label.

**Reason label** - An optional label, named in `labels.reasons` for a kind of stop (review limit, agent asked for help, retries exhausted, timeout, authentication, workspace, invalid pull request, usage limit, a stage skill that does not exist, an engine error, no reviewer giving a verdict, the lead's limit), that Carrier puts beside `needs human` while the epic waits.
It is off until named.
_Avoid_: cause label, error label.

**Recover (an epic)** - Asking the engine to continue one running epic whose agent is not alive, from its real state: it reads the epic's last execution and GitHub and goes on from there, as the engine does at start.
It refuses when an execution of that epic is really alive, and it never sets a status, stage or round the caller picked.
An epic in needs-human is resumed, not recovered.
See [ADR 0044](../adr/0044-recover-continues-an-epic-from-its-real-state-and-no-command-sets-one.md).
_Avoid_: unstick, fix the state, reset, retry (an execution retry is the automatic one after a technical failure).

**Resume from a stage** - Resuming an epic at `review` or `fix` instead of `ship`, keeping its round, pull request, worktree and blockers.
When the epic stopped on the review limit, resuming gives it more rounds counted from the current one, by default the same number as `maxReviews`, which a flag can change.
The epic keeps that cap as its `roundLimit`; an epic with none follows the live `maxReviews`, and a restart from ship clears it with the rounds.
_Avoid_: restart from review, rewind.

**Stage skill** - The skill a stage invokes, named in the `skills` block of the config (a repo's `skills` replaces what it names): by default Solve's `ship`, `code-review` with `code-post` to publish, and `code-resolve`.
The prompts of ship, review and fix invoke the names the epic was saved with, so a reload does not change a running epic and a restart from ship takes the new ones.
Only the name is configurable; Carrier keeps the prompt around it and the result contract, and the skill has to leave what the engine checks, above all a linked worktree and an open pull request that closes the epic after ship.
See [ADR 0045](../adr/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md).
_Avoid_: command, plugin, custom prompt (the prompt is not configurable).

**Attempt (of an epic)** - The stretch of an epic since its current start: the engine sets its start when it reserves the epic, and a resume starts a new one.
Only the executions of the current attempt count for recovering the epic and for its retry budget, and the retries are back to the maximum with each attempt.
It is not a retry: a retry is the automatic new execution after a technical failure inside an attempt.
_Avoid_: run, try, session (a session belongs to an agent, not to the epic).

**Engine error** - The kind of stop (`engine_error`) for an epic whose own path hit an unexpected error of the engine, or that the poll recovered three times in a row without success.
The reason is the error in one redacted line, and the epic can be resumed.
See [ADR 0046](../adr/0046-an-unexpected-error-stops-the-epic-it-happened-on-and-the-poll-recovers-an-epic-that-lost-its-agent.md).
_Avoid_: crash, internal error.

**Wake-up (on quota)** - An epic stopped in `usage_limit` that resumes by itself once the provider's probe says the exhausted window is back, from the stage where it stopped.
It is off until `limits.autoResume` is set, saves the time as `resumeAt`, checks the probe again before resuming, and does nothing when the wait is longer than `limits.autoResumeMaxHours`.
See [ADR 0049](../adr/0049-a-quota-stop-wakes-up-by-itself-when-the-provider-says-the-window-is-back.md).
_Avoid_: auto-retry (a retry is the automatic new execution after a technical failure), auto-restart, resume by timer.

**Cancelled before it started** - An epic cancelled with no execution yet, because its `ready` label was removed or its issue closed; it goes back to the queue when `ready` returns, with nothing of the cancel left on it.
One cancelled because its pull request was closed, because its issue no longer exists or after it had worked is not this, and stays cancelled.
_Avoid_: dropped, withdrawn.
