# The chat shows what the agent waits on and what its subagents do

Status: spec
Source: AshuLab/carrier#1025

## Problem

A person who sends a message and waits cannot tell what the agent is waiting on, nor what its subagents are doing, and the epic's Agent output has the same gap for the subagents it runs.

The live line of a call group already says what runs, with its step, a timer, a glow and "Waiting for your answer". What it leaves out is what makes a wait readable. The timer counts from the start of the turn, not from the call, so a three-minute `pnpm test` looks like a two-second read. A call to an MCP tool reads `Using mcp__linear__create_issue` followed by the raw JSON of its arguments, and nothing says it is an MCP call or from which server. Nothing says that a call is taking long.

Subagents are worse. A call to `Agent` is an "other tool" row with the raw JSON of its input, and when three run at once the line shows only the last one that started. What a subagent does inside is not shown apart from the main thread. The chat adapter (`src/chat/claude.ts`, `translate()`) never reads `parent_tool_use_id` from what the SDK sends, and the SDK's own types say that an assistant message produced inside a subagent carries it, and so does a partial stream event. So a subagent's text, thoughts and calls arrive as if the main agent had produced them, and its streamed text goes into the main agent's message. That is a wrong transcript as well as a gap in what can be seen. The chat's `ChatEvent` (`src/chat/runner.ts`) has no field for a parent, and the app's decoding (`ChatConversation.swift`) ignores any it were given.

The epic's side is half built. The ship parser already reads the agent id and the `task_*` events, and the Agent output tab has the slice card, one per subagent, which opens in place on its calls ([subagent cards](subagent-cards.md)). It draws its calls through the same flow items and `ChatToolGroupView` as a session, so it gets whatever the work card gains. What it lacks is the live last step of a subagent (the engine drops `task_progress`) and the same way of reading a subagent as the chat will have. Subagent UI for the chat was deferred on purpose ([in-app sessions](../research/in-app-sessions.md), [chat host](chat-host.md)), so none of this exists to find; the question was never about discoverability.

## Solution

Three pieces, the first two for the chat and the third for the epic. The design is in two prototypes built against the app as it is: [subagent-view.html](../research/macos-app-design/explorations/subagent-view.html) is the final one, and column A of section 1 of [work-card-kind-chips.html](../research/macos-app-design/explorations/work-card-kind-chips.html) is the chosen live line (the rest of that page, B and the nested X and Y, lost).

**A chip on the live line says what the agent is waiting on.** The call group's line keeps its glow, shimmer and step, and gains a chip by kind: Thinking, Read, Search, Edit, Shell, the MCP server's name for an MCP call (its tool name goes in the words, not `mcp__server__tool` and not the JSON), "N subagents" while subagents run, and "Needs you" while an approval waits. The timer on the right becomes the running call's own; the turn's time stays beside it, quieter, while it is longer. A Shell or MCP call that passes 30 seconds turns its timer amber until it ends, and nothing else changes: that is the whole "this is slow" signal. Once the run ends, its summary counts MCP calls and subagents apart instead of "other tools". This is `ToolKind` and `ToolGroup` growing two cases, and it reaches the epic's Agent output by itself because both draw with `ChatToolGroupView`.

**Each subagent is a row of the chat, and opens its own view.** The parent's call group collapses to one line, "N subagents · Waiting for them…", and under it each subagent is a row with the height and radius of a "Worked" card: its type as a chip, its title (the description it was launched with), the step it is on now, its count of steps, its timer, and a chevron. A finished one shows a tick and its duration; a failed one, a red mark; a stopped one, a square. Tapping a row replaces the conversation with the subagent's view, which wears the window's own header: the round glass button next to the sidebar's becomes a ‹ Back button, the title is the subagent's, the subtitle says "Explore · Subagent of <session>", and in place of the worktree pill there is its state (Running with a timer, or Finished with its time) and a Stop button. The content is what the main agent's is: the brief it was given as a bubble with its own label, then its call groups, thoughts and messages drawn by the same views, with the same live line and chip, and the rows of any subagent it launched in turn. The message box's place holds a read-only note and a Back button. The row, the brief bubble and the note are built on the existing work card shell and `chatSurface`, so the person's Surfaces setting (glass or flat) applies to them as it does to every other card of the conversation.

While a subagent runs the session is working, even when the main agent's turn has ended. The SDK runs subagents in the background by default, so the turn can end while a subagent still works and the SDK opens a new turn when it finishes; the parent is only waiting for its child, and there is work left to do. The session shows as working in the sidebar and the header, Archive and delete refuse it as they refuse a working session, and the host does not close it as an idle one. The message box's Stop, which is there while the session works, stops the running subagents as well as the turn.

**The slice card opens the same view.** In the Agent output tab a slice card keeps its row (its state, slice, counts and pull request) and, when opened, shows the subagent's view with the Back header instead of unfolding in place, its subtitle naming the slice and the epic. Its row also shows the step the subagent is on now, from `task_progress`, which the engine stops dropping.

What lost for the chat. A panel on the right keeps the chat in view while one subagent is open, but squeezes the width and shows one at a time; the person chose the view that replaces the chat, and the same component can later be offered full screen from a panel if that is missed. Tabs per subagent give a quick jump but hide the chat and grow with every subagent. Subagents as children of the session in the sidebar keep the live ones in sight from anywhere, but fill the sidebar with rows that live for minutes, and what removes them is a decision nobody wants. Showing them nested inside the parent's card keeps the feed short, but the person does not want to read a subagent inside the main agent's work. A hover peek is not "see everything".

## Scope

1. The live line of a call group shows a chip before its words: Thinking, Read, Search, Edit, Shell, the server of an MCP call, "N subagents" or "Needs you", whichever is what the agent is waiting on.
2. An MCP call reads its server as the chip and its tool name as the words, in the live line and in the opened step's row; neither `mcp__server__tool` nor the JSON of its arguments is shown.
3. The timer of a live line is the running call's own time; the turn's time shows beside it, quieter, while it is longer.
4. A Shell or MCP call running for more than 30 seconds turns its timer amber until it ends; nothing else of the line changes.
5. The summary of a finished run counts MCP calls and subagents apart ("1 MCP call · 2 subagents") and no longer counts them as "other tools".
6. What a subagent says, thinks and calls is stored as the subagent's and never as the main agent's, and its streamed text never reaches the main agent's message.
7. A subagent shows as a row under the run that launched it, with its type, title, current step, steps, timer and state (running, finished, failed or stopped); the parent's line says "N subagents · Waiting for them…" while any runs, and the launching `Agent` call is not drawn as another tool.
8. Tapping a row opens the subagent's view with a ‹ Back button, its title and subtitle, its state and (while it runs) Stop, its brief, and its call groups, thoughts and messages drawn as the main agent's; Back returns to the conversation.
9. Stop in the view stops that subagent; its row and its view show it stopped once the SDK confirms.
10. A row and its view update as events arrive, including after the turn that launched them ended; a subagent launched by a subagent shows as a row in its parent's view.
11. The session is working while any of its subagents runs: the host keeps its state working after the turn ends until the last subagent ends, Archive, delete and the idle sweep treat it as working, and the message box's Stop stops its running subagents.
12. A session whose stored events predate this change shows exactly as it does today, with no rows.
13. In the Agent output tab a slice card opens the subagent's view instead of unfolding in place, with the slice and the epic in its subtitle, and its row shows the step the subagent is on now.

## Decisions

**The link rides on the chat events, and the history is those events.** The host stores the transcript of a session as its chat events, bounded and redacted ([ADR 0006](../adr/0006-agent-events-stored-in-sqlite-with-bounded-output.md) for the engine's, the same for the chat), and a subagent's view is drawn from them like every other part of it, not from `getSubagentMessages`, which reads the subagent's own transcript file and would bypass that bounding and redaction. A restart of the host keeps the history because it is in SQLite. Sessions that predate the change are not backfilled (story 12). A cursor page of events may start inside a subagent, and the app handles the cut as `ToolCall(orphanEnd:)` handles a call whose start was before the page.

```ts
// src/chat/runner.ts: what ChatEvent gains. `parentCallId` is the call that launched the subagent the event was made in.
| { kind: 'assistant' | 'reasoning'; text: string; parentCallId?: string }
| { kind: 'tool_start' | 'tool_end'; callId: string; /* as today */ parentCallId?: string }
| { kind: 'task'; callId: string; taskId: string; state: 'started' | 'progress' | 'completed' | 'failed' | 'stopped';
    agentType?: string; text?: string; lastTool?: string; tools?: number; tokens?: number; ms?: number; background?: boolean;
    /** The call of the subagent that launched this one; absent for one the main agent launched. */ parentCallId?: string }
```

Every field is read from the SDK's message only when it has the type above, as `translate()` does today ("never throws on a shape it does not know"); anything else gives the events it gives now. A partial text of a subagent is dropped, not tagged: deltas are never stored, and the view shows a subagent's text when its block is finished, which is when the SDK sends it. `taskId` keeps the id that `stopTask` takes; a subagent launched by another has its `parent_task_id` turned into a `parentCallId` through a map of task ids to their launching calls, kept the way the adapter keeps `this.tools` for tool names.

**The app joins by the launching call.** `chatFeed` builds each subagent from the `task` events that share a `callId` and the events whose `parentCallId` is that call, the way `Lanes.swift` joins a subagent's lines through the shared call id, and takes the launching `Agent` call out of the parent's group. The subagent's calls, thoughts and messages become the flow items the view draws. One view component takes flow items from either source: a chat adapter (events to items) and the epic's lane, which `EpicTranscriptAdapterTests` already treats as an adapter. A subagent whose start has no end while its session is no longer working shows as stopped, as an unfinished call does.

**Session state.** The host keeps the set of running tasks of a session (from `started` until `completed`, `failed` or `stopped`) and sets the session `working` on a `task` start and back to `idle` only when the turn has ended and the set is empty; `touch(...)` in `src/chat/sessions.ts` is where `turn_end` sets idle today. A host that restarts has lost its subagents with the process, so on resume a task with no end is shown stopped, by the app's rule above for a start with no end.

**Stop is a new request.** `ChatConversation` gains `stopTask(taskId)`, implemented by the Claude adapter with `Query.stopTask` and absent from the Codex adapter; the chat host's protocol gains a request for it behind its own capability, so an older host is told apart (`capabilities` in `src/chat/server.ts`). The message box's Stop sends it for each running subagent after the interrupt. A `task_notification` with status `stopped` is what ends the row.

**The engine records progress.** `src/harnesses/claude.ts` already turns `task_started` and `task_notification` into `task` events; it also turns `task_progress` into one, keeping the last tool's name and the usage, bounded by ADR 0006. To keep the table from filling, only a change of the last tool's name is recorded. The slice card's row reads the latest of them.

**Constants and options.** The slow threshold is 30 seconds (`ToolCall` knows when it started and the live line already ticks every second), the same for Shell and MCP and for nothing else. `agentProgressSummaries` stays off: it costs model calls, and a row says the last tool's name instead of a model-written line.

**Testing seams.**
- Stories 1 to 5: `ChatConversationTests` and `EpicTranscriptAdapterTests` drive `chatFeed` and the group's title, summary, `doing` and chip kind through events; the chip and amber timer are `ToolGroup` and `ToolCall` values, so they are tested there and not through the view. The live line's drawing is covered by one golden in `CarrierTests` (as `CallLineTests` does for a call line).
- Stories 6, 9 and 11, the host side: `src/chat/claude.test.ts` replays a recording of a real conversation through the adapter with only `query` faked; a new recording with two subagents, one in the background past the turn's end, is the fixture for the adapter. `src/chat/sessions.test.ts` drives the state rule (working until the last task ends, sweep and archive refusals), and `src/chat/server.test.ts` the new request and its capability.
- Stories 7, 8, 10 and 12: `chatFeed` through `ChatConversationTests` with the new `chat-events-*.json` fixtures (`FixtureServer`), including a page that starts inside a subagent and a feed with no link events; the view and its header have goldens in `CarrierTests`, as `SessionHeaderTests` has for the epic's.
- Story 13: `LanesTests`, `SliceCardTests` and `EpicTranscriptAdapterTests` for the join and the last step; the engine's parser in `src/harnesses/claude.test.ts` against `claude-subagents.fixture.jsonl`, with a `task_progress` line added.
- The docs ship with the change: `docs/macos-ui.md` (cards in the feed), `docs/macos/sessions.md` and `CHANGELOG.md`, as the `macos-ui-change` skill asks.

## Out of scope

Writing to a subagent. The only route is indirect: the main agent's `SendMessage` tool reaches a subagent launched with a `name`, while it runs, if the main agent chooses to relay it and the tool is allowed in the chat host's configuration. That is a second version, as a message box in the subagent's view that sends to the main agent with the context, labelled as such.

The right panel, tabs, subagents in the sidebar and the hover peek. The Codex adapter, which emits no subagent events today. Shell and Monitor tasks, which also arrive as `task_*` events and are not subagents. Cost or token screens beyond what the row and the view's header show. A web UI. A backfill of sessions stored before this change.

## Open questions

The order of the SDK's events when a background subagent outlives the turn: whether its `task_notification` comes before or after the turn's `result`, and what the new turn that follows carries. The state rule above does not depend on it, but the adapter's recording does; it is captured first, from a real session, before the adapter is written.

Whether `stopTask` on a foreground subagent, one whose `Agent` call is blocking the turn, ends that call with a result the parent can read, or leaves the turn waiting. Settled by the same recording.
