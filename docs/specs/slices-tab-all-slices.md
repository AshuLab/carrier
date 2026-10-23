# The Slices tab shows every slice of the epic, up to date

Status: spec

## Problem

The Slices tab of the macOS app is where Diego looks to know how an epic is going, and it fails him in two ways.

It is late. The engine reads an epic's slices from GitHub only inside its poll, which by default runs every five minutes, so a slice that was just taken, opened as a pull request or merged shows its old state until the next one. It happened for real on epic #311: the agent took slice #312 at 14:23:48, the engine's last read was at 14:22:31 and had it as `ready`, and the tab showed it as "Waiting · ready to start" while the agent was working on it. The same delay holds back the ring's merged count.

It shows the epic in pieces. The legend under the ring (Merged, In progress, Waiting) works as a selector and the list under it shows one group at a time, so there is no way to see at once which slices are merged, which are being built and which are still to come. Each slice's dependencies are there only as a line of detail in the Waiting group, away from the slices they depend on.

## Solution

Two pieces of one epic, buildable in any order, because Diego's problem is one: to see the real, current state of the epic's slices and what depends on what.

The list shows every slice of the epic at once, in one flat list ordered by issue number, which is the order `to-tickets` publishes them in and so the order they run in; a slice added later with a higher number than the one it depends on will sit out of order, and that is accepted. Each row has its state as an icon at its left: a green check for merged, the turning ring for in progress, an empty circle for pending. A pending row says why in its detail: `ready to start`, or `after #312 <title>` for a slice blocked by another slice of this epic, with the number first so it can be found in the list (several blockers are listed in a row, separated by commas). The Waiting group is renamed Pending, which is the word Diego uses. The exploration with the chosen design is in `docs/research/macos-app-design/explorations/slices-tab-all-slices.html` (the Proposed column).

The totals above the list (merged, in progress, pending, and a fourth item, Total) are filters, one selected at a time like a choice: selecting Merged shows only the merged slices, selecting In progress shows only those and Merged is no longer selected, and the filters never add up. Total shows every slice and is the one selected when the tab opens. The selected item is shown by its highlighted row alone, with no check mark, and the highlight is the accent colour the person chose in the system settings, not a fixed blue; the blue of in progress stays the status colour it is. There is no line between the totals and the list, and no other line about the filter. A filter whose group has no slices left (the last one in progress merged) is no longer a filter and the list shows every slice again. The ring stays as it is. Ready and blocked slices count together as pending, because the row already says which they are. Skipped slices stay out of the ring, the totals and the list, as today, so the total can differ from the sub-issues listed on GitHub.

The dependencies shown are those between slices of the same epic. A slice blocked by something outside the epic keeps showing the blocker as it does today, and an epic blocked as a whole by another epic is not a thing Carrier knows.

For freshness the engine refreshes an epic's slices as soon as something that changes them happens, and keeps a timer as a net. When a command of the agent ends (the `tool_end` of its normalised events, never the start, because GitHub does not reflect the change before) and it is one of a fixed list (`gh issue edit`, `gh issue close`, `gh pr create`, `gh pr merge`, `gh pr ready` and `gh pr close`), the epic's slices are read again from GitHub with the same query as today. The command is only a signal to look; the data still comes from GitHub, so a missed or false detection costs a query or one timer period and never a wrong state. Bursts coalesce into at most one read every ten seconds per epic, and a timer reads the live epics' slices every minute whatever happens, which also covers a slice taken by hand on GitHub. The cost is one query of cost two per read, a few dozen an hour per epic against a limit of five thousand points. ADR 0008 keeps the slices as a cache of GitHub; what changes is when it is read, which is no longer only at each poll, and the rule that live epics are read every poll stays.

What was cut. The app guessing which slice is in progress from the live session lost because the session does not say which slice it works on exactly (glossary: Subagent), and a guess drawn as a fact is worse than a delay. Only the timer, with no signal from the events, lost because it either keeps the delay of a minute or reads constantly. Refreshing only when a session ends or the stage changes lost because a slice takes its claim, its pull request and its merge well inside one session. Sections by state one under the other lost to the flat list because they split the epic again. Showing one group at a time, with the legend as a selector, is what hurts today. Filters that add up lost because Diego reads the tab as one choice at a time. A check mark on the selected total lost because the highlighted row says it already. Showing the dependencies of other epics lost because Diego wants this epic's own slices first. A way to read slices more often by polling harder lost because it spends the rate limit on every repository for the sake of one epic.

## Scope

1. As Diego, I see every slice of the epic in one list, ordered by issue number, when I open the tab.
2. As Diego, I read each slice's state from the icon at the left of its row: merged, in progress or pending.
3. As Diego, I read why a pending slice is pending: `ready to start`, or `after #N <title>` with every blocker of this epic that is still open.
4. As Diego, I see the totals Merged, In progress, Pending and Total, and pressing one shows only the slices in that state while the others deselect; Total shows them all and is the selected one when the tab opens.
5. As Diego, I see the selected total highlighted in my system accent colour, with no check mark and no line between the totals and the list.
6. As Diego, when the last slice of the filtered state leaves it, I see every slice again.
7. As Diego, I see a slice as in progress within seconds of the agent taking it, and as merged within seconds of its merge, without waiting for the engine's next poll.
8. As Diego, a slice taken by hand on GitHub shows within a minute.
9. As Diego, I never see a state the engine made up: every row is what GitHub said at the last read.

## Decisions

The model in `CarrierCore` carries the list, the filter and the totals; the view only draws them:

```swift
public enum SliceGroup: CaseIterable, Hashable { case merged, inProgress, pending }   // title "Pending" (was waiting)
public enum SliceFilter: Equatable { case all, only(SliceGroup) }

public struct SliceRow: Equatable {
    // ... number, title, prNumber, issueURL, prURL as today
    public var state: SliceGroup
    /// merged: its time; in progress: lane and activity, or "working"; pending: "ready to start" or "after #N <title>, #M <title>".
    public var detail: String
}

// slicesTabModel(subject, reply:, filter: SliceFilter = .all, now:) -> rows of every non-skipped slice by number, filtered;
// legend: the groups with slices in ring order, plus the total; a filter whose group has no slices behaves as .all.
```

A blocker whose title is not among the epic's slices (a slice of another epic) is shown as `#N` alone, as today.

In the engine, the list of commands is one pure function with the allowlist spelled out, applied to the `arg` of a `tool_start` and acted on at the `tool_end` of the same `callId`, in the `run.onEvent` hook where the events are already recorded:

```ts
const changesSlices = (command: string) =>
  /(^|[\s;&|(])gh\s+(?:issue\s+(?:edit|close)|pr\s+(?:create|merge|ready|close))(?=\s|$)/.test(command);
```

This holds for a compound command (`cd x && gh pr create ...`), for repeated spaces and for a leading environment variable, and does not match `gh issue view`, `gh pr list`, `ghost issue edit` or an empty string; a command longer than the 1 KB the event keeps may be missed, and the timer covers it. A call that ends in error is a signal too, because reading costs one query and the data is GitHub's. The pending calls are kept per execution and dropped when it ends. A read from an event or from the timer goes through the engine's existing slice read (a failed one keeps the last rows, as today) and through a one-read-at-a-time guard per epic, with a trigger inside the ten-second window scheduling a single read at the window's end so the last change is seen. The timer uses the engine's own clock and scheduling, so a test controls it.

Testing seams. The matcher goes through its own table test (every case above, plus a non-string guard where the type allows one). The engine behaviour (stories 7 to 9) goes through `src/orchestration/engine.test.ts`: the fake runner delivers event batches, the fake GitHub counts `readSlices` and can change a slice's answer, and a clock the test controls: a claim command's `tool_end` makes one read and the rows change; a command of the list with no `tool_end` makes none; a burst makes one read per ten seconds with the last change visible; the timer reads once a minute with no events; a failing read keeps the last rows. The tab's model (stories 1 to 6) goes through `macos/Tests/CarrierCoreTests/SlicesTabTests.swift`, the seam that already pins the ring, the legend and the rows: every slice by number, the state and detail of each row, pending with one and several blockers and with a blocker outside the list, each filter, Total, a filter whose group has emptied, skipped slices left out, a queued epic with everything pending. The view, the accent highlight and the icons have no automated test; Diego checks them against the exploration with the fixture, in light and dark and with a non-blue accent colour.

## Out of scope

Dependencies on slices of other epics and epics blocked by epics. The ring's drawing and the rest of the tab's design (the detail line, the PR chip). Skipped slices. Sorting by anything but the issue number. Refreshing the pull request block and the review threads by event, which could use the same signal later. Detecting changes someone makes by hand on GitHub sooner than the timer.
