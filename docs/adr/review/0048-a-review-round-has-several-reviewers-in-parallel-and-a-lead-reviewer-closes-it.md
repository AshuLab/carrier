# 0048 - A review round has several reviewers in parallel, and a lead reviewer closes it

- Status: accepted; amends the rule of the [orchestrator spec](../../specs/autonomous-orchestrator.md) that an epic never has two active executions
- Date: 2026-11-22

## Context

The review of an epic is one agent: the engine launches a single `review` execution per round, from the `reviewer` role, and takes its one result as the verdict.
A person who wants the opinion of another provider or model, or of a reviewer with a different skill, has no way to get it.
The config already accepts a `leadReviewer` role, and the setup asks for it and the doctor checks it, but the engine never reads it.
The engine is built on one execution per epic at a time: the retry streak, the recovery from the last execution and the reviewer's checkout are all per epic.

## Decision

An epic has one mandatory reviewer, `agents.reviewer`, and up to three more in `agents.extraReviewers`, each with its own profile, provider, model, effort, persona and, if it wants, its own skills.
A repo overrides them as it overrides the other roles, and an extra reviewer that declares no failover steps takes those of `reviewer`.

A review round is all the reviewers on the same head, in parallel, each in its own detached checkout of that head.
The round ends when every reviewer has settled, with a verdict or with a failure it could not recover from.
A reviewer that fails does not stop the round, and neither does one that answers that it cannot conclude: it has no verdict, and the round goes on with the others.
The round needs one verdict to count, and with none the epic stops in needs-human with the kind `reviewers_failed`, naming each reviewer and why.
The epic records how many reviewers gave a verdict out of how many were configured, and shows it.

The verdicts combine in one way.
If any reviewer asks for changes, the author fixes once with the blockers of all of them, each blocker keeping the id of the reviewer that raised it, and only that reviewer can say it is resolved, and the next round runs every reviewer on the new head.
If every verdict is a completed review, the observations of all of them go to the author in the one pass the epic has, and a head that does not change after it is the head the reviewers agreed on.
A round counts once toward `maxReviews`, however many reviewers it has.
A blocker's id is prefixed with its reviewer so two reviewers' ids never collide.
A reviewer with blockers still open that gives no verdict in a later round is not agreement: the epic stops with `reviewers_failed` and does not go on with the others' verdicts.

The lead reviewer, `leadReviewer`, is optional and runs once the reviewers agree, on that head, with the summaries of the reviewers.
Its skill is `skills.lead`, by default the review skill with a prompt that tells it its role.
The lead, like each extra reviewer, keeps its own option, failover and retry state, and its own failover steps, or those of `reviewer` when it declares none; running out of retries stops the epic with `retries_exhausted` naming it.
If it completes, the epic is ready for test; its skill gives the formal approval of the pull request with the lead's identity, and the engine records whether the lead's result says it submitted one, and does not require it, so a lead that cannot approve does not block the flow.
If it asks for changes, the exchange is between the author and the lead alone: the author fixes and only the lead reviews again, up to `limits.maxLeadRounds`, by default 3, and then the epic stops in needs-human with the kind `lead_limit`.
The lead's exchange does not count toward `maxReviews`, and the other reviewers do not look at the commits it makes.

The epic keeps the head the reviewers agreed on and the head the lead approved, and shows both when they differ.
The rule that an epic never has two active executions becomes: never two of the same role, and never the author and a reviewer at once.

Settled when the epic was specced, against the code as it is after the first three epics.
An epic with one reviewer behaves as it does today and keeps its kinds of stop, because `reviewers_failed` exists only for a round with several.
A reviewer is named by its slot (`reviewer`, `lead` and, for an extra reviewer, its key: [0057](0057-an-extra-reviewer-is-an-entry-of-a-map-with-a-key-a-name-and-a-type.md) replaced the positions `reviewer-2` to `reviewer-4`, which no longer exist), and the prefix of a blocker's id is added only when the epic has several reviewers.
An extra reviewer that has no verdict because a skill the person named is absent for it does not stop the epic, while the mandatory reviewer and the lead do, with `skill_missing` as in [ADR 0045](../orchestration/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md).
Every reviewer publishes its own comments with its review skill, and a profile may be shared between roles: the prefix of the id, not the account, tells the reviewers apart.
All the reviewers of a round are given the same commit, and a head that moves repeats the round with the two repeats of ADR 0047, shared with the lead's own review.
The lead's observations are kept and shown and do not go to the author, and a resume at a stage starts the lead's exchange over.
The options of the extra reviewers and the lead live in the epic's saved configuration and not in a column each; the number of verdicts is read from the executions of the latest round; and whether the lead approved is what its result says (`approval`), because the review decision of the pull request is empty in a repo that requires no review.
An extra reviewer that declares no failover steps of its own takes `failover.roles.reviewer`, and the lead takes it when `failover.roles.leadReviewer` is empty.
A stop in `reviewers_failed` does not wake by itself, and a round whose every failure was a quota one stops in `usage_limit` so the wake-up applies.
A round is its number and its head, it is decided in the transaction that imports its last result, and a head that moves stops the round's other running reviewers; the repeats of ADR 0047 count rounds, not executions.

## Alternatives considered

Reviewers one after another lost, because the person chose parallel and the wait for several reviews adds up; it would have kept the one-execution rule and the simpler recovery.
A `reviewers` list in place of `reviewer` lost, because it breaks every config and the app, which read `agents.reviewer`.
Repeating the whole round, reviewers and lead, after the lead asks for changes lost, because the lead is the final reviewer by design and the exchange with the author alone is cheaper.
Stopping the epic when a reviewer fails lost, because an extra reviewer that is down would then block reviews that worked.
Requiring the formal approval on GitHub lost, because GitHub does not let a pull request's author approve it and an app may lack the permission.

## Consequences

The retry streak, the recovery and the checkout have to work per execution and not per epic, which is why the fixes that scope them to an attempt come first.
A person's Mac can run up to four reviewer processes for each epic at once, so three epics may mean twelve agents.
An epic can reach ready for test with fewer reviews than configured, and with a final commit that only the lead saw, and both are shown and not hidden.
The stage `lead` is new, with its optional stage label, and `reviewers_failed` and `lead_limit` are new kinds of stop with their reason labels and their lines in the app.
The executions and the epic's saved results carry which reviewer they belong to, so the schema and the replies the app reads change, and the fixtures with them.
The cost of an epic grows with the number of reviewers and with each round.
