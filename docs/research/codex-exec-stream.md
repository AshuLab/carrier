# Codex `exec --json` stream: the event shapes the macOS app needs

> Spike of 2026-10-21 for the [macOS app redesign](../specs/macos-app-redesign.md) (issue #112). It closes the "not verified" part of the [engine data inventory](macos-app-data-engine.md) for Codex. One real run of `codex exec ... --json --dangerously-bypass-approvals-and-sandbox` (codex-cli 0.153.4, the flags of `src/harnesses/codex.ts`), stdin closed, in a throwaway git repository under the system temp directory, deleted afterwards. The prompt asked to read a file, run `ls -la`, run a command that fails, append a line to a file and create a new one. The stdout is saved as [`src/harnesses/codex-exec.fixture.jsonl`](../../src/harnesses/codex-exec.fixture.jsonl) with the thread id, the user name and the scratch path replaced by placeholders; the existing adapter test loads it.

## Every line is one JSON object

Top-level `type` values seen, in order: `thread.started`, `item.completed`, `turn.started`, `item.started`, `item.completed`, `turn.completed`. Not seen in this run (a failed turn prints `turn.failed`, an API retry prints `error`, both already handled in `codex.ts`).

| Line | Fields |
|---|---|
| `thread.started` | `thread_id` (the session id; the first line) |
| `turn.started` | none |
| `turn.completed` | `usage`: `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens` |
| `item.started` / `item.completed` | `item`, with `item.id` (`item_0`, `item_1`, ... counted per thread) and `item.type` |

Item types that appeared:

| `item.type` | Appears as | Fields besides `id`, `type` |
|---|---|---|
| `error` | `item.completed` only | `message`. Here a notice about `--dangerously-bypass-hook-trust`, printed twice before `turn.started`: a warning, not a failure |
| `agent_message` | `item.completed` only | `text` (what the agent says, also the last message, here `DONE`) |
| `command_execution` | `item.started` then `item.completed` | `command`, `aggregated_output`, `exit_code`, `status` |
| `file_change` | `item.started` then `item.completed` | `changes`, `status` |

`reasoning` and `todo_list` items did not appear (the model was not asked to plan); do not assume they never will.

## `command_execution`

- **Command**: `item.command`, the full shell line as run, wrapped by Codex: `/bin/zsh -lc 'ls -la'`. A summary that wants the user's command has to strip the `<shell> -lc` wrapper.
- **Output**: `item.aggregated_output`, stdout and stderr merged, in one string. Empty (`""`) on `item.started`, complete on `item.completed`. There is no streaming of partial output.
- **Exit code**: `item.exit_code`, a number on `item.completed` (`0`, or `1` for the failing `ls`), `null` on `item.started`.
- **Status**: `item.status`: `in_progress` on start, then `completed` (exit 0) or `failed` (exit not 0). A failed command is still a normal `item.completed`, not an error line.
- **Pairing**: `item.started` and `item.completed` share `item.id`. Commands ran one at a time in this run.

## `file_change`

- **Files**: `item.changes`, an array of `{path, kind}`. `path` is absolute. `kind` seen: `add`, `update` (`delete` is expected, not seen). One item can hold several files (the new file and the edited one came together in one item).
- **Diff**: none. No hunks, no line counts, no content, on start or on completion.
- **Status**: `in_progress` then `completed`; `failed` was not seen.
- **Pairing**: same `item.id` on `item.started` and `item.completed`; the two lines were identical except for `status`.

## What Codex does not give

- **No time anywhere.** No timestamp or duration on any line or item (searched for `timestamp`, `ts`, `started_at`, `duration`: none). The only clock is the order of the lines.
- **No diff** for `file_change`, and no per-file counts of added or removed lines.
- **No partial output** for a running command: `aggregated_output` is `""` until the item completes, so a "current command, live output" view has the command line only.
- **No separate stdout and stderr**; no working directory per command; no tool name beyond the item type.
- The user's own command is hidden behind the `<shell> -lc` wrapper.
- Token usage only per turn (`turn.completed.usage`), not per item.

## What the engine would have to stamp or compute itself

- **Time**: the engine stamps its own arrival time on each line (`HostAgentRunner` already sees each line as it is printed). The duration of a command is the gap between the arrival of its `item.started` and its `item.completed`; accurate to the pipe latency, which is enough for a panel.
- **Diff**: run `git diff` (and read untracked files for `add`) in the workspace after the `file_change` completes, or once at the end of the stage. With several `file_change` items on the same file, a diff per item is not recoverable from the stream; only the workspace's state is.
- **Command text**: strip the `<shell> -lc` wrapper for display.
- **Output size**: `aggregated_output` is whole and can be large; cap it before it is stored (see the inventory's recommendation) and redact it first, since the stream carries the raw output of any command (an `env` dump, a `.env` read).
- **Pairing**: key open calls by `item.id`; `error` and `agent_message` items have no `item.started`, they are complete on their one line.
