# Can a Claude subagent message be tied to a lane and a slice?

Spike 3 of the [macOS app redesign](../specs/macos-app-redesign.md) (story 3). Evidence base: the engine's own 12 Claude executions on one Mac (2026-10-19 to 2026-10-21), read structure only (field names, ids, `Agent` call descriptions, worktree names); no message text was copied. Four of them have subagents: three `ship` runs with 13 build subagents (10, 2 and 1) and one review run with 4. The rule is `attributeSubagentLines` in `src/harnesses/claude.ts`, tested over [`claude-subagents.fixture.jsonl`](../../src/harnesses/claude-subagents.fixture.jsonl) (30 sanitised lines: two build subagents running side by side on lanes 1 and 2, one review subagent, text replaced by `<text>`, ids kept).

## Short answer

The agent is exact. The slice and the lane are hints that held on every run where the model followed Solve's wording, and that fail silently otherwise.

## What the stream carries

| Question | Answer | Held on |
|---|---|---|
| Do a subagent's `assistant` and `user` lines carry an agent id? | Yes: `agent_id`, plus `subagent_type` and `task_description` on the same line. | 17 of 17 subagents, every message line |
| Do they carry the parent call? | Yes: `parent_tool_use_id` is the id of the `Agent` tool call in the main thread. Every such call is in the stream (0 orphans). Main-thread lines have `parent_tool_use_id: null`. | 17 of 17 |
| Is the agent id the task id? | Yes for `local_agent` tasks: `task_started.task_id` equals `agent_id`, and `task_started.tool_use_id` equals the `Agent` call id. The `Agent` call's result in the main thread (`async_launched`) also has `agentId`. | all |
| Start and end | Start: the `Agent` tool_use, `system/task_started`. End: `system/task_notification` with `status` (all `completed`). | all |
| Do the `system/task_*` lines carry `agent_id`? | No, only `task_id`. The rule leaves them with the main thread (`agentId: null`). | all |
| `tool_progress` lines | Their `parent_tool_use_id` is the `Bash` call being waited on, not an `Agent` call. Not a subagent signal. | seen in several runs |

## How the slice and the lane are read

| Source | Result |
|---|---|
| Slice from the `Agent` call description (`Build slice #653`; same text in `task_started.description` and `task_description` on every line) | 13 of 13 build subagents. The 4 review subagents are named `<Pass> pass review PR 673`: no slice, correctly. |
| Slice from the branch (`feat/<epic>/<N>-<slug>` in the subagent's commands) | 11 of 13 and always equal to the description. Absent for the 2 subagents of the run where no branch name appears in their tool inputs. |
| Slice from the `Agent` prompt | Not usable: the prompt is one line that points to a file named after the slice (`prompt-<N>.md`). Same number, but a file name is no better than the description. |
| Lane from a worktree path (`<epic worktree>--lane-N` in `Bash` commands or `file_path` of the subagent's tool calls) | 10 of 13, one lane per subagent, never two. Every one of the 10 is in the one run that used lanes (3 lanes, 10 slices). |
| Lane from the `Agent` prompt or call | 0 of 13. The lane is not announced; it shows up in the subagent's second tool call (the first call precedes the first `cd`). A live view learns the lane one call late. |

The three subagents without a lane (two runs) built their slices one after the other inside the epic worktree. There is no lane to find there, so `undefined` is the right answer, but it cannot be told apart from "the model did not use the convention".

Lanes are slots, not identities: lane 1 was used by 6 of the 10 slices in the lane run (one after another), lanes 1 to 3 ran at the same time at most (matches `background_tasks_changed` with up to 3 tasks). A lane number says where, never which slice, so the slice must come from the description.

## Where it fails

- The slice and the lane are the model's wording and Solve's directory naming. A subagent description such as "Fix the build" gives no slice; a worktree not named `--lane-N` gives no lane. The function returns nothing then, it never guesses.
- Review subagents (`Spec/Standards/Risk/Experience pass review PR N`) are real subagents with an exact `agentId` and no slice or lane. They are not lanes of building.
- Sequential runs in the epic worktree have a slice but no lane.
- The lane is known only from the subagent's second tool call on; the first message of a lane is attributed to the lane in a second pass over the finished list, not live.
- A subagent that edits a file by a relative path after `cd` would not show its lane in that call; the lane was visible in at least one command of all 10 subagents that had one, but nothing guarantees it.
- Only Claude. Codex and `agy` have no subagent lines in this repo.
- Stream shape of claude 2.1.303 to 2.1.305 (the versions of these runs); `agent_id` and `subagent_type` on message lines are not documented as a contract.

## Recommendation

Make exact: the list of subagents of an execution, their start and end, their status, and which messages and tool calls (so which files, tests and errors) each one did. That is `agent_id` with `parent_tool_use_id`, present on every subagent line in every real run. The sections of the Agent output tab per subagent, and the counts per subagent, can be built on it without a caveat.

Label as a hint: the slice of a subagent ("Build slice #N") and the lane number. Show them when the rule found them, with the hint mark the spec already plans (stories 21 and 27), and show the subagent by its description alone when it did not. Do not count on either to sum up per lane (a lane is reused), do not draw a lane column for runs where no subagent has one, and do not use them to key anything stored: key by `agentId`, keep slice and lane as columns that may be null.

The robust sources stay outside the stream: GitHub for which slice is merged or open, and `git worktree list` for the lane paths, as the [data inventory](macos-app-data-engine.md) already recommends. The stream tells which agent did what; GitHub and git tell the state of the slices.
