# Antigravity `stream-json`: the event shapes the app needs

> Spike from 2026-10-21 for story 2 of the [macOS app redesign](../specs/macos-app-redesign.md). Complements [antigravity.md](antigravity.md), which covers whether `agy` can be a harness at all. `agy` 1.4.4, model `gemini-3.8-flash-low`, one short task (search, a failing command, an edit, a listing) in a throwaway git repository under the system temp folder, deleted afterwards. The captured stdout is [`src/harnesses/agy-stream.fixture.jsonl`](../../src/harnesses/agy-stream.fixture.jsonl), with the temp path replaced by `/work/repo`, the conversation id by `00000000-0000-4000-8000-000000000001` and the user name by `user`. stderr was empty. The test in `src/harnesses/agy.test.ts` loads it. One run of one model: what is listed as "not seen" is not ruled out.

## Lines

One JSON object per line, three kinds of `event`:

| `event` | Carries |
|---|---|
| `init` | First line. `conversation_id`, `init.model`, `init.cwd`, `init.permission_mode`, `init.tools` (60 tool names, ~1.3 KB: not worth storing). |
| `step_update` | `step_update.{conversation_id, step_index, state, step_type, ...}`. `state` is `ACTIVE` or `DONE`. |
| `result` | Last line. `status` (`SUCCESS`), `response` (the final text), `duration_seconds` (whole run), `num_turns`, `usage`. |

`conversation_id` is on every line, so the session id never has to be remembered from `init`. `step_index` is a counter inside the conversation (0, 1, 2, ...), the same for the `ACTIVE` and the `DONE` of one step. There is no `tool_use_id`: a call is paired with its result by `(conversation_id, step_index)`.

## Step types seen

| `step_type` | What it is | Lines |
|---|---|---|
| `user_input` | The prompt. One `DONE`, no text (the prompt is not echoed). | 1 |
| `agent_response` | A model turn. Before a tool call it is a single `DONE` with no `text_delta`, with `duration_seconds` and `usage` (the model call). The last one streams the final text as several `ACTIVE` lines with `text_delta` (fragments to concatenate; they are not cumulative) and ends in a `DONE` whose `text_delta` is `"\n"`, with `duration_seconds` and `usage`. | 1 to many |
| `tool` | A tool call, see below. | 2 (`ACTIVE`, `DONE`) |

The reasoning text is never streamed; only `usage.thinking_tokens` (a count) shows it happened. Steps ran one at a time here, so at most one tool was `ACTIVE`; whether parallel tool calls interleave was not seen.

## Tool steps

Tool names seen: `run_command`, `read_file`, `write_file`, `edit_file` (a run asked to search used `run_command` with `grep`, so there is no dedicated search step to count on).

- **Call.** The `ACTIVE` line has `tool_name` and `tool_info: {name, parameters}`. `tool_info` is a JSON object, not the Python-like string that [antigravity.md](antigravity.md) described. `parameters` are the tool's own, with capitalised keys: `run_command` has `CommandLine`; `read_file`, `write_file` and `edit_file` have only `Path`.
- **Edits carry no content.** `write_file` and `edit_file` parameters hold the path and nothing else: no new text, no old text, no patch.
- **Duration.** Only on the `DONE` line, as `duration_seconds`, a float in seconds with microsecond digits (`0.113831`). The `ACTIVE` line has none.
- **Result.** The `DONE` line repeats `tool_info` and adds `tool_info.output` for some tools, as a string:
  - `run_command`: `"Command exited with code 1.\n\nCommand output:\nls: /nonexistent: No such file or directory\r\n"`. The exit code is only in that sentence, there is no field, and lines end in `\r\n`. A failing command is still a `DONE` step: nothing marks it as an error except the code in the text.
  - `read_file`: a summary only, `"2 lines, 11 bytes"`, never the file content.
  - `write_file`, `edit_file`: no `output` key at all.
  - Not seen: a tool that fails to start, a tool that is cancelled, a step left `ACTIVE` by a kill.

## What the stream does not give

The engine would have to stamp or derive these itself:

- **Any wall-clock time.** No step has a timestamp. The engine stamps the arrival time of each line: `startedAt` on the tool's `ACTIVE`, and `endedAt` on its `DONE` (or `startedAt + duration_seconds`, which is the tool's own measure and excludes the pipe delay).
- **A diff or the written content** for `write_file` and `edit_file`. Compute it from `git diff` of the workspace, as already planned for Codex.
- **File content read** (`read_file` returns a size) and **the reasoning text**.
- **A success flag per tool.** For `run_command`, parse `Command exited with code (\d+)` from `output`; for the others, absence of an error is all there is.
- **The user prompt**, which `user_input` does not echo. The engine already has it.
- **Per tool tokens.** `usage` is on `agent_response` steps and on `result`, never on a tool step.
- **A search or list tool** as a distinct kind; those showed up as `run_command` or `read_file` here.

## For the parser

`parseEvents` can key on `step_update` with `step_type: "tool"`: open on `ACTIVE`, close on `DONE` by `step_index`, take the summary from `tool_info.parameters` (`CommandLine` or `Path`), the result from `tool_info.output` when present, and the duration from the `DONE`. Messages come from the `text_delta` of `agent_response` steps. Unknown `step_type` or `tool_name` values should be shown by name and not fail, because only four tools and three step types were seen out of 60 tools in `init.tools`.
