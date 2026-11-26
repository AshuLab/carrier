# Background processes are shown apart from the turn

Status: spec

## Problem

When the agent ends its turn and leaves something running (a `pnpm dev` of a front end it brought up, a build, a monitor), the macOS app shows the session as working: a ring and a clock that go on, in the sidebar and in a card over the message box with a turning ring, a glow and a shimmer.
Only the colour (cyan instead of the violet of a turn) says it is not the model, and a person reads the motion and the clock first.
Diego sees the session as busy when the model is doing nothing but a script running in the background, and with a process that never ends the session stays working for good: it never reaches Done and it cannot be archived.

The two things that are called "background" here are not alike.
A subagent or a workflow is the model's work, will wake the agent with a result, and is right to hold the session as working.
A command, a monitor or a dev server is not the model working: the turn is over.
Today the app has one state for both.

## Solution

A session is working during a turn and while it has agent work; a background process does not hold it ([0056](../adr/sessions/0056-a-session-is-working-only-while-the-model-acts-and-a-background-process-does-not-hold-it.md)).
A session left with only processes is idle or Done like any other, its clock stops, and the processes are a fact shown beside it.
The terms are in the glossary (Turn, Background task, Agent work, Background process).

**What is agent work** is decided once, by the Claude adapter, as an allowlist on the task's `task_type`, because the SDK types it as a free string: `local_agent`, `local_workflow`, `in_process_teammate` and `remote_agent` are agent work, and everything else, today's (`local_bash`, which includes a Monitor that runs a command, `monitor_mcp`, `monitor_ws`, `mcp_task`) and tomorrow's, is a process.
It was checked in the SDK's types, its docs and the CLI it ships; the placement of `remote_agent` and `in_process_teammate` is inferred.
"Wakes the agent when it ends" does not separate them, since a shell that exits wakes it too, so the line is whether the model goes on working while the task runs, which is a rule of Carrier's.
The adapter says its answer on each task (`agentWork`), the host stores it and lists it in `background` with the rest, and every reader asks that field instead of keeping a list of its own, so the host and the app cannot disagree.
A host that does not send the field reads as agent work, which is what the app did before.

**The sidebar.** The row reads as any session whose turn ended: the project's icon has no arc, "Done" in green with the time while it is unread, the plain time after, and it sits in its age group and not in Working.
While the session has a process it carries a still mark: the terminal glyph and the count, in a small grey capsule with no colour and no motion, at the right of the second line (the place and branch line) and before the provider marks.
There it meets nothing the row already says: the title and the time keep their line, and Pin and Archive, which take the time's place under the pointer, never touch it; when the row has a third line the providers go down to it and the mark has the second line to itself.
The mark also shows while the model works on a turn, beside the arc and the stopwatch of that turn.
The hover card says what runs in the background in a line of its own, not in the tone of work, and VoiceOver reads the row with "N background processes".
The rule is one place, `SessionRow.isWorking` and the status derived from it, so the sidebar, the Working group, the order and clock, the hover card and the Sessions home follow it together.

**The conversation.** The processes are one grey notice card over the message box, in the family of the queued-message card (`NoticeCard`, grey: nothing is asked of the person): "2 processes still running", their names, Stop all (Stop when there is one) and a chevron that opens the card in place to a row for each process with its command, how long it has run and its own Stop.
It has no ring, no glow and no shimmer, it stacks with the other notices as they do, and it is gone with the last process.
It replaces the cyan card only for processes: the card for agent work stays as it is, and both can show together.
Stop on the card stops a process through the host's `stopTask`, so a host that does not list that capability shows the card without Stop, and `interrupt` is never used for it (with no turn running it would stop agent work too).
A process shows in the transcript as the call that started it, as today.

**Archive and delete.** A session with only processes can be archived or deleted.
The app asks first, saying what it stops ("This stops pnpm dev"), and the host stops each process through `stopTask` before it closes the session, logging and going on when one refuses.
A session with agent work still refuses, as today, and the idle close still spares a session with any background task, since closing it ends the agent's process that owns them.

What was cut: telling a process that ends from one that never does (there is nothing in the event to say it, and the problem is that it is not the model, not how long it lasts); a group of its own for sessions with processes (the session would be in two places and the group would hold sessions that need nothing); the mark after the title (it takes the title's width) and beside the time (it is the column Pin and Archive take); a blocklist of `local_bash` (a type added later would show as the model working again); a list of agent work kept in Swift beside the one in TypeScript (they drift); and, for the conversation, a pill in the header next to the terminal button (it is confused with the person's own shell), a tab in the terminal drawer (the drawer is shut most of the time and these are not terminals to type in) and the card of today made quieter (it still reads as something the model is doing).
Keeping the call that started the process alive in the transcript ("running · 14m · Stop") was drawn and is a possible addition, not part of this.

## Scope

1. As Diego, when the agent's turn ended and only processes are left, I see the session as Done while unread and as idle after, with no arc round its icon and no stopwatch, in its age group and not in Working.
2. As Diego, I see a small still mark with the count of processes at the right of a row's second line, before the provider marks, and alone on that line when the row has a third.
3. As Diego, I see that mark also while the model works a turn, beside the arc and the stopwatch of the turn.
4. As Diego, I see a session with a subagent, a workflow, a teammate or a remote agent running as working, as before, and with the live card.
5. As Diego, I see a task of a type the app does not know as a process.
6. As Diego, I see one grey card over the message box that says how many processes are running and their names, with Stop all, and with no motion.
7. As Diego, I open that card in place and see each process with its command and how long it has run, and I stop one of them or all of them from it.
8. As Diego, I see the card go when the last process ends or is stopped, and the mark leave the row with it.
9. As Diego, I archive or delete a session with only processes after the app tells me which ones it stops, and they are stopped; I am still refused for one with agent work.
10. As Diego, I see on the hover card what runs in the background, and with VoiceOver I hear "N background processes" on the row.
11. As Diego, with a process left running, the session is still not closed for being idle, and when the process ends and the agent wakes, the session works that turn as before.

## Decisions

The rule and its reasons are in [0056](../adr/sessions/0056-a-session-is-working-only-while-the-model-acts-and-a-background-process-does-not-hold-it.md); the terms are in the glossary.

**Where the allowlist lives.** The Claude adapter classifies when it translates `background_tasks_changed`, and the answer travels on the task.
The match is exact and by membership, so a missing, empty, wrong-typed or differently-cased `task_type` is a process:

```ts
// runner.ts
export type BackgroundTask = { id: string; kind: string; description: string; agentWork: boolean };
// claude.ts
const AGENT_WORK = new Set(['local_agent', 'local_workflow', 'in_process_teammate', 'remote_agent']);
// per task, after the `ambient` filter:
const kind = String(task.task_type ?? 'task');
{ id: String(task.task_id), kind, description: String(task.description ?? ''), agentWork: AGENT_WORK.has(kind) }
```

```swift
// BackgroundTask: a host that does not say reads as agent work, as before
public var agentWork: Bool   // decodeIfPresent(Bool.self, forKey: .agentWork) ?? true
// SessionRow
public var isWorking: Bool { state == .working || (state != .waiting && background.contains { $0.agentWork }) }
public var processes: [BackgroundTask] { background.filter { $0.agentWork == false } }
```

**The host.** `settle` (archive and delete) refuses only for agent work, with the codes it has (`session.tasksRunning`, `session.childTasksRunning`) counting agent work alone; before it closes, it stops each process through `stopTask` and logs a refusal without stopping.
`armIdle`, `interrupt` and `stopTask` keep treating every background task as they do, and `chat-host.md` says the new field and the new archive rule.

**The app.** `archiveBlock` reads agent work; a new function says which processes an archive or a delete would stop, for the confirmation, in `CarrierCore` with the other session-menu rules.
The processes card is its own view over the message box (`NoticeCard`, grey), fed by `ConversationModel` with the processes and with whether the host can `stopTask`; the cyan card is given agent work only.
New words go in `Localizable.xcstrings` in English and Spanish, as the background-work lines did.
The UI guide (`docs/ui.md`), `docs/macos/sessions.md` and `docs/macos/chat.md` say the new row mark and the card, and the fixture `chat-events-background.json` gets a session that has only processes; the view work follows `macos-ui-change`.

**Testing seams**, the broadest one that still isolates each story:

- Stories 4 and 5, the classification: `src/chat/claude.test.ts`, through the `background` event the adapter emits for a `background_tasks_changed` message, with each known type, an unknown one, a missing one and an `ambient` one.
- Stories 9 and 11, the host: `src/chat/sessions.test.ts`, through `sessions.list`, `archive`, `delete` and the idle close on a session with a fake conversation (the tests for background work there), checking that processes alone do not refuse, that each one is stopped before the close, and that agent work refuses as it does.
- Stories 1, 2, 3 and 5, the state: `macos/Tests/CarrierCoreTests` through `SessionRow` (`isWorking`, `status`, `workingSince`), the grouping of `SessionSections` and the decoding of a task with and without `agentWork`.
- Stories 9 and 10, the words: `SessionMenuTests` (`archiveBlock` and the processes an archive stops), `SessionPeekTests` (the hover card's line) and the Spanish tests for the new copy.
- Stories 6, 7 and 8, the card: what it shows (the names, whether Stop is offered, when it goes) is a function in `CarrierCore` tested through `ConversationModel`'s processes; how it looks has no unit test, and is checked against the fixture in the states of the UI guide (one process, several, open, model working too, no `stopTask`) as `macos-ui-change` asks.
- Story 2, the mark's place: the same fixture, with a row that has a third line and one that has not.

## Out of scope

Codex: the host reads no background task from it and its terminals reach it as items, so there is nothing to separate there.
Antigravity: it does not run in the chat.
Telling a monitor from a shell: `kind` does not travel in `background_tasks_changed`, and both are processes.
Changing how a subagent or any agent work is shown, in the conversation, in the sidebar or in its own view: another epic is on it, and until it lands the cyan card and the live look stay for agent work.
Stopping or restarting a process beyond what `stopTask` does today.
Showing the address of a process (`localhost:5173`) as a link: the host does not send it and reading it from the output is its own feature.

## Open questions

Whether `remote_agent` and `in_process_teammate` are agent work as inferred: it needs a session that runs a teammate and a cloud agent to see what the host lists while they run (`research`).
A wrong placement costs little: a teammate shown as a process leaves the session Done while it works, and the person can still read and stop it.

Whether closing a session ends the shell tasks its agent started: the archive does not depend on it, since it stops each process first, but the promise "archiving stops them" holds only as far as `stopTask` does (`research`).
