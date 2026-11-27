# Sessions

**Session** - The conversation an agent holds in its harness, identified by an id the harness can resume (`claude --resume`, `codex resume`, `agy --conversation`). Each execution has one; the app shows an execution's work as one session block and Continue in Terminal resumes it ([0007](../adr/app/0007-continue-in-terminal-through-a-validated-descriptor.md)).
_Avoid_: execution (the invocation with its time limit and result), thread, chat.

**Chat host** - The process that holds user sessions: it starts when a person opens the first chat and ends when no session is running and no client is attached. It has its own lock and control socket, shares code with the engine but not its state, and the engine's stop does not touch it ([0013](../adr/sessions/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)).
_Avoid_: chat server, session manager, engine (the engine runs epics).

**Chat runner** - The port through which the chat host drives one provider's agent: open or resume a conversation in a folder, send a message, answer an approval, interrupt, set an option, close. One adapter per provider implements it (Claude, Codex) and a fake stands in for tests. It is not the `AgentRunner`, which runs one unattended execution to a result.
_Avoid_: provider client, driver.

**Chat event** - What a chat runner reports about a conversation in Carrier's own shape, whatever the provider speaks: a message from the person or the agent, a tool call and its outcome, an approval asked, an option changed, the usage of a turn, the end of a turn. The host stores them as the transcript of a user session, bounded and redacted.
_Avoid_: agent event (the epic executions' events), message, log line.

**User session** - A conversation the person starts inside the app with the agent of their choice, in a workspace. It belongs to no epic ([0012](../adr/sessions/0012-sessions-and-epics-are-two-separate-worlds.md)), is disposable once its job is done, and can be archived. It is a Session in the sense above, when that conversation is not an epic's execution.
_Avoid_: chat, thread.

**New session draft** - What the app shows in New session before the first message: a plan (a folder, a repository to clone or a new project; the branch, worktree and its name; the agent and its options; the text). Choosing or changing any of it does nothing on the machine, and it is blank every time New session opens and after a send ([0018](../adr/sessions/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
The plan's workspace is one of three kinds: a `folder` that exists, a `repo` to clone or fetch, or a new project (`newProject` in Swift and `newProjectKind` in TypeScript, `project` on the wire so an older host still reads it), an empty folder the host makes with `git init`.
_Avoid_: new chat, new session (the session does not exist yet), form, wizard.

**Preparation** - What the chat host does after the first message is sent, in the background and in order, only the steps the plan needs: `clone` (or `fetch`) or `project`, `worktree` or `checkout`, the project's `actions`, `agent`, `message`. The session is `preparing` and shows the steps until the agent answers; a failed step stops it with the reason in words and Try again repeats what did not finish, while Cancel stops the running step and deletes the session (a finished clone stays in the projects folder). A repository to watch is added to the engine's `repos` only after the agent has answered.
_Avoid_: setup (that is a repository's own scripts, out of scope), provisioning, bootstrap.

**Session lifecycle** - The life of a user session: created by its first message, worked in, then archived or deleted by the person or by the clock. A session idle for 15 days is archived and an archived one idle for 30 days is deleted, both from its last activity and both configurable in `chat.json`; a delete by the clock spares a session with unsaved work ([0019](../adr/sessions/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md)).
_Avoid_: expiry, retention, auto-clean.

**Chat MCP** - The MCP server the chat host runs for the agents of its sessions: loopback only, on by default, injected into one session when it opens and never into the agents of an epic or the user's own CLI configuration ([0024](../adr/sessions/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)). Its tools are pre-approved in the harness; what each may do is its access level.
_Avoid_: Carrier MCP (the engine has none), orchestrator MCP, the app's MCP.

**Toolkit** - A group of tools of the chat MCP kept together, with their schemas, handlers and tests, and added as one. The first is `capabilities`; each later capability is a toolkit of its own.
_Avoid_: plugin, module, skill (a skill is the person's or a plugin's).

**Tool access level** - What a tool of the chat MCP declares when it is defined: it reads, it reads as a session (it needs to know which session is calling) or it acts as a session (it changes something and needs a live session that holds the capability to act). The server checks it before the handler runs, and a tool that declares none does not register.
_Avoid_: permission (that is the harness's own, asked of the person), scope, role.

**MCP token** - The random secret that identifies one session to the chat MCP and carries its capabilities. It is kept hashed and only in memory, and ends when the session closes or sits idle.
_Avoid_: session id (that is the session's own), API key, login.

**Agent switch** - A person changing the agent of a user session between turns: the session keeps its transcript, folder and worktree and goes on in a new native conversation with another configured agent, of another harness or another account of the same one ([0032](../adr/sessions/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md)). Changing only the model of the same agent is an option change and not a switch.
_Avoid_: failover (Carrier moving an epic's role by itself when credits run out), provider switch, migration.

**Handoff** - What the new agent of a switched session receives with its first message: a bounded selection of the stored transcript (the person's first message and the newest ones, up to 16,000 bytes), the ids of what was left out and the pointer to the chat MCP's `history` tool that reads them. Carrier chooses it and no agent writes it, and it carries no reasoning, tool state or attachments.
_Avoid_: summary, compaction, context transfer.

**Child session** - A user session started by a delegation from another session, its parent: a real session with its own agent and transcript, working in the parent's folder, kept out of the list of sessions and listed in its parent's summary. It runs one task and takes no message from the person, who can still read it and answer its approvals ([0033](../adr/sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)).
_Avoid_: subagent (a Claude agent inside an execution, with no session of its own), sub-session, worker, thread.

**Delegation** - The person asking, in a session, for work to go to other agents, which the agent carries out with the chat MCP's `delegate_start`, in any mode and with no approval of its own ([0036](../adr/sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)).
It starts child sessions and moves nothing out of the parent.
_Avoid_: failover, subagent call, handover (the parent keeps the session).

**Permission level** - Carrier's scale of four steps for what a chat session may do, from reading only to Claude's `auto`, on which the options of each harness sit (Claude's permission modes, Codex's sandbox and approval policy).
It exists to keep a child session from having more privilege than its parent ([0033](../adr/sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md), [0036](../adr/sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)).
_Avoid_: permission mode (Claude's own option), sandbox (Codex's own option), access level (what a chat MCP tool declares, [0024](../adr/sessions/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)).

**Turn** - The stretch of a session in which the model acts: from a message of the person (or a wake-up by the agent's own work) to the end the agent reports.
A session is working only during a turn or while it has agent work; what is left running after the turn ended is not the model working.
_Avoid_: run, job, activity (anything that is not the model acting).

**Background task** - Anything the agent started that is still running after its turn ended, as the host lists it in a session's `background`: an agent work or a background process.
_Avoid_: job, pending task.

**Agent work** - A background task that is the model's own work: a subagent or a workflow.
It will wake the agent with a result, so the session is still working while it runs.
_Avoid_: background job, async task.

**Background process** - A background task that is not the model working: a command, a monitor, an MCP tool, a dev server left running.
The turn is over, the session is done and the process is a fact about it, not work (it does not mean the engine's [Detached run](orchestration.md)).
_Avoid_: job, service, daemon, running task.
