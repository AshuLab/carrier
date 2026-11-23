# A review to trust, and an intake in order

Status: spec

## Problem

A review can be recorded on a commit the reviewer never saw.
The reviewer's checkout is made from whatever the pull request's head is when the stage launches, the engine never compares it with the head it stored, and a reviewer that reports a newer head than the one it was given is accepted and that head is marked as reviewed.
When a person pushes while a review runs, the epic stops in needs-human with `pr_invalid` and costs a person's attention, although a new review would fix it.

Around the review, several things make the loop less trustworthy than it looks ([the findings](../research/engine-review-2026-11.md), level 2).
After an observations pass the next review gets the blockers of an earlier round, an epic can go to ready for test with observations nobody answered and nothing says so, and the reviewer's checkout carries what the last round left in it.
One authentication signal stops every epic of a profile, and on `agy` a tool's output can set that signal.
An `api_error` is retried three times in seconds with no wait, the Codex message `usage_not_included` is not recognized as a usage limit, and an exit 0 with an error the tool printed is taken as success.
A fix whose saved workspace is gone shows as a process that does not start, and an error of `git worktree list` after ship stops the epic.

The intake, the way Carrier takes epics from GitHub, has its own problems (level 3).
The queue is ordered by `id`, not by when an epic entered, and GitHub is asked for no order, so the newest epic runs first and a resumed one jumps the line.
An epic cancelled before it started ignores `ready` when it comes back.
One repo that GitHub answers badly aborts the poll for every repo, and a rate limit is swallowed so the poll goes on asking.
Labels are written wrongly in four ways: `ready` is taken off only while the epic runs, so a failed write can restart a stopped epic by itself; one removal is sent for every label the issue lacks; a repo that left the config still gets writes; and some stop messages do not say what happened or what to do.
A cleanup that kept a worktree or a branch is marked as done, so what was kept is never seen again.

It hurts whoever runs Carrier on real epics, today Diego, and we know because the review of the engine found each of these in the code and the first epic of this series ([the engine never leaves an epic stuck](engine-never-stuck.md)) left them untouched.
This is the second of four epics that come out of that review, and the other two start from `main` once this one is merged: [the rest, in order](carrier-engine-improvements.md).

## Solution

One epic in two parts, a review to trust and an intake in order, that do not depend on each other except that the failure recognition goes before the retry waits.
Both build on what the first epic left: the attempt rule (only the executions since the epic's current start count), `engine_error` and the isolation of one epic's errors, the cap of rounds that each epic keeps (`roundLimit`), and the resume from a stage.

### A review to trust

The decision is [ADR 0047](../adr/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md), with the rules below.
The head a review was given is the commit its checkout is at, which the checkout reports, and not the head the epic stored: the two differ when someone pushed in between.
The review's prompt tells the reviewer that commit, and the result must carry it as its head or it is an invalid result and is retried.
When the head GitHub has at the end of a review is not that commit, the engine stores the new head, reviews again without counting a round, at most twice in a row, and then stops the epic in needs-human with `pr_invalid`; the count of repeats in a row starts again when a review completes on its own head, and a new attempt clears it.
The result of a review of a head that was superseded is kept as an execution but is never read: the blockers and observations of the next round never come from it.
A resume at `review` after the head moved adopts the new head, since the review looks at it anyway; a resume at `fix` still refuses, because the blockers it hands to the author belong to the head the epic stored.

The decision on authentication is [ADR 0050](../adr/0050-one-authentication-signal-is-a-technical-failure-of-its-epic-and-a-profile-stops-when-it-repeats.md).
A first authentication signal of a profile ends that execution as a technical failure, retried like any other, and the profile's other epics go on; a second signal of the same profile, in the retry or in another epic, stops every epic of the profile as today, and any execution of the profile that ends with no signal clears the memory.
On `agy` the plain text `Authentication required` counts only when it comes on stderr, and the structured result that says authentication failed or timed out keeps counting wherever it comes.
The real message of an authentication error is kept with the epic as the reason it stopped, and not only in `stderr.log`.

The retries wait by kind.
An `api_error` is retried after 30 seconds, then 2 minutes, then 10 minutes, by its position in the epic's failures of this attempt; when the epic has more retries than three the last wait repeats, and when failures of different kinds mix, the wait is by the kind of the failure that just ended and its position in the streak.
A process that died is retried at once, as now.
The wait is a due time the engine keeps and not a sleep inside its handler: it never delays shutdown, a retry that comes due while the engine is down starts at the first poll after it starts, and an engine that stops cancels nothing that is saved.
The Codex message that starts with `usage_not_included` is a usage limit, with no reset time, and an exit 0 with an error the tool printed is a failure, taken to failover when it is a usage limit, but only when no valid result file was written, so an error the tool printed and recovered from never fails a good run.
No regular expression guesses at quotas: a false positive would stop an epic as `usage_limit` over a passing error.

What a round carries is made right.
The blockers handed to a review are none when the latest review completed.
An epic that goes to ready for test with observations left unanswered records how many and why (`already_taken` when the one pass was already used, `last_round` when the round was the last the epic's cap allows, read from the epic's own cap), and the panel, `carrier status` and the replies the app reads carry it, with no change to what the engine does.
The checkout of a reviewer is reset to its head and cleaned of what is not tracked before each round, keeping ignored files so a review does not rebuild its dependencies, and a failure of that preparation is a stop of kind `workspace`.
A fix whose saved workspace does not exist stops the epic in needs-human with the kind `workspace` and a clear reason, with no retry spent, and so does a resume or a recovery that reaches it.
The ship prompt tells the agent to take the head from `gh pr view`, because the author's folder for ship is the shared clone and `git rev-parse HEAD` there is not the pull request's head.
An error of `git worktree list` after ship is not a stop: the result is left to be settled again, up to three times, and then it is a stop of kind `workspace`; a worktree that is really missing still stops at once.

### Intake in order

The queue is first in, first out: by when the epic entered it, and then by `id`, asking GitHub for the oldest first.
An epic that enters the queue, new, resumed or requeued, gets a position after every epic already in it, so two never tie and the one that resumed goes to the end of the line; when a slot is free it still starts at once, and it waits only when there is competition.
The order of the queue the app shows is the same.
An epic cancelled before it started, because its `ready` was taken off or its issue was closed, and that has no execution yet, goes back to the queue when `ready` comes back, since no work was lost; the requeue clears everything the cancel left, the reason, the cleanup mark and the wake-up fields.
An epic cancelled because its pull request was closed without a merge stays cancelled when `ready` comes back, and so does one cancelled because its issue no longer exists, or one that had already worked when it was cancelled: no command is added for them, and a person who wants the work again opens a new epic.
The epic records why it was cancelled as a kind and not only as a text, and the poll decides by the kind.

A repo that fails with GitHub unavailable (a timeout, a 5xx, a network error) is skipped for that cycle and shown with its reason, the others are read, queued and launched as usual, and the longest wait GitHub asked for is kept for the next cycle.
The repos are still read one after another, so a repo that does not answer costs its timeout once per cycle.
A rate limit is not a repo's problem but the account's: it ends the poll, in the reads of progress, slices and pull requests as in the listing, and Carrier waits what GitHub asked for.

Labels are written right.
`ready` comes off the issue in every status except queued, so a failed write cannot restart a stopped epic by itself, and the `ready` that a resume or a wake-up puts on a stopped epic is read by the poll before the reconciliation takes it off, as the first epic left it.
A status change removes only the owned labels the issue has, read from the issue as the poll already read it, or once from GitHub when the change comes from a request; the ready listing and the open listing are read once per repo and cycle.
Carrier writes no label for a repo that left the config, whatever the status of the epic.

The messages say what happened.
A timeout says the limit that ended it and what to do next, `retries_exhausted` says the kind and message of the last failure, and a stop that comes from a provider's 5xx says that, not that the epic ran out of usage.
An epic whose cleanup kept a worktree or a branch is still marked as cleaned, so the cleanup does not repeat for ever, and what was kept is an event of the epic so it shows.

### What was cut, and why

A probe for a token before treating an authentication signal as a failure lost, because the token the engine can mint is the GitHub profile's and the signal of Claude, Codex and `agy` is about the model's account, so a token that mints proves nothing about a logged out agent.
Re-pointing a review to the new head while it runs lost, because the reviewer has read the old one and its verdict would mix two commits.
Counting a repeated review as a round lost, because the limit of rounds is about how many times the author and the reviewer disagree, and a push from outside says nothing about that.
A guess at quota texts by pattern lost, because a false positive would stop an epic over a passing error.
Sleeping inside the handler for the retry wait lost, because it would block shutdown for up to ten minutes.
Deleting every untracked and ignored file of the reviewer's checkout lost, because the reviewer would rebuild its dependencies at every round for a gain no finding asked for.
A command to restart an epic whose pull request was closed lost, because it is a command that sets a state, which the first epic refused, and the work is better asked for again as a new epic.
Reading the repos in parallel lost, because the finding is about one repo stopping the others, which skipping fixes, and parallel reads change how the engine talks to GitHub.

## Scope

1. As the person, a review whose result carries a head other than the commit its checkout was made at is an invalid result and is retried, and the reviewer is told that commit.
2. As the person, when the head of the pull request moves while a review runs, the review is made again on the new head without counting a round, at most twice in a row, and then the epic stops in needs-human with `pr_invalid`.
3. As the person, the result of a review of a head that was superseded never feeds the blockers or observations of the next round.
4. As the person, resuming an epic at `review` after its head moved reviews the new head, and resuming at `fix` refuses while the head is not the stored one.
5. As the person, a first authentication signal of a profile makes that epic's execution a technical failure that retries, and the profile's other epics go on.
6. As the person, a second authentication signal of the same profile, in the retry or in another epic, stops every epic of that profile, and an execution of the profile that ends without one clears the memory.
7. As the person, the real message of an authentication error is kept with the epic as the reason it stopped.
8. As the person, on `agy` the plain text `Authentication required` counts only on stderr, and the structured result that says authentication failed or timed out still counts.
9. As the person, an `api_error` is retried after 30 seconds, then 2 minutes, then 10 minutes, and a process that died is retried at once; the wait never delays shutdown and a retry that came due while the engine was down starts at the first poll after it.
10. As the person, the Codex message that starts with `usage_not_included` is a usage limit, and an exit 0 with an error the tool printed and no valid result is a failure, and no longer a success.
11. As the person, an epic that goes to ready for test with observations left unanswered says how many and why, in the panel, in `carrier status` and in the replies the app reads.
12. As the person, a review never receives the blockers of an earlier round when the latest review completed.
13. As the person, a fix whose saved workspace does not exist stops the epic in needs-human with the kind `workspace` and a clear reason, and does not burn its retries.
14. As the person, the reviewer's checkout is reset to its head and cleaned of untracked files before each round, and a failure of that preparation is a stop of kind `workspace`.
15. As the person, the ship prompt takes the head of the pull request from `gh pr view`.
16. As the person, an error of `git worktree list` after ship is retried up to three times and then stops the epic with the kind `workspace`, and a worktree that is missing stops it at once.
17. As the person, queued epics start in the order they entered, an epic I resumed goes to the end of the line, and the queue the app shows has the same order.
18. As the person, an epic cancelled before it started because its `ready` was removed or its issue closed goes back to the queue when `ready` comes back, with nothing of the cancel left on it, and one cancelled because its pull request was closed without a merge, because its issue no longer exists or after it had worked does not.
19. As the person, a repo that GitHub answers slowly or with an outage is skipped for that cycle with its reason, and the other repos are read, queued and launched as usual.
20. As the person, a rate limit anywhere in the poll ends it, and Carrier waits what GitHub asked for instead of going on asking.
21. As the person, `ready` is taken off the issue in every status except queued, and the `ready` that a resume or a wake-up puts on a stopped epic is still seen by the poll before it is removed.
22. As the person, a status change writes only the labels that are on the issue and not one removal per label that is missing, and each repo's listings are read once per cycle.
23. As the person, Carrier writes no label to a repo that left the config.
24. As the person, a timeout stop says the limit and what to do next, a retries-exhausted stop says the kind and message of the last failure, and a stop caused by a provider's 5xx does not say the epic ran out of usage.
25. As the person, an epic whose cleanup kept a worktree or a branch is marked as cleaned, and what was kept shows as an event of the epic.

## Decisions

The data. The epic carries the count of reviews repeated in a row for a moved head (per attempt), how many observations were left unanswered with why, and the kind of its cancel.
The epic's events gain one for a review repeated on a moved head, one for a cleanup that kept something, and one for a requeue of a cancelled epic.
A retry's due time is kept with the epic, so a restart of the engine finds it.
Each of these that is a column comes with a migration made by `pnpm db:generate`, and the slices that add a migration are ordered one after another so two never create the same number.
An epic saved before this version is read with the defaults: no repeats, no unanswered observations, and a cancel with no kind that is never requeued.

The checkout of a reviewer reports the commit it was made at (`prepareReviewer` returns the path and that commit, and the `Workspaces` port and its fake follow), and the engine passes it to the review's prompt and compares it with the result.
The adapters of the harnesses learn which stream a line came from (`HarnessAdapter.parseLine` gets the stream), and a line signal carries the text of an authentication error and not only that there was one.
The profile's authentication memory lives in the engine and is not saved: a restart forgets it and costs at most one more signal.

The rule of the review round, for what changes in the stage loop; the rest is as in [the orchestrator spec](autonomous-orchestrator.md).

| After | Condition | Next |
| --- | --- | --- |
| review | result head is not the checkout's commit | invalid result, retried |
| review | the head GitHub has is not the checkout's commit, repeats below two | the review again on the new head, not counted |
| review | the head GitHub has is not the checkout's commit, repeats at two | needs-human `pr_invalid` |
| review | the epic's cap of rounds reached with observations left | ready for test with the count and `last_round` |
| pass | observations left after the pass | ready for test with the count and `already_taken` |

The waits of the retries, as the contract:

```ts
// the wait before retry n (1-based) of an api_error, in milliseconds; a process that died waits 0
const apiErrorWaits = [30_000, 120_000, 600_000]
const wait = (n: number) => apiErrorWaits[Math.min(n, apiErrorWaits.length) - 1]
```

The control socket. No new request or capability: the replies the app reads gain the unanswered observations as an optional field, per the checklist of `src/control/AGENTS.md`, with the goldens and the fixtures under `macos/Tests/Fixtures`; an engine's reply that lacks it is read by an older app as before.
The queue order the app shows follows the same order as the reserve.
`carrier status` shows the unanswered observations and a retry's due time.

Documentation is part of the epic: `docs/troubleshooting.md` (a stop by authentication, a `workspace` stop, a repo shown as skipped, the unanswered observations), `docs/cli.md` (`status`), the CHANGELOG, the glossary, and the specs `resume-a-stopped-epic.md` (the resume at review after a moved head) and `autonomous-orchestrator.md` (the rule of a head that moves) are amended.

Testing seams, per story, preferring the seams the repo has:

- Stories 1 to 6, 9, 11 to 13, 16 to 18 and 20 to 25: the engine through its public interface in `src/orchestration/engine.test.ts`, with the fake `GitHub`, the fake `AgentRunner` that writes, fails, hangs or is cut, the fake `Workspaces`, an injected clock and a real temporary SQLite; a restart of the engine on the same database covers a retry that came due while it was down. The queue order and the reserve are covered where `reserve.ts` is tested, and the pure rule of the waits has its own unit test.
- Story 4: the refusal and the adoption in `engine.test.ts`, and the request in `src/control/server.test.ts`.
- Stories 7, 8 and 10: the failure kinds and the exit rules of each harness in `src/harnesses/claude.test.ts`, `codex.test.ts` and `agy.test.ts`, and the exit 0 rule in `src/harnesses/host-runner.integration.test.ts`, gated as the others are.
- Story 11: `engine.test.ts` for the count and the reason, the reply in `src/control/replies.test.ts` as a golden, and the snapshot in `src/status/snapshot.test.ts` with its contract test.
- Story 12: the blockers an engine run hands to a review, in `engine.test.ts` with the fake `AgentRunner` that records its prompts, since `blockers.ts` has no test of its own.
- Stories 14 and 15: `src/execution/git-workspaces.integration.test.ts`, gated, for the reviewer's checkout, and `src/prompts/build-prompt.test.ts` for the ship prompt.
- Story 19: `engine.test.ts` with a fake GitHub that answers `GitHubUnavailable` for one repo and a rate limit for another.
- Story 22: `src/integrations/github.test.ts` for the labels sent and the listings read.
- The macOS side of the contract fixtures and the app's own views are out of this epic.

## Out of scope

The other two epics, in this order: the labels' new defaults and the skills the person names; and several reviewers with a lead.
They are in [the backlog](carrier-engine-improvements.md) and each is specced again from `main` when its turn comes.

Anything in the ship prompt that holds only for Solve's skills, until the skills are configurable in the next epic.

A command to restart an epic cancelled because its pull request was closed, and a failover for a result that is missing, which today is retried four times and never fails over, until a case shows it is needed.

Reading the repos in parallel, and everything the review of the engine found that is only suspected: child processes that outlive their agent, a clone whose base is stale, and the environment a child inherits, until there is evidence.

Pausing one epic while the others run (`hold`), the label orders `carrier:restart*` and a `carrier enqueue` command, until someone needs to act from GitHub.

The macOS app (a card for unanswered observations, the retry's due time) and a CLI setter for the labels.

The review of how Carrier treats text written by third parties that the agents read, and of updating the engine while epics are running.

## Open questions

Which quota messages the recognizers miss, and which exit 0 outputs carry an error the tool recovered from.
Each harness decides `usage_limit` from a short fixed list of texts (Claude only the 429 `usage_limit_reached`, Codex four starts plus the one added here, `agy` three), and anything else is an `api_error`.
It needs real error outputs from each CLI to see which variants fall through, since no pattern will guess them, and the epic does not wait for them: it adds the one prefix the research already names and the exit 0 rule above.
