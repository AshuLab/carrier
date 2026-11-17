# What the spike found about switching and delegating between agents

> Research of 2026-11-16, for [switch-and-delegate-between-agents](../specs/switch-and-delegate-between-agents.md).
> The scripts, the raw output and one results file per part are in [spike-switch-and-delegate](spike-switch-and-delegate/README.md).
> Versions: Claude Code 2.1.325 with the SDK pinned at 0.3.311, and Codex 0.167.2.

## Short answer

A handoff kept a Claude conversation going: the new conversation answered 6 of 6 questions about the earlier one and none without it.
The handoff belongs in the instructions the conversation opens with, not in front of the person's first message.
Both harnesses can ask the person about one tool of a server while the others stay pre-approved, but each has a catch: Claude's `auto` mode runs the tool unasked and its `plan` mode asks for every tool, and Codex offers "allow for the session" only for a tool in its `auto` mode.
The levels of the permission scale do not mean the same on the two harnesses, so the scale changed.
Both adapters can tell a usage limit from a retried rate limit by a structured field, and neither does today.
Everything that needs a real Codex model is not checked, because the account is at its usage limit until 2026-11-20 at 7:11 PM.

## How each result was obtained

| Part | What ran | What it is evidence of |
| --- | --- | --- |
| A, Claude | The real SDK and the real `claude`, model `haiku`, 35 turns in temporary folders, with a probe that recorded and denied every approval. | How Claude's modes treat one tool of an MCP server and what each mode allows. |
| B, Codex | The real `codex app-server` with a scripted fake of the Responses API, so the model only did what a script said. Two real turns for the model list and the limit. | How Codex's approvals, elicitations, sandbox and config behave. Nothing about how a real Codex model reacts. |
| C, handoff | Real Claude for the seed and the receiver, a toy `history` tool through Carrier's own MCP server, 31 answered turns. Codex was not run. | Claude to Claude only; the two directions between the harnesses are not checked. |
| D, limits | Reading of the SDK's types and Codex's generated schema, the engine's fixtures, and a replay through the adapters with a fake transport. | What the adapters see today and what they could classify on. |

## One tool asks while the others are pre-approved

Claude, with `allowedTools` naming only the read tool and a callback that denies:

| Mode | The tool left out of `allowedTools` |
| --- | --- |
| `default`, `acceptEdits` | Asks, through the callback, with the tool's name, input and display name and no title or description. |
| `plan` | Everything asks, the pre-approved read included, and the model refused to call the other one. |
| `auto` | Ran with no question. |
| `dontAsk` | Denied by the harness before any callback. |

With the wildcard `mcp__carrier-chat__*` both tools are approved with no callback.
A project's deny rule for the tool removes it from the model's list even with the wildcard, and a project's ask rule for the read tool beats `allowedTools`.
The one suggestion the callback carries writes an allow rule to the project's local settings, which outlives the session.

Codex, with the scripted model:

| Setup | Result |
| --- | --- |
| Server default `approve` plus `approval_mode = "prompt"` on one tool | Only that tool asks, under `untrusted` and `on-request`. Under `never` there is no question: the tool fails with `MCP tool call requires approval, but approval policy is never`, and a server default of `approve` still runs everything. |
| Both tools in `prompt` | Both ask. |
| One tool left in `auto` mode, the others `approve` | That tool asks, and its request offers `persist: ["session", "always"]`. Accepting with `persist: "session"` allows that tool for the thread. |

The elicitation carries `_meta.tool_name`, `_meta.tool_params` and a message that names the tool, and only an explicit `prompt` leaves out the persistence offer.
Accept runs the call, decline fails it with `user rejected MCP tool call`, cancel with `user cancelled MCP tool call`, and the model sees that text.
The `config` of `thread/start` merges with the person's own MCP servers and is per thread; per-tool config given at `thread/resume` applies in a fresh process and not on a thread already running.

## What each level lets an agent do without asking

| | Write inside the folder | Write outside it | Network | `ls` |
| --- | --- | --- | --- | --- |
| Claude `dontAsk` | refused | refused | refused | runs |
| Claude `default` | asks | asks | asks | runs |
| Claude `acceptEdits` | runs | asks | asks | runs |
| Claude `plan` | asks, only the plan file was attempted | not attempted | runs | runs |
| Claude `auto` | runs | runs | runs | runs |
| Codex `read-only` | refused | refused | blocked | runs |
| Codex `workspace-write` with `untrusted` | asks for everything, `ls` included | | | |
| Codex `workspace-write` with `on-request` or `never` | runs | `/tmp` runs, `/var/tmp` refused | blocked | runs |

Codex blocks the network in every cell, and its `workspace-write` also writes under `/tmp`.
Claude's `auto` reaches the network and writes anywhere, and its `plan` mode ran `curl` unasked.
`on-request` and `never` behaved the same in every probe, because no probe tried to leave the sandbox.

## The handoff

- The seed was 8 turns and 43,180 bytes, with four pasted specs of about 10 KB; the handoff held 9 of its messages in 16,000 bytes and the whole text sent was 16,860, because the frame and the pointer to `history` add about 860.
- Handed to a new Claude conversation with the `history` tool, it answered 3 of 3 questions whose answer was in the handoff and 3 of 3 whose answer was only in what it left out, with no invented answer, in two runs that asked in different orders.
  The first omitted question made the agent page the earlier conversation, 3 to 5 `history` calls, and the next ones cost nothing.
  The first use of the tool costs one more call, because Claude loads an MCP tool through `ToolSearch` first.
- Without a handoff and without the tool the same six questions got 0 of 6 and no invented answer.
- With the first message a command (`/pong ALPHA`, a skill):

| Where the handoff sat | The command ran as a command | The handoff arrived | Turns |
| --- | --- | --- | --- |
| In front of the command, in the same message | No: the reply was right, but the model called the skill itself | Yes | 1 |
| A turn of its own before the command | Yes | Yes | 2 |
| In the SDK's `systemPrompt` with `append`, when the conversation opens | Yes | Yes | 1 |

- Codex's app-server accepts `developerInstructions` in `thread/start` and `thread/resume`, and `turn/start` has no instruction field.
  Whether a Codex model reads them was not checked.
- The SDK says it records the rendered system prompt with the conversation and reuses it on `resume` ignoring a different `append`; whether a resume keeps the handoff was not checked.

## The usage limit

| | Signal | The reset time |
| --- | --- | --- |
| Claude | The failed `result` with `is_error`, status 429 and `api_error: "usage_limit_reached"`, which the engine's real fixture holds. The field is marked internal and is not in the SDK's types; the SDK exports `USAGE_LIMIT_ERROR_PREFIXES` for a text match. | Text on the `result` (`resets 12:40pm`), a timestamp on `rate_limit_event` and on the synthetic assistant message. |
| Codex | `codexErrorInfo: "usageLimitExceeded"` on the `error` notification, with `willRetry: false`, and on the failed turn. A retried rate limit has `willRetry: true`. This was captured for real. | Not in the error. `account/rateLimits/read` gives `resetsAt` in epoch seconds, and `src/usage` already reads it. |

Neither chat adapter reads these fields: a usage limit and a rate limit come out as the same `error` with text and a `turn_end` with outcome `error`.
The real Codex text starts with a curly apostrophe, `You’ve hit your usage limit`, while the engine's matcher and its `codex exec` fixture have a straight one, so a text match for the app-server has to take both, and the structured field is the better key.
The free-plan text is `Upgrade to Plus to continue using Codex (…), or try again at Nov 20th, 2026 7:11 PM`.
`rateLimitReachedType` is `rate_limit_reached` for a quota that is used up, so that name does not separate a usage limit from a transient rate limit.

## Models

Opening a conversation with an invalid model id does not fail on either harness: Claude adds it to the option list and Codex accepts it at `thread/start`, and both fail on the first turn, Claude in about 0.75 seconds with an error and zero usage and Codex with `modelNotFound`.
Opening reaches ready in about 0.55 seconds on Claude with 14 models listed, and Codex's `model/list` answers in about 2 ms.
Codex lists `gpt-6-luna`, `gpt-5.6-terra` and `gpt-5.6-luna` with no price, so which is the cheapest is not known.

## What changed in the records because of this

- 0032: the handoff travels in the instructions of the new conversation, its 16,000 bytes count the whole text, an agent with an unlisted model is refused at the switch, and the usage-limit signals are named.
- 0033: the scale has three levels and `plan`, `auto` and Codex's `never` are off it, the allowance for the session comes from a tool left in `auto` mode on Codex and from an update with the destination `session` on Claude, `plan` gets no `act`, and the status is accepted.
- The brief: the same changes, and the open questions that these results answered are gone.

## Not verified

- Any real Codex model turn: whether it calls `history`, whether it reads `developerInstructions`, how it reacts to a refused tool, and the two directions of the handoff between the harnesses.
- Whether a resume of a Claude conversation keeps the appended system prompt, and whether Codex keeps `developerInstructions` on resume.
- `persist: "always"` on Codex, which would write the person's config, and whether the Claude CLI honours an update with the destination `session`, which the SDK's types allow.
- Whether `ping_act` asks in Claude's `plan` mode, because the model refused to call it, and a risky tool in `auto`.
- The real order of `rate_limit_event`, the synthetic message and the `result` on a live Claude limit, and the text of the limit in `codex exec --json` on a current Codex.
- SDK 0.3.326 and Codex 0.169.0, the latest releases on 2026-11-17, whose release notes change none of what these results rest on; everything above ran on 0.3.311 and 0.167.2.
