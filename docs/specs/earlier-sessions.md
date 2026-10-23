# The Agent output tab lets you open the sessions it folds away

Status: spec

## Problem

The macOS app's Agent output tab shows one card per agent session of an epic, newest first, and only the three newest. The rest are summed up in a line of plain text, `1 earlier session`, that cannot be clicked. The oldest session of an epic is the builder's (the ship), so as soon as there are four sessions (a ship, a review, a fix and a second review) the builder is the one hidden, and nothing in the app lets Diego read it. Found testing the slice rows of epic #272: the tab said `1 earlier session` and the builder, where those rows live, was unreachable.

It is not caused by that epic. The cap of three came with the first version of the tab, with no reason recorded, and the design mockups drew the line as text too, so it was never given a way to open. On epic #244 it would have said `7 earlier sessions`: seven ship attempts (five of them failed by the orphan bug since fixed, one quick, one good), then a review, a fix and a second review.

## Solution

Diego wants the tab as it is, with a different limit and a way through. The list shows the five newest sessions, and what is older is collapsed behind one row at the cut, `Earlier sessions · N`, that opens when pressed and shows all the rest with no limit, in the same cards. Pressed again, it closes. With five sessions or fewer there is no row.

Five covers a normal epic: the builder is the fourth from the newest in the sequence above, so it shows without pressing anything. It is hidden again only when an epic has three or more review rounds (a ship, then a review and a fix per round: the sixth session and older), and then the row opens it.

The older sessions are drawn like the others, with their state (a failed one carries the stopped badge) and their counts, and all of them folded when the row opens, whatever their state: the rule that a stopped session opens by itself belongs to the sessions in view, and would fill the screen with failed attempts. Their events are asked for when the row opens, to draw the counts as for the sessions shown from the start, and not before.

The row sits at the cut, between the fifth session and the older ones, so that closing it is at hand however long the list is. The reference is the prototype `docs/research/macos-app-design/explorations/earlier-sessions-options.html`, option A. The row is the app's own look: the glass row of the slices (the surface of the window's controls), a clock icon, `Earlier sessions` with the count after it, and the round chevron on the right that every card has, turned up while the row is open. It has no other element.

What lost: showing every session with no limit, because each session asks for its events to draw its counts and an epic with many failed attempts would fetch them all at once to open the tab; pinning the builder on top, because an epic can have several ship attempts and none is the builder more than the others; filtering out the failed attempts, which Diego did not ask for and which are the only trace of why an epic took long; the row after the last session with `Show fewer` at the very bottom, because with a long list the way to close it is a long scroll away.

## Scope

1. The tab shows the five newest sessions of an epic, newest first, as it showed three.
2. When an epic has more than five sessions, one row, `Earlier sessions · N` with N the number of older ones, sits right after the fifth; with five or fewer there is none.
3. Pressing the row shows all the older sessions below it, newest first, with no limit; pressing it again hides them.
4. An older session is a card like the others, with its state, counts and a folded body, and it is folded when the row opens whatever its state.
5. The events of the older sessions are asked for when the row opens (for their counts) and not while it is closed.
6. The row is a glass row with a clock icon, its title and count, and the round chevron on the right, up while open, and nothing else.

## Decisions

The cap is `visibleSessions = 5`. `SessionList` stops carrying the line as a string: it carries the shown sections and, apart, the older ones as sections too (empty when there are none), built whether the row is open or not since that costs nothing without their events; the view decides what to draw. An older section is never open by default.

```swift
public struct SessionList: Equatable {
    public var sections: [SessionSection]   // the newest `visibleSessions`
    public var earlier: [SessionSection]    // the rest, newest first; empty with five or fewer
}
```

Whether the row is open is state of the view of the epic, kept with the folds the person made by hand (`SessionFolds`), so it lasts as long as they do and is not a setting. `epicFocus`, which says which sessions the poller asks events for, counts the older sessions' ids only when that state is open.

Testing seams, by story:

- Stories 1, 2 and 4: `sessionList` in `SessionSectionsTests`, with canned replies of 5, 6 and 12 sessions (the existing helpers `reply` and `many`): the five newest in `sections`, the rest in `earlier` newest first, none with five, an older stopped session not open by default. The existing tests that expect `earlier` to be a string and three sessions change with the type and the cap.
- Stories 3 and 5: `SessionFolds` and `epicFocus` in `SessionSectionsTests`, in the style of its existing focus tests: pressing flips the state, and the older ids are in `counting` only when it is open.
- Story 6: the row's look has no automated test, as with the other macOS views: the prototype is the reference and the owner reviews it in the app. Its height, closed and open, is held by a small `ImageRenderer` test in the style of `LaneHeaderTests`.

## Out of scope

Filtering or searching the sessions. Removing the failed attempts. A setting for the limit. Changing what a session card shows. The slice rows inside the builder session, which are the epic #272.
