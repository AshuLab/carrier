# Review of the engine's flow, November 2026

Read-only review of how an epic goes through the engine, made to find where it can stay stuck, lose work, spend agent runs for nothing or be impossible to control.
Four reviewers each took a stretch (intake and start, the stages, results and retries, recovery and ending), and the findings below are theirs, merged and ordered by what they cost the person.
Nothing was run and no finding was reproduced: "read" says the code was read for it, "checked" says the lead of the review read the lines again, and "suspected" says it follows from the code but no one saw it happen.
Line numbers are those of `src/orchestration/engine.ts` unless a file is named, in the working tree of 2026-11-22 (with the uncommitted label changes), so they drift.
The decisions taken from this are in the four specs that came out of it: [the engine never leaves an epic stuck](../specs/engine-never-stuck.md), [a review to trust and an intake in order](../specs/review-to-trust-and-intake.md), [labels and skills the person names](../specs/labels-and-skills-the-person-names.md) and [several reviewers and a lead](../specs/several-reviewers-and-a-lead.md).

## How an epic goes through the engine

The poll asks each repo for the issues with the ready label, queues them in SQLite, and reserves the oldest one when a slot is free after checking that its issue is still open and ready.
The engine then runs `ship` (the author builds the epic and leaves a final pull request in its own worktree), `review` (another identity checks that pull request in a separate detached checkout) and, when the review asks for it, `fix`, until the epic is ready for test or stops for a person.
A stage ends when its agent process exits, and when it exited well the engine reads the JSON the agent wrote, validates the pull request against GitHub and moves the epic.
A technical failure is retried, a usage limit fails over to another configured provider, and anything else stops the epic in needs-human with a kind.
The skill each stage invokes is written into `src/prompts/ship.ts`, `review.ts` and `fix.ts`.

## Level 1: an epic must never stay stuck

| # | Finding | Evidence | Status |
|---|---|---|---|
| 1 | An ending by usage limit, or by a failure that fails over, is stored with no error, so the retry never sees it and nothing schedules it; only the recovery at start moves it. If handling it throws (`onOption` throws for a provider the epic's saved config lacks, or the SQLite transaction, or `execute`), the epic stays `running` with its last execution failed, and `carrier restart` answers `not stopped`. This matches the symptoms of the epic that had to be edited by hand, but it was not confirmed against that epic's data. | 462, 476-479; `retry.ts:11-15`; 520; 828-836; 1178 | checked |
| 2 | `track` logs an error and `failed` rethrows it when it is not GitHub being unavailable, so an exception in a stage handler becomes an unhandled rejection, and nothing outside the chat host handles one. The engine is started detached and nothing starts it again. | 572-579; 210-214; `chat/host.ts:174` | checked; the crash is suspected |
| 3 | `settlePending` and `retryPending` catch only a refusal by GitHub, so any other exception aborts the poll before it launches or labels anything for any epic, and runs again at the next poll. | 716-725; 541; 1050-1051; 1076-1080 | read |
| 4 | The recovery at start reads each live epic's issue outside the per-repo guard, so a 404 (a deleted issue, a lost access) or a throw in `recoverEpic` stops the engine from starting, and the same error stops each poll that retries the recovery. | 882-883; 1103-1108; `compose.ts:203-209`; 890-895 | checked |
| 5 | After a Resume, `launch` claims the stage before preparing the workspace, and `execute` returns without an execution if the engine is stopping or the epic was parked; the next recovery then sees an old finished execution and calls `launch`, which does nothing because the stage is already claimed. The `interrupted` branch has no stage guard, and `timed_out` after a park has no branch at all. | 363-365; 419; 822-839; 491 | read |
| 6 | The retry budget counts the failed executions before a restart, because the restart keeps the executions, so after `retries_exhausted` the first technical failure of the resumed epic stops it again with no retries. | `retry.ts:11-15`; 521 | checked by the logic |
| 7 | Nothing detects a process that hangs. Only `maxExecutionHours` bounds a run, `lastActivityAt` is only shown, `done` waits for the `close` event that a child holding the pipe can block, and the kill is skipped once the leader is gone. | `host-runner.ts:79-84, 192`; 435 | read |
| 8 | The recovery of the whole engine runs once per process, and `check` and `reload` do not run it again, so on a live engine only a few of the stuck states are moved. A restart also resets the retry streak, so a crash loop retries without limit. | 890-895; 868-871 | read |

What can a person do today for a stuck epic: for one in `running` with no process, only stop and start the engine; for `ready_for_test`, only a merge or a close; for `cancelled` or `merged`, only an edit of the database.

## Level 2: a review to trust

| # | Finding | Evidence | Status |
|---|---|---|---|
| 9 | The reviewer's checkout is made at whatever the pull request's head is at launch, and `prepareReviewer` returns only the path, so the engine cannot compare it with the stored head. The result's head is compared with GitHub's current head, so a reviewer that reports a newer head than it was given is accepted and recorded as reviewed. | `git-workspaces.ts:192-206`; 587-589 | checked |
| 10 | `latestBlockers` takes the latest review that asked for changes without checking for a later one that completed, so after an observations pass the next review gets the blockers of an earlier round as the previous round's. | `blockers.ts:13` | checked |
| 11 | On `agy`, the text "Authentication required" is matched on any stdout or stderr line before the JSON is read, so a tool's output can set it, and one signal stops every epic of that profile. | `agy.ts:52-53`; `host-runner.ts:148, 200`; 500-509 | checked |
| 12 | The workspace of a fix is the saved path, and it is not checked to exist, so a missing folder shows as a process that does not start, retried three times and ending in `retries_exhausted` with a misleading text. | 384-387; `host-runner.ts:186-189` | checked; the message is suspected |
| 13 | An exit 0 with an error the tool printed is taken as success, and the missing result is retried four times and never fails over. A usage limit that is not in a harness's short list is an `api_error`, retried three times in seconds with no wait, and the Codex `usage_not_included` is missing though `docs/research/agent-usage-limit-signals.md` says to map it. | `host-runner.ts:203`; `claude.ts:79`; `codex.ts:50`; `agy.ts:40` | read |
| 14 | The ship prompt tells the agent to take the head with `git rev-parse HEAD`, and the author's cwd for ship is the shared clone, not the pull request's worktree. A wrong head ends in `pr_invalid` with no retry. | `result.ts:35`; `git-workspaces.ts:120` | checked; the effect is plausible |
| 15 | The observations pass is skipped without a mark when it was already taken or the round is the last, so the epic goes to ready for test and nothing says that observations were left unanswered. | 656-659; `control/epic.ts:203` | read |

Also found and kept out of the epic until there is evidence: a reviewer checkout that is reused without a clean, a clone whose local base is not advanced, children of an agent that are not reliably killed, and the whole environment a child inherits (no tokens were found mixed between parallel executions).

## Level 3: intake and operation

| # | Finding | Evidence | Status |
|---|---|---|---|
| 16 | The ready label is removed only while the epic is `running`. If GitHub fails right there and the epic then stops in needs-human, the next poll reads the remaining label as a person saying to go on, and starts it again unattended. | 171; 1041-1043 | checked |
| 17 | Only an epic in needs-human is requeued when `ready` comes back; a `cancelled` one ignores it, including one cancelled because its `ready` was removed while it waited. | 1043 | checked |
| 18 | The queue is ordered by `id`, not by when it entered, and the ready listing asks GitHub for no order, so the newest comes first and runs first in a poll. A resumed epic keeps its old `id` and jumps the line. | `reserve.ts:19`; `integrations/github.ts:161-165` | checked |
| 19 | A repo that fails with GitHub unavailable aborts the poll for every repo, by a choice the code comments. Each call can take up to 30 seconds and the repos are read in sequence. | 1018, 1059-1065; `config/load.ts:15` | read |
| 20 | A rate limit is swallowed by the progress, slices and pull request reads, so the poll goes on asking and ends as a success on the normal interval. | 906, 941, 1004, 971-975 | read |
| 21 | Each label change sends one removal for every owned label the issue lacks (about fourteen with stage and reason labels), and the ready listing and the open listing read the same endpoint twice per repo. | `integrations/github.ts:223-230`; 1025-1026 | read |
| 22 | Label writes are not filtered by the repos in the config, so an ended epic of a removed repo with a pending label still gets written. | 728-737, 163-174 | read |
| 23 | Messages that do not help: `timeout` omits the limit and the next step, `retries_exhausted` for a missing result says only that the file is missing, and the real message of an authentication error goes only to `stderr.log`. A 5xx stop reads "ran out of usage". | 489-491; 344 | read |
| 24 | The cleanup marks an epic as cleaned even when it kept worktrees or branches, so what was kept is never seen again. | 708 | read |

## Checked and found fine

The retry accounting is right inside one attempt (`earlier.length >= max` is max plus one tries, and a failover or a timeout breaks the streak).
A crash after the reserve, or between claiming the stage and inserting the execution, is recovered at the next start.
GitHub being down while a slot is filled is picked up by `resumeStarts` at the next poll.
The retention of logs and sessions touches only ended epics, by an allowlisted id, and does not follow symlinks.
The cleanup of worktrees keeps any with unsaved work and any branch that is not on the remote.
The tokens are made for each execution and live only in the child's environment, and none was found in an argument, a log or the state.
