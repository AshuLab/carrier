# A chat host lets you talk to any provider's agent

Status: spec

## Problem

Carrier covers only the automatic half: it takes epics that are ready and implements them. To talk to an agent first (to think, to explore a repo, to write the work down) the person leaves for a terminal or for the provider's own app, so what they ask Claude, Codex or any other agent, and what comes back, lives outside Carrier and outside the app that is about to show their work.

The app is going to have a place for conversations ([0012](../adr/0012-sessions-and-epics-are-two-separate-worlds.md)), and the macOS epics that build it need something to talk to. Carrier has no part of that today: its only way to run an agent is an unattended execution that takes a prompt in argv, gives no input afterwards and ends in one result for an epic. Nothing in `src/` holds a conversation, and the research behind this ([in-app sessions](../research/in-app-sessions.md)) is the only record of the idea.

This epic is the backend of the conversation and nothing else: a chat with an agent of the person's choice, in a folder, with no screen of its own besides the terminal. It knows nothing about epics, labels or the skills flow; what an agent does with its own tools and skills is the provider's and the person's, as in a terminal.

## Solution

### The host

A chat host: a process of its own with its own lock, its own control socket and its own SQLite file, all under `<root>/chat/` (`chat.sock`, `carrier.lock`, `chat.db`, `logs/`). It shares code with the engine (config, logger and its redaction, process handling) and none of its state, and the engine's stop does not touch it ([0013](../adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)). A file of its own, with its own Drizzle migrations, keeps two processes from migrating or writing the engine's database; `pnpm db:generate` gains a second config for it and the build copies both migration folders.

A client starts it on demand. `carrier chat` looks for a host on the socket and, finding none, starts `carrier chat-host --config <file>` detached, the way `carrier start` starts the engine ([0010](../adr/0010-carrier-runs-in-the-background-as-a-detached-process.md)), and waits for the socket to answer. `chat-host` runs the host in the foreground and is also how it is debugged. Nothing starts a host but a client that wants a chat.

A session is live while its agent process runs. With no client attached, an idle session is closed after one minute: its process ends, the session stays in the list and resumes by its id. A session that is working, or waiting for an approval, is kept live. The host exits one minute after the last live session ended and the last client left, and `carrier chat --stop` closes every session and ends it at once. Each live session records its process id and its process group; the agent leads its own group, and when a host starts it sweeps the groups a dead host left behind, SIGTERM then SIGKILL, after checking the process is still the recorded command.

### The port and the adapters

The chat runner is the port through which the host drives one provider, with a fake for tests, and it speaks Carrier's own chat events whatever the provider speaks. It is not the `AgentRunner`: nothing in it is epic-shaped, there is no result file and the process is not done after one answer.

Claude's adapter uses the Claude Agent SDK pointed at the user's own `claude` binary; Codex's uses `codex app-server`. ACP is not the seam and no ACP adapter is part of this epic. The first ticket is a spike that settles both paths against the real tools before anything is built on them: input works across several turns; an approval round-trips and a decline is honoured; a session id comes back and a second run resumes it; the options (permission mode, model, reasoning level) can be listed, set and changed; an interrupt stops a turn; the user's installed skills are visible; and the agent's process can lead its own group. The findings are written to `docs/research/chat-spike.md`. If Claude fails the SDK path its adapter falls back to the CLI headless (`claude -p --output-format stream-json`) and then to a terminal pane; if Codex fails, it drops out of the epic, which still closes with Claude.

The session runs as the user: the agent's environment is the host's own, with the user's `CLAUDE_CONFIG_DIR` / `CODEX_HOME` and `gh` login, and no token is minted or injected. The binary is the `command` of the agent in the config, else the one found on the path.

Permissions are the provider's. The adapter lists the provider's own options with their values and the current one, the person picks them per session, and a session the person gave no options starts with the provider's default; Carrier adds no policy and no bypass rule. When the agent asks for approval the host turns it into a chat event with the provider's own choices, keeps it pending while no client is attached, and passes the chosen answer back.

### The record

Sessions and transcripts live in `chat.db`. A session has an id, the agent's name and harness, the folder, a title (the first line of the first message, cut at 80 characters), the options it runs with, the provider's native session id, its state (working, waiting for an approval, or idle), the recorded process, when it was created and last active, and whether it is archived. Chat events are stored in order with an autoincrement id that is the cursor of the `events` request. Each finished turn also has a row with the model, its outcome (ok, interrupted, error), its duration, the number of tool calls and the usage the provider reported, kept as the provider gave it, so statistics can be built later without touching the transcripts.

Text is redacted first and then cut, as in [0006](../adr/0006-agent-events-stored-in-sqlite-with-bounded-output.md), but the limits are those of a conversation and not of an epic's log: a message of the person or of the agent keeps up to 64,000 characters, a tool's argument 1,024, and a tool's output the first and last halves of 4,096. A message of the person longer than 64,000 characters is refused when sent, with the reason. A message is stored when it ends; while it is written, the text so far travels in the `events` reply as `streaming` and is not stored, so a crash mid-message loses only that message. Nothing is deleted on a schedule: a session and its transcript go when the person deletes it.

### The socket

`chat.sock` is a 0600 Unix socket in a 0700 folder with newline-delimited JSON, a hello on connect and one reply per request, like the engine's, with a strict allowlist of requests and a `capabilities` list in the hello. Its line cap is 1 MiB, not the engine's 16 KiB, because a pasted spec is a request. The engine's client already connects to a path and reads a hello, so the CLI reuses it; its hello type widens to carry the chat capabilities.

```ts
// requests, all strict objects with a positive integer id
{ cmd: 'agents' }                                          // the configured agents and their binaries
{ cmd: 'list'; archived?: boolean }
{ cmd: 'open'; agent: string; folder: string; options?: Record<string, string> }
{ cmd: 'resume'; sessionId: string }
{ cmd: 'send'; sessionId: string; text: string; command?: string }   // `command` is the id of one the session lists; `text` is then what follows its name and may be empty
{ cmd: 'answer'; sessionId: string; approvalId: string; choiceId: string }
{ cmd: 'interrupt'; sessionId: string }
{ cmd: 'setOption'; sessionId: string; option: string; value: string }
{ cmd: 'agentOptions'; agent: string }   // what an agent offers before a session exists: it is started in a folder of nobody's, read and ended; kept ten minutes
{ cmd: 'close'; sessionId: string }
{ cmd: 'archive'; sessionId: string; archived: boolean }
{ cmd: 'delete'; sessionId: string }
{ cmd: 'events'; sessionId: string; after?: number; limit: number }   // limit 1..200
{ cmd: 'stop' }                                            // the host: close every session and exit
```

The `events` reply carries the events after the cursor, the new cursor, the session's summary, the `streaming` text, the pending approvals, the options with their values and the commands the session lists. There is no push channel: a client polls `events` by cursor, as the app polls the engine, and the terminal client polls every 200 ms. A push channel can be added later behind a capability without changing these requests.

The folder of `open` must be an absolute path to an existing directory and is resolved to its real path. It is refused when it lies inside `<root>/repos` or `<root>/worktrees` or `<root>/orchestrator`: a session never works in the engine's shared clone or in an epic's worktree. A reply that fails names the reason in words and never the provider's or the system's own message when that could carry more than the client should see.

### The client and the config

`carrier chat` is a thin client of that socket, in plain lines and without a full-screen UI. `carrier chat --workspace <folder> [--agent <name>]` opens a conversation and prints the reply as it streams; an approval is asked at the prompt with the provider's choices; `/options` lists the options, `/option <id> <value>` changes one, `/quit` leaves and the session stays. Ctrl+C during a turn interrupts it, at the prompt it leaves. `carrier chat --resume <id>` resumes a session and prints its end of the transcript, `--list` lists the sessions (folder, agent, state, age), `--list --archived` lists the archived ones, `--archive <id>`, `--unarchive <id>` and `--delete <id>` do what they say, and `--stop` stops the host.

A `chat` block in the config lists the agents a session can start with; it is optional, and without it there are two agents, `claude` and `codex`, with the binaries on the path and the provider's defaults. A name is a lowercase word, the harness is `claude` or `codex`, and `command`, `model` and default `options` are optional. An option the adapter does not list is refused when the session opens. `docs/configuration.md` and the JSON Schema change with it.

### What was cut

The chat inside the engine process, for tying conversations to the engine's stop and lock. Reading the providers' own history instead of keeping a transcript, because the list, the search and the statistics would depend on files that differ and change. ACP as the seam, because v2 is alpha and its Claude and Codex agents sit on the same SDK and app-server. A Carrier policy for permissions or for `gh pr merge`, because the provider's own system decides what the agent may do and what the person approves. An on/off switch for the terms question, because this is for personal use and nothing is published. A push channel, because polling by cursor is what the engine's socket already does and the terminal client does not need less than 200 ms. Clone, new repository and scratch folders as workspaces, because the picker that chooses them is the next epic's. A watcher process that kills the agents when the host dies, in favour of the sweep at the next start.

## Scope

1. From a terminal, `carrier chat --workspace <folder> --agent claude` opens a conversation with the agent in that folder, starting the host if it is not running, and the reply is printed as it streams.
2. Over several turns the agent remembers the conversation.
3. When the agent asks for approval, the terminal shows the question with the provider's own choices and the answer is honoured, including a decline; if the person leaves while it is pending, it stays pending and can be answered after `--resume`.
4. The person can list the session's options (permission mode, model, reasoning level, whatever the provider offers), change one while the session runs, and a value the provider does not list is refused.
5. Ctrl+C during a turn interrupts it and the session stays open for the next message.
6. A closed session, also after the host ended or died, resumes by its id with the same agent context, and the transcript so far is shown.
7. `--list` shows the sessions with their folder, agent, state and age; a session can be archived, unarchived and deleted from the terminal (`--archive`, `--unarchive`, `--delete`), and a deleted one leaves nothing behind.
8. The same conversation works with Codex through the same port, or the epic closes without Codex if its spike failed.
9. A folder that does not exist, is not a directory, or is inside the engine's clone, worktrees or orchestrator folder is refused with a reason.
10. The host starts with the first chat, closes an idle session with no client after one minute, exits one minute after the last live session and client are gone, and `--stop` ends it at once; stopping or restarting the engine changes none of this.
11. Every message, tool call and approval is stored in the transcript redacted and bounded, and each turn records its model, outcome, duration, tool calls and usage.
12. After a host crash, the next host start ends the agent processes the dead one left and marks those sessions closed and resumable.
13. A developer can test the host, the socket and the client with a fake runner and a temporary SQLite, with no provider installed.
14. The configured agents can be listed, and the `chat` block validates and is documented in `docs/configuration.md`.

## Decisions

Implementation calls follow the Solution above and [0013](../adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md); this is the shape the chat runner has to take, trimmed to the decision. The spike may add to it what the providers force, not remove from it.

```ts
type ChatOption = { id: string; label: string; values: { id: string; label: string; detail?: string; version?: string }[]; current: string };
// What the person can invoke from the message box, whatever the provider calls it. The client lists these and sends one by `id`; how each
// provider is told is the adapter's: Claude reads `/name arguments` in the message, Codex takes a skill item before the text.
type ChatCommand = { id: string; name: string; description: string; argumentHint?: string; kind: 'skill' | 'command' };
type ChatChoice = { id: string; label: string; allow: boolean };
type ChatUsage = Record<string, number>; // as the provider reports it

type ChatEvent =
  | { kind: 'user'; text: string }
  | { kind: 'assistant'; text: string }                       // a finished message
  | { kind: 'delta'; text: string }                           // streaming, never stored
  | { kind: 'tool_start' | 'tool_end'; callId: string; tool: string; arg?: string; output?: string[]; status?: 'ok' | 'err' }
  | { kind: 'approval'; approvalId: string; tool: string; arg?: string; choices: ChatChoice[] }
  | { kind: 'approval_answered'; approvalId: string; choiceId: string }
  | { kind: 'option'; id: string; value: string }
  | { kind: 'turn_end'; outcome: 'ok' | 'interrupted' | 'error'; model?: string; usage?: ChatUsage }
  | { kind: 'error'; text: string };

interface ChatConversation {
  readonly options: ChatOption[];
  readonly commands: ChatCommand[];            // skills and commands to invoke; empty when the provider has none or does not say
  /** The provider's id for this conversation, once it has one. */
  readonly nativeId: string | undefined;
  send(text: string, command?: ChatCommand): void;
  answer(approvalId: string, choiceId: string): void;
  interrupt(): Promise<void>;
  setOption(id: string, value: string): Promise<void>;
  close(): Promise<void>;
  onEvent(listener: (event: ChatEvent) => void): void;
}

interface ChatRunner {
  open(args: { folder: string; resume?: string; options?: Record<string, string>; env: NodeJS.ProcessEnv }): Promise<ChatConversation>;
}
```

The runner's `open` rejects when the provider is not installed, not logged in, or does not know the native id to resume, and the host turns each into a reason a client can show. Adapters keep their own typed parsing and never throw on a line they do not know. The host treats an agent process that ends on its own as the end of the turn if one was running (outcome error) and of the live session otherwise.

The chat socket's request union is its own and strict, in the style of the engine's, with the same hello (`protocol: 1`). The cursor polling choice is a reversible default, which is why it has no ADR.

Testing seams, by story:

- Stories 2, 3, 5, 6, 7, 9, 10, 11, 13: the host through the same interface its socket uses, a request in and a reply out, with a fake chat runner (it plays scripted events, holds approvals and ends on cue) and a temporary SQLite, and an injected clock for the minute rules. This is the broadest seam and carries most of the behaviour. The socket gets its own test in the style of the engine's server test: strict objects, an unknown command, the line cap, the 0600 mode.
- Stories 1 and 4 at the terminal: the `chat` command with scripted input and output streams against an in-process host over a real temporary socket with the fake runner.
- Stories 1, 3, 4, 5, 6, 8 per provider: each adapter replayed against a recording of that provider's real conversation, with only the transport faked, as the harness adapters are tested against their fixtures; the recordings are made by the spike. A gated integration test per provider runs the real tool (`CARRIER_IT_*`, listed in its header) and covers what the recordings cannot: resume, interrupt and the skills.
- Story 9: the folder check as a pure function over real temporary folders, including a symlink into the engine's clone.
- Story 12: the sweep with the process table and the kill injected.
- Story 14: the config's load test for the `chat` block (default agents, unknown harness, bad name, unknown field), and the JSON Schema is regenerated.
- No tests: the spike's findings document.

## Out of scope

The macOS conversation view, the sessions list, archive and search as screens, the workspace picker and the Home page: epics 3 and 4. A link between a session and anything on GitHub, and everything of the solve flow (labels, tickets, who applies `solve:epic:ready`). More providers than Claude and Codex, ACP, images and attachments, checkpoints and revert, forks and switching provider mid-session, plan or subagent views, Take over, mobile and remote, and a web UI. Clone, new repository and scratch folders as workspaces. An automatic cleanup of transcripts and any statistics screen or query beyond what is stored. A `doctor` check for the chat agents' binaries, and making a host started by the app find the user's tools when the app has a minimal `PATH`: that belongs to the epic that starts it from the app. Publishing: the written answer from Anthropic on using a Claude subscription from an app that starts the user's own `claude` is needed before any build with sessions is published, and is not part of building this.

## Open questions

Whether the Claude Agent SDK, used as the research describes it, gives what the spike asks: a permission callback, interrupt, a way to change the model, a way to point it at the user's own binary and to start the process as the leader of its own group, and whether its npm package brings a binary of its own. Settled by the spike against the SDK's reference and a real run.

Whether the user's installed skills (`/sharpen` and the rest) are visible to a session through the SDK and through the Codex app-server. Settled by the spike.

How steady the Codex app-server is for a long conversation, and how it lists the options of a session. Settled by the spike; the epic closes with Claude alone if it fails.
