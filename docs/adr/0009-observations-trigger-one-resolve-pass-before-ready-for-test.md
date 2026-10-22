# 0009 - A review that leaves observations triggers one resolve pass by the author before the epic is ready for test

- Status: proposed
- Date: 2026-10-22

## Context

The review loop only reacts to blockers. A reviewer's `completed` result sends the epic to `ready-for-test` ([the spec](../specs/autonomous-orchestrator.md), transition table), and only `changes_requested` with at least one blocker starts a `fix` turn. A reviewer that finds something worth saying but not worth blocking has nowhere to put it in the result: the contract has `blockers` under `changes_requested` and nothing under `completed`. On the first real epic that finished a review (`vemec/sass-blueprint#635`) the reviewer posted one nitpick on the pull request, the result said `completed`, the epic went to `ready-for-test`, and nobody answered the nitpick. The person who opens the pull request finds the reviewer's remark unanswered, which is not how a pull request is handed over between two people.

The machinery to answer already exists: the `fix` turn invokes the `code-resolve` skill, which reads every reviewer comment on the pull request, judges each, changes what holds and replies on each thread. What is missing is a reason for the engine to start that turn when the review did not block. The engine decides only from the result file and never from what is on GitHub ([0001](0001-separate-coordination-from-repo-evaluation.md), [0002](0002-sqlite-authority-labels-mirror.md)), and the cache of review threads the app shows is not allowed to drive a decision ([0008](0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)).

## Decision

The reviewer's `completed` result gains an optional list of observations, each with a title, a stable id and optionally a link, the same shape as a blocker. An observation is a finding that does not stop approval.

When a review round returns `completed` with a non-empty list, the engine starts the author in `fix` mode before the epic can be ready for test, with the observations in its prompt and the instruction to run `code-resolve` on them. The author only replies and changes: it never resolves a thread, because resolving says the reviewer is satisfied and only the reviewer can say that. If the author's result carries the same head as the one that was reviewed, nothing changed and the epic goes to `ready-for-test`. If the head moved, the new commit is unreviewed and the next review round runs, counted against the limit of rounds like any other.

The pass runs at most once per epic. A review that follows the pass and returns `completed` with observations again goes to `ready-for-test` with them visible on the pull request, so the loop always ends. Blockers keep working as today, with no such limit beyond the rounds. A `completed` result with no observations, or without the field, goes to `ready-for-test` as before.

Only the observations the reviewer lists start the pass. `code-resolve` works through every reviewer's comments on the pull request when it runs, so a person's comments already there are answered in the same turn, but a comment left after the epic is `ready-for-test` is not Carrier's to act on.

## Alternatives considered

Always run the author after a review, with or without observations. It matches "there is always one more pass" literally, but on a clean review it spends an execution (minutes and a few tenths of a dollar) answering nothing, and it needs no signal from the reviewer, so it hides whether anything was said.

The engine reads the pull request's threads from GitHub to see whether there is anything unresolved. It would also catch a person's comments, but it makes the engine read GitHub to decide, which [0001](0001-separate-coordination-from-repo-evaluation.md) and [0008](0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md) rule out, and an unresolved thread is not the same as one the reviewer left on purpose.

Reading the free-text summary for words like "nitpick". It needs no contract change, but any wording that is not matched is a silent miss.

The author resolves the threads it answers. It leaves the pull request tidier, but it states the reviewer's agreement on its behalf. Replying and leaving the thread open keeps the two roles apart.

## Consequences

The result contract grows one optional field, and the reviewer prompt has to ask for it, so the first reviews after the change are where to check that a reviewer fills it. An epic with observations costs one more author execution and, if the author commits, one more review round. The engine now has one way to reach `fix` that does not come from blockers, so the stage needs to say why it started, for the prompt and for the app. This changes the transition table of the original spec: a conclusive review without blockers is no longer always the last step.
