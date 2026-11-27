# Failed chat subagents: what `task_notification` carries, recorded for real

> Spike of 2026-11-26 for ticket #1552 of epic #1551 ("Subagents have a place of their own in the window header").
> Question: what does the provider's end notification of a subagent that failed carry in its `summary`, does the subagent's own last erroring tool result say the cause better, and what should the failed subagent's block show?
> The recording is [chat-spike/claude-subagent-failed.fixture.jsonl](chat-spike/claude-subagent-failed.fixture.jsonl).
> Line numbers below are lines of that file.

## Short answer

- **Yes, a `failed` `task_notification` carries a non-empty `summary`.**
  It carries the full termination reason from the provider (`"Agent terminated early due to an API error: ... (error type ..., HTTP ..., request id ..., model sent to the API: ...)"`), and it has no `usage` field.
- **No, the failed subagent's own last erroring tool result does not say the cause better.**
  When the subagent fails on an API or model error, it has no tool calls or tool results of its own; its only inner message is a synthetic `assistant` error (`model: "<synthetic>"`, `is_api_error_message: true`) whose text omits the error type, HTTP status, and request id that `summary` includes.
  Meanwhile, ordinary tool errors inside a subagent (such as a failing `Bash` command or a `canUseTool` error) return to the subagent's model and end the task with `status: "completed"`, and a `canUseTool` denial with `interrupt: true` ends it with `status: "stopped"`, not `status: "failed"`.
- **What the failed subagent's block should show:** show the notification's `summary` when it is present and non-empty (redacted and bounded as the main agent's messages are), and show `"Failed"` alone only when `summary` is absent or empty.
  This confirms the design already written in [the spec](../specs/subagents-in-the-header.md) under "What a subagent returned" and requires no fallback to a tool result.

## What was run

- Machine: macOS arm64, Node 26, using the user's own Claude login (`claude auth status` reported `loggedIn: true`, `authMethod: claude.ai`).
  No token was read, stored, or printed.
- `@anthropic-ai/claude-agent-sdk` 0.3.326 against `claude` 2.1.332, main model `haiku`, in a throwaway `CARRIER_HOME` and an empty scratch folder with two files (`a.txt` and `b.txt`) and a custom subagent definition `.claude/agents/bad-model.md` pinned to `model: claude-nonexistent-model-999`.
- Driven through `startChatHost` (`src/chat/host.ts`) and `claudeChatRunner` (`src/chat/claude.ts`) over the host's control socket, with `realClaudeDeps.query` wrapped to write every raw SDK line and host marker to JSONL before `claudeChatRunner` translated it.
- Other ways tried to provoke `status: "failed"` (not kept in the fixture except the `Fail and interrupt` turn):
  1. Custom agent with `maxTurns: 1` asked to run two sequential `Bash` commands: ended with `status: "completed"` and `summary: "NOTE: this agent stopped at its 1-turn limit before finishing. It was still calling tools and had produced no report.\n"`.
  2. Subagent running a failing `Bash` command (`ls /nonexistent_path_xyz`) followed by a throwing `canUseTool` callback (`Error`): both `is_error: true` tool results returned to the subagent model, and the subagent ended with `status: "completed"`.
  3. Subagent running a failing `Bash` command (`ls /nonexistent_spike_path_12345`) followed by `canUseTool` returning `{ behavior: 'deny', ..., interrupt: true }` (recorded as turn 3 of the fixture, lines 160–259): ended with `status: "stopped"` and `summary: "Fail and interrupt"` (only the title, line 205), just like `stopTask`.
- Scrubbed in the fixture: the scratch folder path became `/work`, `/private/tmp/claude-501/...` became `/tmp/claude-1000/-work`, the user's home directory became `/home/user`, and the messaging socket path became `/tmp/cc-socks/1000.sock`.
  `grep -inE 'vemec|ghersidl|/Users/|var/folders|claude-501|ghp_|gho_|github_pat_|sk-ant|Bearer|AKIA|access_token|refresh_token|id_token'` matches nothing in the fixture.

## What the `failed` end notification carries

### Foreground failure (lines 29–34)

```json
{"type":"system","subtype":"task_notification","task_id":"aa2d1ba2090957dad","run_id":"0mwy1211l-31e48e64","tool_use_id":"toolu_017qmz1NKiPtkgs2B9gPHTMW","status":"failed","output_file":"/tmp/claude-1000/-work/73fc4832-6ceb-42f5-9b27-e4fe17f28d1b/tasks/aa2d1ba2090957dad.output","summary":"Agent terminated early due to an API error: There's an issue with the selected model (claude-nonexistent-model-999). It may not exist or you may not have access to it. (error type model_not_found, HTTP 404, request id req_011ChSCb8oh1qGW6piwzvDs6, model sent to the API: claude-nonexistent-model-999)","uuid":"6a595f1e-e5b7-4d7a-abd1-cfa56f46b760","session_id":"73fc4832-6ceb-42f5-9b27-e4fe17f28d1b"}
```

What arrives around it:

- Line 29: `task_started` (`task_type: "local_agent"`, `is_backgrounded: false`).
- Line 30: the subagent's `user` brief (`parent_tool_use_id: "toolu_017qmz1NKiPtkgs2B9gPHTMW"`).
- Line 31: a synthetic `assistant` error inside the subagent (`model: "<synthetic>"`, `is_api_error_message: true`, `error: "model_not_found"`, `api_error_type: "not_found_error"`, `parent_tool_use_id: "toolu_017qmz1NKiPtkgs2B9gPHTMW"`) whose text is `"There's an issue with the selected model (claude-nonexistent-model-999). It may not exist or you may not have access to it."`.
- Line 32: `task_updated` with `patch: { status: "failed", end_time: 1795726270107, error: "Agent terminated early due to an API error: ..." }`.
- Line 33: `task_notification` with `status: "failed"`, no `usage`, and `summary` equal to `patch.error`.
- Line 34: the parent's `Agent` `tool_result` (`is_error: true`, `parent_tool_use_id: null`) carrying the exact same string as `summary`.

### Background failure (lines 111–159)

```json
{"type":"system","subtype":"task_notification","task_id":"ab7643d6f2e7f9470","run_id":"0mwy124ze-a8b0b088","tool_use_id":"toolu_01ERbSubzKj4aFntvqexNotn","status":"failed","output_file":"/tmp/claude-1000/-work/73fc4832-6ceb-42f5-9b27-e4fe17f28d1b/tasks/ab7643d6f2e7f9470.output","summary":"Agent terminated early due to an API error: There's an issue with the selected model (claude-nonexistent-model-999). It may not exist or you may not have access to it. (error type model_not_found, HTTP 404, request id req_011ChSCbVLy6Nky2c2MPngcZ, model sent to the API: claude-nonexistent-model-999)","uuid":"6e414a40-8b50-4908-858b-fd36793536d5","session_id":"73fc4832-6ceb-42f5-9b27-e4fe17f28d1b"}
```

- The notification carries the same `summary` shape and also has no `usage` field (line 116).
- Because the parent's `Agent` call already received `"Async agent launched successfully..."` (line 112), the notification is what delivers the failure to the parent, and the SDK opens a follow-up turn (`system/init` at line 135 through `result` at line 159 with `origin: { kind: "task-notification", producer: "session-task", runId: "0mwy124ze-a8b0b088" }`) for the parent to reply.

### Tool error followed by `interrupt: true` (lines 192–206)

- The subagent ran `ls /nonexistent_spike_path_12345` and received `is_error: true` (`"Exit code 1\nls: /nonexistent_spike_path_12345: No such file or directory"`, line 198).
- Its second tool call (`touch denied_after_fail.txt`) was denied by `canUseTool` with `interrupt: true`, which produced `task_notification` with `status: "stopped"` and `summary: "Fail and interrupt"` (only the title, line 205), not `status: "failed"`.

## What the failed subagent's block should show

- Read `summary` from `task_notification` for `failed` just as for `completed`, redact and bound it in `boundEvent`, and store it on the `task` event.
- Because `usage` is absent on a `failed` notification, the adapter must continue treating `usage` fields as optional on `task` events (which `claude.ts` already does).
- In the subagent view, show that `summary` in the failed subagent's block when the provider sent a non-empty one, and fall back to `"Failed"` alone when `summary` is absent or empty.
- Do not pull from the subagent's last erroring tool result: an agent-level failure has no tool error of its own, and an earlier tool error does not cause `status: "failed"`.
