# Review observations: the author answers what a review leaves before the epic is ready

Status: spec

## Problem

Carrier's review loop only reacts to blockers. A reviewer's `completed` result sends the epic to `ready-for-test`, and only `changes_requested` with at least one blocker starts a fix turn. A finding that is worth saying but does not block has no place in the result, so it stays in the review the reviewer posts on the pull request and nobody answers it. On the first real epic that finished a review, `vemec/sass-blueprint#635`, the reviewer left one nitpick, called it harmless, returned `completed`, and the epic went straight to `ready-for-test`. Diego, who is the one who opens the pull request, finds the reviewer's remark with no reply and no decision, which is not how a pull request changes hands between two people: the author at least reads what the reviewer said, changes what warrants it and answers the rest. It is fixed when a review that leaves observations is followed by the author going over them, replying on each thread, and the pull request reaches Diego with every observation answered.

## Solution

The reviewer's `completed` result gets an optional list of observations, each with a title, an optional stable id and an optional link, shaped like a blocker. The review prompt asks for them: whatever the reviewer would post as a nitpick or a suggestion goes in the list. When a review round returns `completed` with a non-empty list, the engine starts the author in fix mode before the epic is ready, with the observations in the prompt and the instruction to run `code-resolve` on them. Replying and changing are the skill's job, not the engine's; what Carrier guarantees is that the skill runs again on those threads. The author only replies and never resolves a thread, because resolving says the reviewer is satisfied and only the reviewer can say that.

After the pass, the head decides. If the author's result carries the head that was reviewed, nothing changed and the epic goes to `ready-for-test`, keeping the verification the reviewer confirmed on that head. If the head moved, the commit was never reviewed and the spec's rule that an unreviewed commit is never declared ready applies: a new review round runs, counted against the limit of rounds like any other. The pass runs at most once per epic, and never at the last round (there would be no round left to review a commit it made), so a `completed` review that still has observations in those cases goes to `ready-for-test` with them visible on the pull request, and the loop always ends. Blockers work as today. A `completed` result without the field, or with an empty list, behaves as it does now.

Only observations the reviewer lists start the pass. `code-resolve` reads every reviewer's comments on the pull request when it runs, so comments a person left while the epic was running are answered in the same turn, but nothing Carrier does starts from a comment left after `ready-for-test`. The decision and what was weighed are in [0009](../adr/0009-observations-trigger-one-resolve-pass-before-ready-for-test.md).

The app needs little: the Review tab's round already lists blockers, and it lists the round's observations the same way, linked, marked as observations. The pass shows as a fix stage in the timeline. The closing result card already shows the author's own account of what it did.

## Scope

1. A reviewer can list observations in a `completed` result; a result with a malformed list is invalid like any other malformed result.
2. The review prompt asks the reviewer to list its non-blocking findings as observations, and the result contract example shows the field.
3. A review round that returns `completed` with observations, when no pass was taken yet and the round is below the limit, starts the author in fix mode with those observations and the instruction to run `code-resolve` on them, replying and not resolving.
4. A pass whose result carries the reviewed head sends the epic to `ready-for-test` with the reviewer's verification.
5. A pass whose result carries a new head starts the next review round, counted against the limit.
6. The pass runs once per epic: a later `completed` with observations goes to `ready-for-test`.
7. At the last round the pass does not run: a `completed` with observations goes to `ready-for-test`.
8. A `completed` without the field, or with an empty list, goes to `ready-for-test` exactly as before.
9. The Review tab lists each round's observations with their links, marked as observations, apart from the blockers.
10. A restart or a technical retry during the pass resumes it as a pass.

## Decisions

The contract and the transitions, which the tickets inherit:

```ts
// CallerResult, the `completed` variant gains:
observations: z.array(z.object({ id: Id.optional(), title: z.string().min(1), url: z.string().url().optional() })).max(MAX_LIST).optional()
// refined like blockers: the ids that are present are distinct.
```

| From | Result | To |
|---|---|---|
| review | `completed`, observations absent or empty | `ready-for-test` (as today) |
| review | `completed`, observations present, pass not taken, round below the limit | stage `fix` (the pass), same round |
| review | `completed`, observations present, pass taken or round at the limit | `ready-for-test` |
| fix, a pass | `completed`, `pr.headSha` equals the reviewed head | `ready-for-test` |
| fix, a pass | `completed`, a new head | review, next round |
| fix, for blockers | `completed` | review, next round (as today) |

A fix is a pass when the epic's latest review result is `completed`, and is for blockers when it is `changes_requested`; the engine reads that from the stored results, not from memory, so a restart or a retry sees the same thing (story 10). That a pass was taken is one column on `epics` (a timestamp, null until the pass starts), with a Drizzle migration through `pnpm db:generate`. When a review is `completed` with observations the epic stores the reviewed head and the reviewer's verification as it does for a ready epic, while it stays running; the no-change end of the pass only flips the status. A new head leaves them stale until the next review completes, so an unreviewed commit is never declared ready.

The fix task's context carries the observations the way it carries blockers (`context.observations`, read from the latest review result), and the fix prompt takes a second shape when they are there: the same `code-resolve` invocation, the list, the instruction to reply on each thread and leave it open, and the reminder never to merge the final pull request. The review prompt gains the paragraph that asks for observations with the same stable-id rule as blockers. The `epic` reply's rounds gain `observations` shaped like `blockers`; the Swift decoder takes an absent field as none.

Testing seams, per story:

- Story 1: the `CallerResult` schema in its existing suite: valid with observations, with none, with a duplicate id, over the cap, with a wrong type.
- Stories 2 and 3: the prompt builder in its existing suite (the review prompt asks, the fix prompt in its second shape lists the observations and keeps the never-merge line).
- Stories 3 to 8 and 10: the engine with the fake runner and the fake `GitHub` in `engine.test.ts`: one test per row of the table, plus the restart case.
- Story 9: the `epic` reply in its suite, and the review tab model in `ReviewTabTests` with `RepliesTests` for the absent and present decoding; no new test for the view.
- The migration: the existing migrations test.
- Real agents: none in the suite; the open question below is checked by hand.

## Out of scope

Comments a person leaves after the epic is `ready-for-test`; Carrier does not look at the pull request again, as today. The author resolving threads. A second pass for observations after the first one. Anything in `code-resolve` itself: how it judges, what it replies. Merging the final pull request, which stays with a person. Letting a person's comments, rather than the reviewer's list, start the pass.

## Open questions

Whether the reviewer fills `observations` reliably from the prompt alone. It is a matter of the first real reviews after the change, not something to settle on paper; the slice that ships the prompt is checked against a real epic before the rest is trusted.
