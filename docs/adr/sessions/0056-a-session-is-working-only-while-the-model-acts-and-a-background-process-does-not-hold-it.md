# 0056 - A session is working only while the model acts, and a background process does not hold it

- Status: proposed
- Date: 2026-11-26

## Context

The host lists what the agent waits for after its turn ended (`background`), and a session with any task in that list is working: its ring and clock go on (in cyan instead of the violet of a turn), it sits in the Working group, it is never Done and it cannot be archived ([session-lifecycle](../../specs/session-lifecycle.md), `docs/macos/sessions.md`).
That was written for a subagent, whose result wakes the agent, and it is right for it.
It is also what a `pnpm dev` the agent left running gets: the session shows the model as working for as long as the process lives, which can be forever, and the person cannot tell a turn from a process that nobody is watching.
The conversation's card over the message box has the motion of a turn too (a ring that turns, a glow, a shimmer), and only its colour says it is not the model.

The Claude SDK does not separate the two for us.
`task_type` of `background_tasks_changed` is a free `string`, not an enum, and "wakes the agent when it ends" separates nothing: nearly every task that ends starts a turn, a shell that exits as much as a subagent.
What separates them is whether the model goes on working while the task runs, and that is a product rule of ours, not something the SDK declares.

## Decision

A session is working during a turn, and while it has **agent work**; a **background process** does not hold it.
With only background processes left, the session is idle or Done like any whose turn ended, its clock stops, and the processes are shown apart from the working state (how is a prototype's question, not this record's).

What is agent work is an allowlist on the Claude task's `task_type`: `local_agent`, `local_workflow`, `in_process_teammate` and `remote_agent`.
Any other value is a background process, the ones the SDK names today (`local_bash`, which includes a Monitor that runs a command, `monitor_mcp`, `monitor_ws`, `mcp_task`) and any value it adds later.
`ambient` tasks stay out of the list altogether, as they are.

The Claude adapter applies the allowlist once, as it reads each task, and says the answer on the task (`agentWork`); the host and the app read that field and keep no list of their own, so they cannot disagree, and a host that does not send it reads as agent work, as before.
The rule is one place in the app, `SessionRow.isWorking`, and every surface that asks whether a session works (the sidebar, the Working group, the order, the clock, the hover card, the Sessions home) follows it.

A session with only background processes can be archived, after a confirmation that says which processes it stops ("This stops `pnpm dev`"), and the archive stops them.
A session with agent work still refuses, as it does today.
A session with any background task is still not closed for being idle, because closing it ends the agent's process that owns them.

## Alternatives considered

Keep the session working and tell the two apart by colour or words only.
It is what exists, and the person still reads motion and a running clock as the model acting.

A group of its own for sessions with processes ("Running").
The session would be in two places at once, working-or-done and running, and the group would hold sessions that need nothing from the person.

Tell a process that ends from one that never ends, by how long it has run or by its command.
There is nothing in the event to say it, a guess would be wrong in both directions, and the person's problem is not how long it lasts but that it is not the model.

Block the known processes (`local_bash`) and let every other type count as work.
A type the SDK adds later would silently be shown as the model working, which is the bug this record removes; an allowlist fails the quiet way, a process shown as a process.

Keep refusing the archive while a process lives.
A Done session that cannot be archived reads as a fault, and the person asked for the processes to stop mattering to the state of the session.

## Consequences

A session whose turn ended with a dev server alive is Done and, if unread, shows as unread: it asks for the person like any finished session, which is the point.
A person can forget a process that no state of the session reminds them of, so the marker of processes has to be visible enough to be found again; that design is open.

The allowlist depends on a string the SDK does not promise, so a new agent-like type is a process until it is added here.
`local_agent` was seen (below), and it is agent work.
`remote_agent` and `in_process_teammate` are still placed by inference: the spike ([#1542](https://github.com/AshuLab/carrier/issues/1542)) could not make either appear, so nothing here says what the host lists for them or whether the model goes on working meanwhile.
`local_script` is unknown: it is a process by the rule above.

What the spike did, on 2026-11-26, with Claude Code 2.1.332 (the `claude` on the path, which is the binary the adapter runs) and `@anthropic-ai/claude-agent-sdk` 0.3.326, model `haiku`, in a throwaway folder under the temporary directory and never `~/.carrier`.
A script outside the repo opened a conversation with Carrier's own adapter (`claudeChatRunner().open`, `src/chat/claude.ts`), logged each raw `background_tasks_changed` message by wrapping the SDK's `query`, and logged each `ChatEvent`; it did not go through the chat host's process or its database.
That driver is not kept in the repo.
To redo the close check: in a throwaway folder, open a conversation with `claudeChatRunner().open`, ask the model to run `sleep 4217` with `run_in_background`, wait for the turn to end, call `conversation.close()`, then look for the sleep with a pattern that cannot match the checking command itself, for example `pgrep -f '[s]leep 4217'` or `ps -axo pid,ppid,pgid,command | grep -v grep | grep 'sleep 4217'`.

- **Teammate (`in_process_teammate`): not observed.** With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, with and without the flag `--teammate-mode in-process`, three runs asked the model to spawn a teammate named `helper` with the `Agent` tool (`name` set, no `subagent_type`, with and without `run_in_background`) that ran `sleep 15` or `sleep 20` while the lead went on running `sleep 3 && echo tick`.
  Every time the host listed `{"task_type":"local_agent","subagent_type":"general-purpose"}`, no `ambient`, `agentWork: true`, and the lead's ticks went on while it ran, until the task ended and the list became empty.
  That confirms `local_agent` and nothing about teammates: this version has no `TeamCreate` tool (the model looked for it and did not find it: seen in the runs' logs, which were not kept; the `Agent` tool's `team_name` is described as "Deprecated; ignored. The session has a single implicit team." in `AgentInput` in `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts`, SDK 0.3.326), and a spawn with a `name` never became a teammate in the headless stream (also from the logs, not kept).
  Why is not known: the code that spawns a teammate sits behind a condition this run did not meet (the CLI's own flags, which a person's account sets, or an interactive session), and the interactive session was out of reach of this spike.
- **Remote agent (`remote_agent`): not observed**, on purpose: it starts a cloud session, which bills and runs outside the machine, and the spike was not to launch one.
  The SDK's own type says where it comes from (`WorkflowOutput.taskType` in `sdk-tools.d.ts`: "`remote_agent` when `remote:true` dispatches to CCR") and the CLI names it "cloud session".
- **What the CLI itself says (read in its bundled code, not observed in a run).** The bundle is embedded in the `claude` binary (`~/.local/share/claude/versions/2.1.332`), and its identifiers are minified, so it is found by text: `grep -a -o 'new Set(\["local_agent","remote_agent","in_process_teammate","local_workflow"\])'` for the set, and `e.isIdle`, `e.isLongRunning` and `e.type==="local_bash"&&!` next to it for the exclusions and the test for `local_bash`. The CLI keeps one set for the tasks that count as agent work running, `local_agent`, `remote_agent`, `in_process_teammate` and `local_workflow`, and a separate test for `local_bash`.
  That is the allowlist here, from the side that owns the types, so it is the best evidence that none of the four is wrongly placed; it is not an observation of what the host lists or of the model working.
  The same code leaves out of that count an idle teammate (one that waits for a message) and a cloud session marked as long-running, and `background_tasks_changed` carries nothing that tells either, so a teammate that is only waiting may hold a session as working here.
  That reading is also inferred.

Nothing seen or read puts a type in the wrong list as a whole, so the allowlist in `src/chat/claude.ts`, its test and the spec's list stay as they are.
The one gap that was read is inside two of the types: an idle teammate and a long-running cloud session count as not working in the CLI, and the event carries neither, so they may read as agent work here.
A person who runs a teammate or a cloud agent in the app, and looks at what the session shows, closes the two open ends.

Closing a session ended a background shell: in the six runs the shell was gone by the end of the run, after `conversation.close()`, though how soon was not the same in each, and in three of them it was checked only at the end.
The model was asked to run `sleep 4217` with `run_in_background`; the host listed `{"task_type":"local_bash","description":"Sleep for 4217 seconds"}` (no `ambient`, `agentWork: false`) and the turn ended.
`ps -axo pid,ppid,pgid,command`, filtered for `sleep 4217`, then showed the shell and its `sleep`, children of the `claude` process but in a process group of their own, not the agent's.
The script then called `conversation.close()`, which is what the host's `close` ends in for an archive or a delete (`src/chat/sessions.ts`), with no `stopTask` before it, and looked again.
What each run showed: gone 1.5 seconds after the close in the first run; still there 1.5 seconds after it in the second and gone a few seconds later (the exact figure was not kept); gone at the first check in the sixth, which polled every 0.2 seconds right after `close()` returned; in the three between, only that nothing was left at the end of the run.
So every run ended with the shell gone, within a few seconds of the close where it was timed, and one run needed those few seconds.
This ADR does not separate a delayed kill (the `claude` process taking its shells down as it ends, or the shell ending on its own once its parent is gone) from some other cause, and the spike did not observe which step ends it.
The shell is in a process group of its own (seen in `ps`), and `endGroup` signals the agent's group (read in `src/chat/group.ts`, not run), so by reading it is not that signal that reaches it directly.
So the archive's promise held for a closed session in these runs, which never called `stopTask` (the host calls it before the close, and that path was not run), and no ticket is needed for it.
The exact filter the original script used to leave its own command out of the match was not recorded: `ps ... | grep "sleep 4217"` alone also lists the `grep`, and `pgrep -f` can match the checking script's own command line, which holds that text, so the redo above uses a pattern that excludes itself.

One side check, a single observation, not a series: a SIGKILL sent to the `claude` process left its shell alive, with `ps` showing its parent as `launchd` (pid 1) and a process group of its own.
The command used, and whether it was repeated, were not kept, and nothing says it is the only way a shell is left running.
`endGroup` escalates to SIGKILL after three seconds when `claude` does not end on SIGTERM, and the startup sweep signals the agent's group by the `pgid` it stored (`src/chat/sweep.ts`), so by reading both a shell in a group of its own would not be reached there; that part is read, not run.
It is a leak of a host that dies or an agent that does not end, not of archiving, and it is left as a note here and not as a ticket.
`awaited` and `off_host` come in the SDK's entries but are not typed or documented, and nothing here relies on them.

Codex is not touched: the host reads no background task from it today, and its terminals and subagents reach the host only as items, so the rule has nothing to separate there.
`stopTask` stays as it is, and a Stop of the session's menu still stops every background task it lists.
