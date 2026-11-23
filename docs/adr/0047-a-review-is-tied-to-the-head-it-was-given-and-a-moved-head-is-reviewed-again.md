# 0047 - A review is tied to the head it was given, and a moved head is reviewed again

- Status: accepted; amends the rule of the [orchestrator spec](../specs/autonomous-orchestrator.md) that a head that changes during a review stops the epic
- Date: 2026-11-22

## Context

The reviewer's checkout is made from whatever the pull request's head is when the stage launches, and the engine never compares it with the head it stored for the epic.
When the result arrives, the engine checks the head the reviewer reports against the head GitHub has now, so a reviewer that reports a newer head than the one it was given is accepted, and that head becomes the one marked as reviewed.
When the head moves while the reviewer works, the spec stops the epic in needs-human with the kind `pr_invalid`, on the reasoning that the verdict no longer applies and repeating the execution does not change it.
A person pushing a fix while a review runs is ordinary, and stopping an epic for it costs a person's attention and the round.

## Decision

The reviewer's checkout reports the commit it was made at, and a review's result must carry that commit as its head, or it is an invalid result.
When the head GitHub has at the end of a review is not the commit the review was made on, the engine reviews again on the new head and does not count that review as a round.
It does so at most twice in a row for one epic, and the next move stops the epic in needs-human with `pr_invalid`, as the spec said.
A verdict is only ever recorded on the commit it judged, so an unreviewed commit is still never declared ready.
The head a review was given is the commit its checkout is at, not the head the epic stored, and the result of a review of a superseded head is kept but never read for the next round's blockers or observations.
Resuming an epic at `review` after its head moved adopts the new head, and resuming at `fix` still refuses, because the blockers handed to the author belong to the head the epic stored.

## Alternatives considered

Keeping the spec's rule lost, because it stops the epic over something that does not need a person.
Re-pointing the running review to the new head lost, because the reviewer has already read the old one and its verdict would mix two commits.
Counting the repeated review as a round lost, because the limit of rounds is about how many times the author and the reviewer disagree, and a push from outside says nothing about that.
Repeating without a limit lost, because a head that keeps moving would spend agent runs for as long as it moves.

## Consequences

An epic can spend up to two extra review runs, with their model cost, when a head moves.
The review's result gains a rule that an older engine's agents never broke, so a reviewer that reports a different head than it was given now fails as an invalid result and is retried.
The spec's sentence about a head that changes during a review is out of date, and the final spec has to say this instead.
