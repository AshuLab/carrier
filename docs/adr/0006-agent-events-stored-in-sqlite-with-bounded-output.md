# 0006 - The engine records what the agents do as events in SQLite, with bounded and redacted output

- Status: proposed
- Date: 2026-10-21

## Context

The only record of what an agent did is its raw output: each harness (Claude Code, Codex, Antigravity) prints its own JSON stream, and the engine appends it untouched to `orchestrator/logs/executions/<id>/stdout.log`, with no time per line. The control socket serves it as `tail`, the last few lines summarised into 60 to 100 characters, with no id and no structure ([0005](0005-engine-independent-of-the-macos-app.md)). The app's new window has to show each agent's messages and tool calls (what it read, searched, edited and ran, with the result, how long it took, and the diff of an edit), count them per session, show the current action of a running agent, and let a person follow it live. None of that can be built from lines of text with no ids, and the app does not read SQLite ([0002](0002-sqlite-authority-labels-mirror.md), [0005](0005-engine-independent-of-the-macos-app.md)), so the structure has to be made by the engine and served over the socket.

A tool's output can hold anything the agent printed, including values that look like secrets (an `env` dump, a `.env` read). Today only GitHub-token shapes are redacted, and the rule in `AGENTS.md` is that state holds no secrets, so copying output into a database that a UI queries raises the stakes.

## Decision

The engine normalises each harness's stream into events as it reads it. Every harness adapter gains a `parseEvents` that turns a line into zero or more events and keeps the state it needs to pair a call with its result. Events are rows in an append-only table, `execution_events`, whose integer id is the cursor of a new `events` request: `say` (a message of the agent), `tool_start` and `tool_end` (one call, with the tool, its one-line argument, a result summary, status, duration, and for an edit its diff), `note`, `error` and `task` (a subagent started or ended).

Output is bounded before it is stored: an argument is cut at 1 KB, a result summary at 200 characters, a command's output keeps its first and last lines up to 4 KB, a diff is capped. Every string goes through a redaction that is wider than today's and is tested against fixtures, before it is inserted. The complete output stays only in `stdout.log`, which remains the source of truth and the replay source: a script can feed an old log through the adapter to fill the table for executions that already ran. The events are deleted together with the logs, 30 days after the epic ends.

Claude's adapter comes first, because its stream is the only one verified against real runs. Codex and Antigravity follow once a real stream of each has been captured; until then their sessions show the summarised `tail` lines. The adapters ignore events they do not know and never throw, since the harnesses change their output between versions.

The reviewer's result also changes: each blocker may carry a stable `id`, and the result may list the ids it now considers resolved. The review prompt passes the previous blockers to the reviewer. Both fields are optional, so existing results and a reviewer that ignores them still validate, and the app falls back to matching titles, marked as approximate.

## Alternatives considered

Parse `stdout.log` on demand for every request, with a byte offset as the cursor. It stores nothing and copies no output into the database, but every per-session count (calls, edits with their lines added and removed, errors) needs a full parse of a log that reaches 3 MB, a call and its result can fall on different sides of a cursor, Codex has no time per line to recover, and the current action of every running agent would need a tail read on every snapshot.

Store the arguments and summaries but no output, and open `stdout.log` on demand. It is the safest for secrets and was the fallback if the owner did not accept the risk. It makes the collapsed output of a command, which the design shows, impossible without reading the log.

Store everything and trust the redaction. Rejected: the redaction cannot know every secret shape, and the table would hold full file contents read by an agent.

Resume at the level of the stream only, with no reviewer contract change, and match blockers by title. It needs no prompt change, but titles are the model's free text and the same finding is often worded differently, so "carried over" and "fixed" would be wrong often enough to mislead.

## Consequences

The app gets a stable, paged, structured view of what each agent did, and the snapshot can carry the newest event of each running session without a tail read. The cost is a new table whose size depends on how much the agents do: from the 12 executions seen, a large ship stays under 1 MB of rows and a review or fix under a few tens of KB, which is an extrapolation to confirm by measuring the real insert path.

Secrets are now copied from a log file into a database the app can read through the socket. The mitigation is the bound, the wider redaction and the retention, and it is a mitigation, not a guarantee; a pattern list can miss a secret. The redaction tests are part of the work.

There is one parser per harness to maintain, and each breaks when its CLI changes its output format. Changing what the reviewer is asked and returns needs a real run to see whether the models comply, and until then the carried-over and fixed marks are approximate.
