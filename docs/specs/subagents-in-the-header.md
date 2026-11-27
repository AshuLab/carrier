# Subagents have a place of their own in the window header

Status: spec

## Problem

In a conversation a subagent looks like one more tool call. Each one is a row of the same height, radius and weight as the lines of a Read, a Bash or a skill, stacked under the run that launched it ([subagents in the chat](subagents-in-the-chat.md)), so nothing says that a subagent is another actor and not another call.

The person who asked for this (Diego) does not report something that fails or is missing: what he wants is that everything that relates to subagents has an imprint of its own in the app, apart from tool calls, skills and the rest, that it is lighter than what the first prototypes drew, and that a finished subagent does not stay as a mark that keeps looking at him.

Two facts of the current build shape the answer. A row is where the subagent was launched, so it scrolls away with the conversation and, in a stored session, it is the only trace. And the host forwards a subagent's state, its steps, its last tool and its times, but not the `summary` of the provider's end notification, so the app cannot say what a subagent returned.

## Solution

A subagent stops being a row of the conversation and becomes an entity of the window's header, in the shape [ADR 0059](../adr/app/0059-subagents-live-in-the-window-header-and-a-conversation-keeps-only-the-run-line.md) records.

**The Subagents button.** A round glass button joins the toolbar of a session next to the worktree pill, and it exists from the first subagent the session launches (a session with none has no button, and so does a session stored before the host linked subagents to their calls). It shows two figures and a count. While any subagent runs, a thin arc turns around it and the count is that of the subagents of the launches that still have one running, so a launch that finished has left the header. When nothing runs, the button is one quiet button, with no arc, that counts every subagent the session launched and carries a small red dot if any of them failed. A failure of a launch that finished while another still runs leaves no mark. No subagent has a colour or an avatar of its own: the only colour is that red dot, and a finished subagent has no mark at all.

A **launch** is the subagents of one run of the agent's calls, which is how the app already puts a subagent under a run; a subagent launched by another belongs to the launch of the one that launched it.

**The Subagents list.** Tapping the button opens a list under it, and Esc or a tap outside closes it. Its rows are the line the app uses for a call group, 30 pt high: the type as a chip, the title, the step it is on (or how it ended), its steps and its timer. A finished subagent is dimmed with no tick, a failed one has a red dot, a stopped one is dimmed and says Stopped, and a subagent launched by another hangs under it with a guide and an indent, counted in the button. The launches that run come first, and each finished launch follows under a bar on the session's time line that says when it ran and how long it lasted, and how long ago it ended with its count ("terminaron hace 4 min · 4 subagentes"); a launch has no name on the screen. Inside a launch the running subagents go first, then the failed ones, then the finished ones, and a nested subagent stays under its launcher whatever its state. Every launch is shown open and the list scrolls when it is long.

Tapping a row opens the subagent view, as the row of the conversation did, and the button stays in the header while the view is open, so the person goes to another subagent from the list without going back to the conversation. The ‹ Back button, the title, the state pill and the subagent's Stop are as they are.

**The conversation.** It draws no subagent row, and neither does a subagent view for the subagents it launched: they hang under it in the list. It keeps the run line it has, "N subagents · Waiting for them…" while they run and how they ended after, one for each launch, and the session's sidebar row keeps its cyan ring while a subagent runs. There is no Stop all: the message box's Stop stops the turn and every subagent that runs, and the subagent view keeps its own Stop for that one.

**What a subagent returned.** The host forwards the `summary` of the end notification in the subagent's `task` event, redacted and bounded as the main agent's messages are, and the app keeps it. For a subagent that completed, the subagent view shows it as a Result block after its work, folded when it is long; for one that failed, it shows the summary when the provider sent one and only "Failed" when not; for a stopped one it shows nothing, because the provider sends the title as the summary there.

**The Brief card.** What the subagent was given stops being a bubble that looks like the person's own message and becomes a glass card built on the existing card shell and `chatSurface`, pinned to the top of the subagent view while the subagent's work scrolls under it, with two lines until it is opened. The slice card of the Agent output tab opens the same view, so it wears the Brief card too; that is the only change that reaches the epic's side.

## Scope

1. The host forwards the `summary` of a subagent's end notification (completed, failed or stopped) in its `task` event, and stores it redacted and bounded.
2. The app decodes that `summary` and a subagent keeps it as what it returned.
3. A session's header has the Subagents button from its first subagent on, and none before, and none in an epic's page.
4. While any subagent runs the button has the arc and counts the subagents of the launches that still run; the launches that finished are not counted.
5. When nothing runs the button is quiet, counts every subagent of the session and has a red dot if any failed; while a launch runs, a failure of a finished one leaves no dot.
6. Tapping the button opens the Subagents list and Esc or a tap outside closes it.
7. A list row is one 30 pt line at every width, with the type, the title, the step or how it ended, the steps and the timer, cut and never wrapped.
8. A finished subagent is dimmed with no tick, a failed one has a red dot, a stopped one is dimmed and says Stopped.
9. A subagent launched by another is nested under it and counted in the button.
10. The launches that run come first and each finished launch follows under a time bar with when it ended and its count; inside a launch the order is running, failed, finished; every launch is open and the list scrolls.
11. Tapping a row opens the subagent view; the button stays in the header while it is open and a tap on another row goes to that subagent.
12. A conversation draws no subagent row and keeps one run line for each launch, and a subagent view draws no row for the subagents it launched.
13. The subagent view shows a Result block for a subagent that completed, the summary of a failed one when there is one, and nothing for a stopped one.
14. The subagent view's brief is the Brief card: glass or flat by the person's Surfaces setting, pinned at the top while the work scrolls under it, two lines until opened; the slice card's subagent view shows it too.
15. The button and every row read aloud what they are ("3 subagents, 2 running"; a row by its type, title, step and steps), and no state depends on colour alone.
16. Every new word is a copy key in English and Spanish.

## Decisions

The host change is in the `task` case of `boundEvent` (`src/chat/transcript.ts`): `summary` is cleaned and cut at `chatCaps.message`, like an assistant message, and the adapter's `task()` (`src/chat/claude.ts`) reads `m.summary` for `completed`, `failed` and `stopped`. The event is stored as JSON, so there is no migration. The Swift `ChatEvent` gets `summary: String?`, and `Subagent` keeps it as `report`.

A launch is the `subagents` of one `ToolGroup` of `chatFeed`, which is how a row is already placed under a run; a nested subagent is joined to its launcher by `parentCallId`, as the view already does. The model that builds the list lives in `CarrierCore/Chat` with no SwiftUI: launches, nesting, the order inside a launch, the counts of the button and its state (hidden, running with a count, quiet with a total and a dot).

The header's button and the popover are views of `Carrier/Features/Chat` placed by `panelToolbar` (`PanelToolbar.swift`), in the place the worktree pill has, and the pill keeps its place. The subagent view keeps its header and adds the button to it. The Brief card replaces `BriefBubble` in `SubagentView.swift`, which the slice card's view uses too.

The order inside a launch (running, failed, finished, with nested ones under their launcher) is a call of this spec and not of the person; it changes in one place.

Testing seams, by story:

- 1: `transcript.test.ts` (`boundEvent` with a `task` event that carries a secret and a long summary) and the recorded-session test of `claude.test.ts`, which already feeds `docs/research/chat-spike/claude-subagents.fixture.jsonl` through the adapter and reads the events; it asserts the `summary` on the completed and the stopped ones.
- 2: `ChatConversationTests` decode the golden `Tests/Fixtures/chat-events-subagents.json`, which gets a `summary` on the completed subagent.
- 3, 4, 5: the new list model, in a `CarrierCoreTests/Chat` file, driven with the same events `SubagentRowTests` builds (`chatFeed` of `task` events); one test per state of the button.
- 6, 11: `WindowShellTests`, which already covers `subagents` and `subagentHeader`, for the button staying while a view is open and the list closing; the popover's tap and Esc are looked at under `--fixture`, as the app's other popovers are.
- 7, 8: `SubagentRowTests` style, an `ImageRenderer` height at 480, 560 and 900 pt for each state and a very long title.
- 9, 10: the list model, with a nested subagent, a launch that finished and one that runs, and an empty launch.
- 12: `FeedRowTests` and `ChatConversationTests`: `chatFeed` of the subagents fixture gives one run line for each launch and no subagent row.
- 13: `ChatConversationTests` (`subagentWork` carries the result of a completed one and not of a stopped one) and `SubagentRowTests` style for the block's height when folded.
- 14: no test of its own beyond the view's height, because `chatSurface` is already covered; it is looked at under `--fixture` in glass and flat, in dark and light.
- 15, 16: `ChatSpanishTests` for the Spanish words, and the spoken labels asserted as strings like `Copy.chatSubagentSpoken` is.

The change to the app follows the macOS UI procedure: read [ui](../ui.md), build, open the fixture with three subagents in parallel, one that ends and one that never ends, and look at every state before updating [chat](../macos/chat.md) (which describes the rows and the view as they are today), [ui](../ui.md) and the Changelog, which CI checks.

## Out of scope

The Agent output tab, the slice card, the Carrier section and the epic's header: the person will review that experience apart and wants to change all of it, so this work touches the epic's side only through the subagent view that the slice card opens (the Brief card). No Subagents button or list for an epic.

Writing to a subagent: the view stays read only.

A name for a launch on the screen, and any colour, avatar or monogram for a subagent.

A Stop all, and anything that stops subagents from the list (Stop stays in the subagent view and in the message box).

## Open questions

None. The end notification of a failed subagent carries a `summary` like the completed one's, as the recording in [chat-subagent-failed](../research/chat-subagent-failed.md) shows; the failed subagent's block shows it, and "Failed" alone when the provider sends nothing.
