# 0056 - Subagents live in the window header, and a conversation keeps only the run line

- Status: accepted
- Date: 2026-11-26

## Context

The chat spec ([subagents in the chat](../../specs/subagents-in-the-chat.md)) draws each subagent as a row under the run that launched it, with the height and radius of a call group's line, and tapping it opens a view that replaces the conversation. The rows are the same shape as every other line of the conversation, so a subagent reads as one more tool call, and the person wants everything about subagents to have an imprint of its own, apart from tool calls, skills and the rest.

The rows also live where the subagents were launched, so they scroll away with the conversation, pile up when the agent launches several times, and are as heavy as the agent's own work. The same spec already ruled out a right panel, tabs, subagents as children in the sidebar and a hover peek, so those stay lost.

## Decision

We give subagents one entry of their own in the window's header, the Subagents button, and one list behind it, the Subagents list, and a conversation draws no subagent row. The conversation keeps only the run line that already says "N subagents" while they run and how they ended after.

The button exists from the first subagent a session launches. While a launch runs it shows that launch, and when nothing runs it folds into one quiet button with the session's total, so a finished session still shows that there were subagents. A launch that finished leaves the header and is only in the list, under a time bar that separates it from the next one. The list is the only place where every subagent of a session is listed, nested under the one that launched it, and it is the way into the subagent view, from the conversation and from another subagent view alike.

A subagent has no colour or avatar of its own: colour is kept for what needs attention, which is a red dot on a failure, and a finished subagent has no mark but is dimmed.

## Alternatives considered

Keep the rows in the conversation. It changes nothing for the person, and it is the one thing they asked to change: a subagent keeps looking like a tool call.

A card or a thread for each subagent in the flow, or lanes on a time line. They give a subagent a body of its own and keep its place in the conversation, but they are taller than a line, fill a long session, and the lanes say when and not what.

A dock above the message box. It keeps the state in sight, but it is a second surface next to the box, where the approval card and Stop already compete.

The avatars of the subagents on the run line of the conversation. It leaves a trace in a stored session, and the person chose to leave the conversation with the run line only.

A cluster of coloured avatars in the header. It was the first shape of this idea and it was dropped for its weight: four colours plus a green tick and a red cross, and a width that has to degrade as the window narrows. One button has the width of the others of the toolbar.

A cluster that disappears when its subagents end. It leaves a finished subagent with no way to be opened, because the conversation has no row either.

A Stop all in the list. The message box's Stop already stops the turn and the subagents that run, so the button would be a second way to the same end, next to a row.

## Consequences

A subagent is a thing of its own, shown by one quiet button, and the header does not grow with the number of subagents. The conversation of a stored session says little about them: the run line and the button are all there is, so what a subagent did is read by opening the list.

The failure of a finished launch is not in the header while a later launch runs; it is in the list only, by the person's choice.

The subagent view is one component that the slice card of the Agent output tab opens too, so the Brief card that replaces its brief bubble shows there as well. The epic's tab, its slice card and the Carrier section are not touched by this record.

Showing the result of a subagent or why it failed needs the host to forward what the provider's end notification says, which the host drops today. Until it does, the list and the view show the state, the steps and the time, as they do now.
