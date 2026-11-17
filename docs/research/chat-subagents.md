# Chat sessions with subagents: what the SDK sends, recorded for real

> Spike of 2026-11-17 for ticket #1041 of epic #1025 ("The chat shows what the agent waits on and what its subagents do").
> Question: the epic left two things open, the order of a background subagent's `task_notification` and the turn's `result`, and what the parent's blocked `Agent` call gets when `stopTask` ends a foreground subagent.
> The recording is [chat-spike/claude-subagents.fixture.jsonl](chat-spike/claude-subagents.fixture.jsonl), replayed by `src/chat/claude.test.ts`.
> Line numbers below are lines of that file.

## Short answer

- A background subagent that outlives the turn: the turn's `result` comes first (line 222), the subagent's `task_notification` after it (line 228), and then the SDK opens a turn of its own with no message from the person: `system/init` (230) up to a second `result` (275).
  That `result` says why it exists: `origin: {kind: "task-notification", producer: "session-task", runId}` where `runId` is the subagent's `run_id`.
  The turn is not an error and it must not be lost: the host drops its `turn_end` today.
- `stopTask` on a foreground subagent: the row ends on a `task_notification` with `status: "stopped"` (312) and the parent's blocked `Agent` call ends at once with an error `tool_result`, `[Request interrupted by user for tool use]` (316).
  The turn does not hang: the parent model reads that, answers, and the turn ends with a normal `result` (350).
- Neither answer breaks the epic's session state rule.
  Both ask for changes to its Decisions, listed per answer below, together with three things the recording showed that the epic did not ask about.

## What was run

- Machine: macOS arm64, Node 26, the user's own Claude login (`claude auth status`: `loggedIn: true`, `authMethod: claude.ai`).
  No token was read, stored or printed.
- `@anthropic-ai/claude-agent-sdk` 0.3.311 (the repo's pinned version) against the user's `claude` 2.1.326, model `haiku`, in an empty scratch folder with two files.
- The driver was a throwaway script of about 60 lines, not kept (as for the [chat spike](chat-spike.md)): `query()` with streaming input, the same options the adapter passes (`includePartialMessages: true`, `extraArgs: {'thinking-display': 'summarized'}`), a `canUseTool` that allows and writes a host line, and one `for await` that writes every message as a line.
  `stopTask` was called by the script 10 s after the foreground subagent started.
- Part 1 of the file is one process with three turns:
  1. One message asking for three subagents in one reply: "Count files" (foreground), "Slow check" (`run_in_background: true`, a 45-second command) and "Delegator" (foreground, which itself launches "Say hi").
  2. No message from the person: the turn the SDK opened when "Slow check" ended.
  3. One message asking for a foreground subagent "Long wait" (a 100-second command), which `stopTask` ends after 10 s.
- Part 2 is a second process with `forwardSubagentText: true` (the adapter does not set it today) and one turn: "Delegator" launching "List files", which runs `ls`.
- Two things in the prompts are the recording's, not the SDK's: `sleep` on its own is blocked by Claude Code's Bash tool ("Blocked: standalone sleep 120"), so the slow commands are `node -e "setTimeout(...)"`; and the model chose to launch the three subagents in one reply when asked (lines 65, 87, 111).
- Scrubbed: `/Users/<name>/.claude-<account>` became `/home/user/.claude`, the scratch folder became `/work` (the same cwd as the chat-spike fixtures), `/private/tmp/claude-501/-private-tmp-rec-cwd-…-work` became `/tmp/claude-1000/-work`.
  Those are plain string replacements over the whole file, so every line is still the JSON the SDK sent and ids, order and shapes are untouched.
  `grep -E 'ghp_|sk-ant|/Users/'` finds nothing, and the same search for the user's name, e-mail and organisation finds nothing either.
  Left as the SDK sent them: session ids, the `system/init` lists (skills, plugins, models, as in the other fixtures) and the opaque `signature` of thinking blocks.
- Not tried: a subagent stopped after the turn ended (a background one), `stopTask` on a nested subagent, two background subagents ending in the same turn, a subagent that fails, an approval asked by a subagent that the person answers late.

## Question 1: a background subagent that ends after the turn

What arrives, in order (all in part 1):

| Line | Message | |
|---|---|---|
| 91 | `task_started` "Slow check", `is_backgrounded: true`, `spawn_depth: 1`, `task_type: "local_agent"` | launched at the start of turn 1 |
| 93 | `user` `tool_result`: "Async agent launched successfully. … The agent is working in the background. You will be notified automatically when it completes." | the parent's `Agent` call is answered at once |
| 222 | `result` `success`, `num_turns: 4`, `subagent_stats.completed: 3` | **the turn ends with the subagent still running** |
| 223 | `task_notification` `status: "completed"` of the subagent's own Bash task (`task_type: "local_bash"`) | after the `result` |
| 224, 225 | `user` `tool_result` "slow-done" and `assistant` text, both with `parent_tool_use_id` of the Agent call | the subagent keeps talking after the `result` |
| 227 | `task_updated` `patch: {status: "completed", …}` | |
| 228 | `task_notification` `status: "completed"`, `summary_is_report: true`, `usage.duration_ms: 49480` | the subagent's end, **after** the `result` |
| 229 | `background_tasks_changed` `tasks: []` | |
| 230, 231 | `system/init`, then `system/status` `requesting` | a new turn starts |
| 271 | `assistant` text: "The Slow check finished and printed `slow-done`." | the parent's reply to the notification |
| 275 | `result` `success`, `num_turns: 1` | the new turn ends |

The turn that follows carries:

- **No `user` message.**
  Nothing in the stream carries the notification as input to the model: the person's message is not repeated and no `user` line announces the task.
  The only text of the notification is the `summary` of line 228.
- **A fresh `system/init`** (230), the same as the start of every turn ([chat-spike](chat-spike.md)), then ordinary `stream_event`, `thinking_tokens` and `assistant` lines for the parent's reply.
  The session id is the same.
- **A `result` that names its cause** (275): `"origin":{"kind":"task-notification","producer":"session-task","runId":"0mwklt92q-6658c1dc"}`, with `result_index: 1` and `queued_turn_count: 0`.
  The `runId` equals the `run_id` of "Slow check" in lines 90 and 91.
  The `result` of a turn the person started has no `origin` (222).
- **Its own usage**: `num_turns: 1`, `total_cost_usd` cumulative for the query, `subagent_stats.completed: 4`.

What this did to the code before the host handled it (the test in `claude.test.ts` replays exactly this):

- The adapter had no notion of a turn it did not start: `turning` was false when line 230 arrives, the reply was emitted as ordinary `assistant` events and line 275 gave a `turn_end` with `outcome: 'ok'`.
- The host dropped that `turn_end`: `onEvent` in `src/chat/sessions.ts` returns on `turn_end` when `live.turn === undefined` ("a turn already recorded").
  So the follow-up turn's usage was never stored in `chat_turns`, and the session was `idle` the whole time it ran.
- Lines 224 and 225, which arrive after the `result`, are a subagent's `tool_result` and text; they would be stored as the main agent's without the `parent_tool_use_id` read.
- Now: the adapter emits `turn_start` at line 230 and the host opens the turn and keeps the session `working` until line 275's `turn_end`; when the last task ends the host waits `FOLLOW_UP_MS` for it before it goes idle.

Does it change the epic's Decisions?
Yes, one change to make (not made here):

- **Session state.**
  The rule "set `working` on a `task` start, back to `idle` only when the turn has ended and the set of running tasks is empty" is right for the end of the first turn and wrong one step later: when the last task ends after the `result`, the SDK is about to run a turn (230 comes right behind 228 and 229), so going to `idle` at 228 would flicker and the reply would run with the session shown idle.
  The rule should read: a task that ends after the turn's `result` is followed by a turn of the SDK's own, so the session stays `working` until that turn's `turn_end`.
  To know it, the adapter treats a `system/init` that arrives while `turning` is false as the start of such a turn (it sets `turning`), and the host has to stop dropping that `turn_end` (`live.turn` must exist for it, or the check must not apply to it).
  The `origin.kind === "task-notification"` of the `result` can be copied into the `turn_end` for the app to say why, but the start is `system/init`, not the `result`.
  One case is not recorded: a background subagent that is stopped after the turn ended.
  If the SDK opens no turn for it, the host would wait for a `turn_end` that never comes, so the rule needs a way out (idle when the set is empty and no `system/init` arrives within a few seconds) until that is tried.
- Everything else in the Decisions holds for this answer: the order does not change how `task` events are stored or joined by `callId`, and `ChatEvent` needs nothing new for it.

## Question 2: `stopTask` on a foreground subagent

Part 1, third turn.
"Long wait" is a foreground subagent: its `Agent` call blocks the parent (line 299), it is not backgrounded (`is_backgrounded: false`, line 301), and it is running a 100-second Bash command (309).
The script called `stopTask` with the subagent's `task_id` 10 s in:

```
310 {"host":"stopTask_called","taskId":"af0d8b127fea03930"}
311 {"type":"system","subtype":"task_updated","task_id":"af0d8b127fea03930",…,"patch":{"status":"killed","end_time":1794914667509},…}
312 {"type":"system","subtype":"task_notification","task_id":"af0d8b127fea03930",…,"tool_use_id":"toolu_01LfpGpsC55uPcp3MTLtLGwE","status":"stopped",…,"summary":"Long wait",…}
313 {"host":"stopTask_result","value":"resolved"}
314 {"type":"system","subtype":"task_notification","task_id":"bmqm2y7lu",…,"status":"stopped","output_file":"","summary":"Run 100-second delayed node script in foreground",…}
315 {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"The user doesn't want to proceed with this tool use. The tool use was rejected … STOP what you are doing and wait for the user to tell you how to proceed.","is_error":true,"tool_use_id":"toolu_01VkyH5M4JLghcjAUAQeVhdW"}]},"parent_tool_use_id":"toolu_01LfpGpsC55uPcp3MTLtLGwE",…}
316 {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"[Request interrupted by user for tool use]","is_error":true,"tool_use_id":"toolu_01LfpGpsC55uPcp3MTLtLGwE"}]},"parent_tool_use_id":null,…,"tool_use_result":"Error: [Request interrupted by user for tool use]","tool_result_meta":[{"id":"toolu_01LfpGpsC55uPcp3MTLtLGwE","non_execution_kind":"interrupted",…}]}
346 {"type":"assistant","message":{…"content":[{"type":"text","text":"The \"Long wait\" subagent was interrupted before it finished, so I don't have a `long-done` result or a DONE reply. Do you want me to launch it again?"}]…}
350 {"duration_api_ms":21649,"stop_reason":"end_turn",…,"subagent_stats":{…,"killed":{"parent":0,"user":1,"system":0},…},"is_error":false,…,"terminal_reason":"completed",…}
```

So:

- **The parent's blocked `Agent` call receives an error result** (316): `is_error: true`, text `[Request interrupted by user for tool use]`, and `tool_result_meta[0].non_execution_kind: "interrupted"`.
  It is a `tool_result` of the main thread (`parent_tool_use_id: null`) for the call id the `task_started` carried as `tool_use_id`.
- **The turn is not left waiting.**
  The parent model sees that result, writes a reply (346: it says the subagent was interrupted and asks whether to launch it again) and the turn ends with a normal `result`: `is_error: false`, `terminal_reason: "completed"` (350).
  Stopping a subagent is not an interrupt of the turn.
- **The row ends on the notification, not on the call.**
  `task_notification` with `status: "stopped"` (312) comes before the call's error result (316), and `task_updated` says `killed` (311).
  `stopTask` resolved between the two (313), so the promise is not what ends the row.
- **The subagent's own Bash task ends too** with its own `stopped` notification (314, `task_type: "local_bash"`, `parent_task_id` of the subagent), and the subagent's pending Bash call gets a "rejected" `tool_result` (315) as if the person had denied it: a subagent's stop reads, inside its transcript, like a denial.
- `subagent_stats.killed.user` goes from 0 to 1 on the `result`.

What the adapter does with it today: line 316 becomes a `tool_end` for the `Agent` call with `status: 'err'` and `output: ['[Request interrupted by user for tool use]']`; the test asserts it.

Does it change the epic's Decisions?
No, it confirms them:

- "A `task_notification` with status `stopped` is what ends the row" is exactly what the stream does, and it arrives before the parent's call ends.
- "The message box's Stop sends it for each running subagent after the interrupt" has no trap in it for a foreground subagent: the parent is not left blocked.
- The app can rely on the parent's `Agent` call ending as `err` with that text; it should not read the text to know why, since the `task` event with `state: 'stopped'` already says.

## Other things the recording showed

Each of these changes a Decision or its wording; the changes are to make, not made here.

1. **A foreground subagent's text and thoughts do not arrive unless `forwardSubagentText` is on.**
   Part 1 (the adapter's options as they are): "Count files" gives the parent stream one `assistant` line, its Bash `tool_use` (118), and the `tool_result`s; the `Delegator` one gives its `Agent` call.
   Its thinking and its final text never arrive.
   The one that ran in the background gives everything: thinking (119), calls and the final text (225).
   Part 2 (`forwardSubagentText: true`): a subagent's `user` brief, thinking, calls and text all arrive with `parent_tool_use_id` and `agent_id`, the nested one included (lines 392 to 408).
   Change to make: the Decisions' "Constants and options" add `forwardSubagentText: true` to the options the adapter passes.
   Without it a subagent's view has calls and nothing else, and the epic's story 8 ("its call groups, thoughts and messages") cannot be met.
2. **A subagent's partial text never arrives, so the epic's "streamed text goes into the main agent's message" does not happen on this version.**
   In both parts, 263 `stream_event` lines, none with a `parent_tool_use_id` and every `message_start` id is the id of a main-thread `assistant` message (none is a subagent's), with `forwardSubagentText` on or off.
   Change to make: none to the code the Decisions describe ("a partial text of a subagent is dropped, not tagged") since there is nothing to drop; the Problem's claim should be corrected to say that the wrong attribution is of the finished blocks (`assistant`, thinking, `tool_use`, `tool_result`), and a stream event with a `parent_tool_use_id` should still be dropped by the adapter in case a version sends one.
3. **`task_*` events are also sent for a subagent's Bash commands.**
   Lines 140 and 309 are `task_started` with `task_type: "local_bash"`, `owned_by_subagent: true` and the subagent as `parent_task_id`, for a foreground command, not only a background one.
   Their `task_notification` has `output_file: ""` (223, 314).
   Change to make: the Decision for the `task` event says it is read from `task_started`, `task_progress` and `task_notification`; it must add that only `task_type: "local_agent"` is a subagent, or each Bash call of a subagent becomes a row (the epic already leaves Shell and Monitor tasks out of scope).

What the recording confirms and the Decisions need no change for:

- `task_started` carries `tool_use_id` (the launching `Agent` call), `description`, `subagent_type`, `is_backgrounded`, `spawn_depth` and `prompt` (68, 91, 113), so the join by `callId` works and the brief is available without a `user` line.
- A nested subagent has `parent_task_id` of the launching subagent's `task_id` (126: "Say hi" under "Delegator", `spawn_depth: 2`), which is what the map from task ids to launching calls needs.
  Its own calls (line 400: the `Bash` call of "List files") carry `parent_tool_use_id` of its own launching call, so `parentCallId` of an event is the SDK's field as it is; the map is needed for `task` events only.
- Three subagents launched in one reply start one after the other with their own `task_id` (68, 91, 113) and all three notifications arrive on their own (135, 132, 228), foreground ones before the parent's `tool_result` for their call (132 before 133, 135 before 136).
- `task_progress` has `last_tool_name` and `usage` for the row's step and count: `{"subtype":"task_progress","task_id":"aea1aa9de8a2c258e",…,"description":"Running List entries in current working directory",…,"usage":{"total_tokens":15111,"tool_uses":1,…},"last_tool_name":"Bash"}` (117).
  A nested subagent's progress is sent too (124: "Say hi", `last_tool_name: "Agent"`).
- `taskId` is what `stopTask` took (310) and the one `task_notification` ends (312).
- Foreground subagents also end with `task_notification` `completed` (132, 135), not only background ones.
