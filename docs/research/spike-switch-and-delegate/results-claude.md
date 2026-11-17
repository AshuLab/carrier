# Spike A (Claude): permission modes, what each lets an agent do, and opening with a model

Run on 2026-11-16 with the user's own `claude` 2.1.325 and login, SDK 0.3.311 as installed in this worktree (not 0.3.325), model alias `haiku` (resolves to `claude-haiku-5-5`), in temporary folders under `/tmp` that the scripts removed.
35 real turns were used, which is the whole budget: A1 8, A2 20, A3 1, plan follow-ups 4 (`a4.ts`) and 2 (`a5.ts`).
No usage or rate limit was hit.
Scripts and raw per-run JSON are in `claude/` and `claude/raw/`; the toy MCP uses Carrier's own `startMcpServer`, `McpSessionRegistry` and `defineTool`, injected as an http server whose `Authorization` header is `Bearer ${CARRIER_MCP_TOKEN}`, the token only in the process environment (never printed or stored).

How it was done: a direct SDK `query` with the same options as `src/chat/claude.ts` (streaming input, `spawnClaudeCodeProcess` with a detached group, `pathToClaudeCodeExecutable`), a `canUseTool` that records every call (tool, input, title, `decisionReason`, `blockedPath`, suggestions) and then denies, and `settingSources` left at the SDK default.
Every conversation was closed with `query.close()` and `endGroup(pid)` of the PID the script captured.

Context that shapes every result: the user's own `~/.claude` settings (read as counts only) have 14 `deny` rules (`EnterPlanMode`, `ExitPlanMode`, `NotebookEdit`, `Agent(Plan)` and others, none about Bash, Write or MCP), no allow or ask rules, and hooks that only notify (`PermissionRequest`, `PreToolUse` on `Artifact`).
They load in every run, as they would in Carrier.
The plan file of plan mode lives under the user's Claude config folder.

## A1. One MCP tool asks while the other is pre-approved

Setup: `allowedTools: ['mcp__carrier-chat__ping_read']` only; `ping_act` (token has `read` and `act`) is not listed; prompt "Call ping_read, then call ping_act, then say what happened". In every run the model first called `ToolSearch` to load the two tools (MCP tools are deferred), then called them.

| Mode | callback for `ping_read` | callback for `ping_act` | `ping_act` executed (server log) | What the model said |
| --- | --- | --- | --- | --- |
| `default` | no (pre-approved, ran) | **yes** | no (denied by the probe) | read returned PONG; act was denied, did not retry |
| `acceptEdits` | no (ran) | **yes** | no | same as default |
| `plan` | **yes** (the allowed read also asked) | not reached: the model stopped after the read was denied | no | read denied; it did not call act because plan mode is read-only |
| `auto` | no | **no** | **yes** | both returned PONG |
| `dontAsk` | no (ran) | no, denied by the harness | no | read PONG; act denied "because Claude Code is running in don't ask mode" |

Plan follow-ups, because the plan row above hid the act tool:

| Plan variant | callback for `ping_read` | `ping_act` |
| --- | --- | --- |
| callback allows `ping_read`, denies the rest | yes, fired although `ping_read` is in `allowedTools`; allowing it let it run | the model refused by itself ("plan mode is on... can't confirm it's safe") and never called it: UNVERIFIED whether it would ask |
| `allowedTools: ['mcp__carrier-chat__*']`, callback denies all | yes, fired although the wildcard covers it | never called, same reason |

Controls (mode `default`):

| Control | `ping_read` | `ping_act` |
| --- | --- | --- |
| `allowedTools: ['mcp__carrier-chat__*']` | ran, no callback | ran, no callback (server log shows both executed): the wildcard approves both |
| project `.claude/settings.json` with `deny: [mcp__carrier-chat__ping_act]` plus the wildcard in `allowedTools` | ran | **removed from the model's tool list** (`init.tools` lists only `ping_read`; ToolSearch answered "No matching deferred tools found"); never called, never reached the callback |
| project settings with `ask: [mcp__carrier-chat__ping_read]` plus `allowedTools: [ping_read]` | **callback fired** (the ask rule beat the allow) | callback fired as in `default` |

What the callback carried for `ping_act`: `tool`, `input: {}`, `displayName: "Ping Act"`, `toolUseID`, and one suggestion `{type:'addRules', rules:[{toolName:'mcp__carrier-chat__ping_act'}], behavior:'allow', destination:'localSettings'}`.
`title`, `description`, `decisionReason` and `blockedPath` were absent for an MCP call, so the approval card has the tool name and the input to show and nothing else from the harness.
The suggestion's destination is `localSettings`, so Carrier's "Always allow" would write the folder's `.claude/settings.local.json`.
The SDK printed `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED` on every run that had `allowedTools` with a canUseTool, for the listed tool (the warning says the callback will not be invoked for it, which was true for `default`, `acceptEdits`, `auto` and `dontAsk`, and false for `plan`).

## A2. What each mode lets the agent do without asking

Four probes as separate turns of one fresh conversation per mode, the callback denying everything; prompts end with "Do nothing else, and if it is refused do not try another way". The outside folder was created beforehand under `/tmp`.
"Ran" means the tool result was ok with no callback; "asked" means `canUseTool` fired; "refused" means the harness denied with no callback.
The model chose the tool: it used `Write` in `default`, `acceptEdits` and `plan`, and `Bash` (redirect) in `auto` and `dontAsk`.

| Mode | (1) a.txt inside the folder | (2) b.txt in a new `/tmp` folder outside | (3) `curl -sI https://example.com \| head -1` | (4) `ls` |
| --- | --- | --- | --- | --- |
| `default` | asked (Write); file not created | asked (Write, reason "Path is outside allowed working directories"); not created | asked (Bash); not run | **ran** (output empty folder) |
| `acceptEdits` | **ran** (Write), file exists | asked (reason "outside allowed working directories"); not created | asked; not run | **ran** |
| `plan` | the only write the model tried was its plan file, which asked (reason: sensitive file, symlink outside the working directories); a.txt not created | not tried (the model said plan mode blocks files other than the plan file); a follow-up fresh conversation again asked only for the plan file; b.txt not created | **ran, no ask**, returned `HTTP/2 200` (repeated in a second conversation: same) | **ran** |
| `auto` | **ran** (Bash), file exists, content `hi` | **ran** (Bash), file exists in the outside folder, content `hi` | **ran**, `HTTP/2 200` | **ran** |
| `dontAsk` | refused (Bash denied "because Claude Code is running in don't ask mode"); not created | refused (Bash); not created | refused (Bash) | **ran** (read-only command allowed) |

Extra checks: in `dontAsk` an explicit `Write` of d.txt was refused with the same message and no callback, file not created; in `plan`, "run `touch c.txt`" produced only a plan-file write (asked, denied) and no Bash call, so whether a shell write runs in plan mode is UNVERIFIED (a shell network read did run).
Disk was checked for every file probe: only the `ran` rows created a file.
No callback ever carried a `title`; `decisionReason` appeared only for the outside-folder and plan-file cases.

## A3. Opening with a model (Carrier's real adapter, `src/chat/claude.ts`)

| Open with | open() to ready | Option `model` after open | How it behaves |
| --- | --- | --- | --- |
| `{model: 'haiku'}` | 567 ms | `current: haiku` | resolves to `claude-haiku-5-5`; no turn run |
| `{model: 'not-a-real-model-xyz'}` | 544 ms | `current: not-a-real-model-xyz`, and the id is appended to the list as its own value | **open succeeds**; fails on the first turn, 0.75 s after `send`: an `assistant` event with the text "There's an issue with the selected model (not-a-real-model-xyz). It may not exist or you may not have access to it.", then an `error` event with the same text, then `turn_end` outcome `error` with zero usage; the option still says the invalid id afterwards |
| nothing | 556 ms | `current: default` (resolves to `claude-sonnet-5-5`) | no turn run |

Models listed in all three (14): `default` (sonnet 5.5), `opus`, `sonnet`, `fable`, `haiku` (Opus 5.5, Sonnet 5.5, Fable 5.2, Haiku 5.5), and nine pinned ids (`claude-fable-5-1`, `claude-haiku-4-5-20251001`, `claude-sonnet-5`, `claude-opus-5`, `claude-fable-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-sonnet-4-6`).
The listing does not depend on the model asked for, and a model that is not in it does not stop `open`.
The three opens needed no turn, so the "ready" times include no model call.

## Raw observations worth keeping

- Modes were set as the start option `permissionMode`, as Carrier does; the init message echoed it back for each (`init.permissionMode`).
- `auto` was available on this account and model (`haiku`); `ping_act` ran with no callback and no classifier prompt. The classifier's reason is not exposed.
- `dontAsk`: a call that no allow rule approves is denied with text that tells the model it may try other tools; the model did not.
- In `plan`, the model told the user it was blocked by plan mode on its own before calling `ping_act`; with the callback denying `ping_read`, it also cited that denial.
- The wildcard `mcp__carrier-chat__*` approved `ping_act` with no callback in `default`.
- A deny rule from the person's project settings makes a tool vanish from the model's list even when `allowedTools` names it by wildcard.
- The callback never fired for `ls` in `default`: Claude Code lets read-only shell commands run without asking.

## UNVERIFIED

- Whether `ping_act` reaches the callback in `plan` mode (the model never called it); only the read was seen asking.
- Whether `auto` would also run `ping_act` when its input or description looks risky or destructive; the classifier decided on a harmless fixed-string tool, and a `destructiveHint` annotation was not tried.
- Whether a shell write (`touch`, redirect) runs in `plan` mode; only `curl` was seen running.
- `Write` and `Edit` in `auto` (the model used Bash), and `Bash` writes in `acceptEdits`.
- Behaviour with SDK 0.3.325 (0.3.311 was installed; the binary was 2.1.325).
- Other models or accounts: everything ran on `haiku` only; `auto` might be unavailable elsewhere.
- Settings sources other than a project `.claude/settings.json` (user, local, managed) and hooks that deny.
- What "Always allow" (the `localSettings` suggestion) does on the next call; it was not accepted.
- `_meta["anthropic/requiresUserInteraction"]` on an MCP tool, which the research says forces an ask (not tried).
- Opening with a model that exists but the account cannot use (only a non-existent id was tried), and `setOption('model')` with an invalid id after open (the adapter refuses ids not in its list, from reading the code, not run).
