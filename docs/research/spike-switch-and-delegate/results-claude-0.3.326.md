# Spike A (Claude) rerun on SDK 0.3.326

Rerun on 2026-11-17 of the Claude scripts of [results-claude.md](./results-claude.md), with the SDK at 0.3.326 and the user's own `claude` 2.1.326 (the first run: SDK 0.3.311, `claude` 2.1.325), model alias `haiku`, same scripts (`claude/a1.ts`, `a2.ts`, `a3.ts`) and the same user settings.
The raw per-run JSON in `claude/raw/` is now the rerun's; the first run's are in git history.
`a4.ts` and `a5.ts` (the plan-mode follow-ups) were not rerun: those rows are UNVERIFIED on 0.3.326.
The first attempt of A2 hit the 5-hour usage limit mid-way and was discarded; it was run again whole once the limit had reset.
Verdict per item: **held** means the same observable result as in results-claude.md, **changed** says what differs.

## A1. A tool left out of `allowedTools`, in each mode

| Mode | Verdict | Observed on 0.3.326 |
| --- | --- | --- |
| `default` | held | `ping_read` ran with no callback; `ping_act` reached the callback and was not executed |
| `acceptEdits` | held | same as `default` |
| `plan` | held | `ping_read` (in `allowedTools`) still reached the callback; the model did not call `ping_act` |
| `auto` | held | both ran with no callback, server log shows both executed |
| `dontAsk` | held | `ping_read` ran; `ping_act` denied by the harness ("don't ask mode"), no callback |

Controls: held. The wildcard in `allowedTools` runs both with no callback; the project `deny` rule on `ping_act` still removes it from the model's tools (ToolSearch finds nothing); an `ask` rule on `ping_read` still beats the allow and fires the callback.
The SDK still prints `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED` for tools in `allowedTools`.

## A2. What each mode runs without asking

| Mode | Verdict | Observed on 0.3.326 |
| --- | --- | --- |
| `default` | held | file inside, file outside and `curl` asked (nothing created, nothing run); `ls` ran. The model now wrote with `Bash` instead of `Write`, so the callback carried a `blockedPath` for the file |
| `acceptEdits` | held | `Write` inside ran and the file exists; `Write` outside asked ("Path is outside allowed working directories"); `curl` asked; `ls` ran |
| `plan` | held for the outcomes, **changed** in the path | no file created inside or outside, `curl` and `ls` ran with no ask, as before. Changed: the write of the plan file itself ran without asking (before it asked, as a sensitive file outside the working directories), and the callback fired for `ExitPlanMode` instead; a write outside the folder now reached the callback (before the model did not try it) |
| `auto` | held | all four ran with no callback; both files exist, including the one outside the folder; `curl` returned `HTTP/2 200` |
| `dontAsk` | held | the two writes (via `Bash`) and `curl` were refused by the harness, no callback; `ls` ran |

Not rerun, so UNVERIFIED on 0.3.326: the explicit `Write` in `dontAsk`, and a shell write in `plan` mode (also UNVERIFIED in the first run).

## A3. An invalid model at open

| Item | Verdict | Observed on 0.3.326 |
| --- | --- | --- |
| `open` with `not-a-real-model-xyz` | held | open succeeds in about 0.6 s, the option reads the invalid id and the id is added to the list |
| the first turn | held, message changed | `assistant` event, then `error`, then `turn_end` with outcome `error` and zero usage, about 1 s after `send`. The text now ends with "Run --model to pick a different model." |
| `haiku`, and no model | held, one value changed | the list holds the same 14 ids, `haiku` resolves to `claude-haiku-5-5`. The `default` alias now resolves to `claude-opus-5-5` (it was `claude-sonnet-5-5`); that comes from the account or the binary, not from the SDK call |

## Also seen

The SDK now prints `CLAUDE_SDK_MCP_SERVERS_ARGV_DEPRECATED` when the adapter opens a session with the chat MCP: Carrier starts its own Claude Code and sets no `mcpServersDelivery`, so the MCP servers' headers go on the command line today and a future SDK release will send them over stdin.
It is a warning only, nothing failed; whether to set `mcpServersDelivery` is not decided here.
