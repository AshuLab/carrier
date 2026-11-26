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
`remote_agent` and `in_process_teammate` are placed by inference (they exist in the CLI, and what they do while they run was not confirmed), and `local_script` is unknown: it is a process by the rule above.
`awaited` and `off_host` come in the SDK's entries but are not typed or documented, and nothing here relies on them.

Codex is not touched: the host reads no background task from it today, and its terminals and subagents reach the host only as items, so the rule has nothing to separate there.
`stopTask` stays as it is, and a Stop of the session's menu still stops every background task it lists.
