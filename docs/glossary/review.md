# Review

**Review round** - One pass of every reviewer of the epic over the same head, in parallel, each in its own checkout; with one reviewer it is that reviewer's single review of the final PR. Rounds are numbered, and the limit of five counts them.
It is settled when every reviewer has given a verdict on the round's head, one that a moved head set aside not counting.
It ends when every reviewer has settled, and it counts once toward `maxReviews` however many reviewers it has.
A technical execution failure does not consume a round.
It is not a lead round.
See [ADR 0048](../adr/review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md).
_Avoid_: retry, iteration, review (that is one reviewer's execution), turn.

**Review thread** - A conversation on a line of a pull request's diff, with who opened it, the file and line, whether it is resolved and a link to it on GitHub. The app lists the final pull request's threads in the Review tab, from a cache of GitHub like the slices ([0008](../adr/orchestration/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); a reviewer agent's blocker is a thread too.
_Avoid_: comment (a thread holds several), blocker (what the reviewer agent reports in its result).

**Blocker** - A finding of a review that stops its approval. It has a title and, when the reviewer provides them, a stable id and a mark when a later round resolves it; the app shows each round's blockers and which carry over.
_Avoid_: issue, comment, error.

**Observation** - A finding of a review that does not stop its approval: a nitpick or a suggestion. The reviewer lists observations in a `completed` result, with a title and a stable id like a blocker; when there are any, the author answers them in one resolve pass before the epic is ready for test ([0009](../adr/review/0009-observations-trigger-one-resolve-pass-before-ready-for-test.md)).
_Avoid_: nitpick (one kind of observation), comment, blocker (the one that stops approval).

**Extra reviewer** - A reviewer beyond the mandatory one (`agents.extraReviewers`), up to three, named `reviewer-2` to `reviewer-4` in the engine, in `carrier restart` and in the stored executions.
It runs in the same review round as the Reviewer, with its own GitHub profile, account, model, effort, persona, skill and failover steps, and one verdict among all the reviewers is enough for a round to count.
See [ADR 0048](../adr/review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md).
_Avoid_: second reviewer, co-reviewer, reviewer slot (a slot is a place where an epic runs).

**Lead reviewer** - The optional role (`leadReviewer`) that reviews last, once, after the reviewers agree, on the head they agreed on and in its own checkout, and gives the pull request its formal approval when it finds no blocker.
The engine runs it: the epic goes to the stage `lead` and, when the lead completes, to ready for test with the head the lead approved kept beside the head the reviewers agreed on; a head that moves while it reviews repeats its review.
It has its own skill (`skills.lead`), and the approval it says it submitted is recorded and shown, never required.
When it asks for changes the exchange is between it and the author alone, one lead round at a time, up to `limits.maxLeadRounds`, and then the epic stops in `lead_limit`.
_Avoid_: tech lead, final reviewer, approver.

**Lead round** - One exchange of the lead reviewer asking for changes and the author fixing them, up to `limits.maxLeadRounds` (3 by default).
The epic's `leadRound` is the number of the lead's review in this attempt: it is 1 when the lead first reviews, and the author's fix of the lead's blockers is followed by the lead's review again, one more, on the head after the fix.
The limit is read when the lead's answer is decided, and a lead that asks for changes at the limit stops the epic in `lead_limit`.
It does not count toward `maxReviews` and does not change the epic's review round, and the other reviewers do not see the commits it makes.
A resume at a stage starts it over: the lead gets its rounds again once the reviewers agree.
_Avoid_: round (that is a review round).

**Re-review (of a moved head)** - A review made again on the new head, without counting a round, because the pull request's head moved while the review ran; at most twice in a row, then the epic stops in `pr_invalid`.
It is not a review round: the round count is about how many times the author and the reviewer disagree.
See [ADR 0047](../adr/review/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md).
_Avoid_: retry (a retry is the new execution after a technical failure), second round.

**Unanswered observations** - The observations of the last review that no author pass answered because the one pass was already taken (`already_taken`) or the round was the last the epic's cap allows (`last_round`); the epic goes to ready for test with their count and the reason.
_Avoid_: ignored observations, skipped comments.
