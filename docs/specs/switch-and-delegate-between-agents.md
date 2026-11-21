# A session can change agent and hand work to other agents

Status: spec; [0036](../adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md) and the spec of [delegating from any mode](delegate-from-any-mode.md) amend what it says of who may delegate, of the approval of `delegate_start` and of the scale of levels.

## Problem

A person who works in a chat session is tied to the agent they opened it with.
When that agent's quota runs out, the work stops: they open a new session with another agent and explain it again, or copy text from one to the other.
The chat does not tell a usage limit apart from any other failure, so nothing says that another agent could go on.

They also cannot use another provider's agent from the session they are in.
A second opinion, two tries of the same task on two models, or a topic kept apart from the conversation all mean leaving the session and starting another.

The owner uses Claude and Codex, on more than one account, and wants all of these cheap: continue after a quota runs out, plan with one agent and build with another, try the one that suits a task, ask another provider for a second opinion, and split a topic off.
[chat-host](chat-host.md) left switching provider mid-session out of its first epic, deferred and not refused.

This spec is the support of the chat host and nothing of the screens.
We know it is solved when the host can switch a session to another configured agent and the next message goes on with that agent knowing what came before; when it tells a usage limit apart, naming the agent and the reset time, so that any client can offer another agent; and when a session's agent, asked by the person, can start two child sessions on two models and a client can read their state and result.
The screens that show all of this are another piece of work, and the host leaves the data ready for them.

## Solution

There are two capabilities.
An agent switch changes who holds the session, and a delegation keeps the session where it is and starts others beside it.
T3 Code makes the same split, and its own release notes recommend delegation over a switch for combining harnesses ([research](../research/t3-code-provider-switching.md)).
The decisions and the alternatives that lost are in [0032](../adr/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md) for the switch and [0033](../adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) for the delegation, and what a spike found about both is in [the spike's findings](../research/switch-and-delegate-spike.md).

**Agent switch.**
A client asks the host to switch a session to another configured agent, between turns only, and any configured agent will do, including another account of the same harness.
The session keeps its transcript, folder and worktree and starts a new native conversation with the new agent, always, also when it returns to one it used before.
The new conversation carries a handoff in the instructions it opens with, and not in front of the person's first message: the person's first message, the newest messages up to 16,000 bytes counted on the whole text, the ids of what was left out and a pointer to a `history` tool in the chat MCP that reads the rest.
A handoff in front of a command or a skill made Claude's model run it itself instead of the harness expanding it, and in the instructions it cost no extra turn and the command ran as a command.
Handed to a new Claude conversation it answered 6 of 6 questions about the earlier one, 3 of them only through `history`, and 0 of 6 without it.
The handoff is a selection and not an agent-written summary, because asking the old agent to summarize spends a turn on the account that may be out of quota.
Reasoning, tool state and attachments do not carry over, and a notice in the transcript says that the agent changed.
Each turn records the harness, the agent and the native conversation that ran it, because the usage history would otherwise put the earlier turns on the new harness and count the old conversation twice.
The new conversation opens at the switch, the old one closes only after the new one opened with the chat MCP, and a switch is refused, leaving the session as it was, when the new conversation could not get the MCP or could not open.
The handoff is given again whenever that conversation is opened or resumed: Claude's SDK records the first system prompt and ignores a later one, which makes it harmless, and where it does not record it the handoff is what carries it.
A switch holds the session against a message or a resume that comes in meanwhile.
An agent whose configured model the harness does not list is refused at the switch, because both harnesses accept an unknown model when they open and fail only on the first turn.

**Usage limit.**
The Claude and Codex adapters classify a usage limit as its own error and keep it apart from a rate limit that the provider retries by itself.
The chat reports it as its own kind of error, which carries the reset time when the provider gives it, so that a client can tell the person to pick another agent.
Nothing moves by itself: the person triggers the switch.
Neither adapter classifies it today: a usage limit and a retried rate limit come out as the same `error` with text.
The signal to classify on is a structured field and not the text: on Claude the failed result's `api_error` of `usage_limit_reached`, which is marked internal in the CLI, with the SDK's `USAGE_LIMIT_ERROR_PREFIXES` as a fallback, and on Codex the `codexErrorInfo` of `usageLimitExceeded` with `willRetry` false, which a real limit produced.
On Claude the reset time is the timestamp of the rate-limit event when the turn had one and the result's text otherwise.
On Codex the adapter asks `account/rateLimits/read` for it as soon as the limit arrives, and falls back to the error's text when that fails; the text has a curly apostrophe, which a match on it must take into account.

**Delegation.**
In a session the person says what they want, such as two agents on two models, and the agent turns it into calls of the chat MCP.
Saying so is the request: `delegate_start` asks the person nothing, in any mode, and it is offered to every session that has no parent and whose harness is new enough.
A child is a real session hanging from its parent: its own agent and options, the parent's folder, not in the list of sessions, archived and deleted with the parent.
It runs one task and takes no message from the person, and the host refuses one sent to it; a client can read its events as they come, the person can answer its approvals and questions, and to correct it they delegate again.
Nothing is recursive, because only a session without a parent gets the `act` capability that the MCP already has for a tool that changes something, and a parent has at most four children running.
A child never has more privilege than its parent: Carrier ranks what a session may do on a scale, reads the parent's level when the delegation starts, and lowers the options of the child's own agent to it when they are above, never raising them.

| Level | The session | Claude | Codex |
| --- | --- | --- | --- |
| 0 | reads and changes nothing | `dontAsk`, `plan` | sandbox `read-only` |
| 1 | changes, and asks before each change | `default` | `workspace-write` with `untrusted` |
| 2 | edits without asking | `acceptEdits` | `workspace-write` with `on-request` or `never` |
| 3 | acts with no check | `auto` | none |

Every mode is on the scale, so a session in any of them can delegate; the scale only decides what the child may do.
A level of Codex is a pair of sandbox and approval policy: `read-only` is level 0 whatever the policy, and `workspace-write` is level 1 with `untrusted` and level 2 with `on-request` or `never`.
A parent in `auto` has a Claude child in `auto` and a Codex child at level 2, the broadest Codex has.
A child runs at the lower of the level of its own agent's options and the parent's level, with the options of its own harness at that level, so it is never raised.
An agent that sets no permission option (`permissionMode` for Claude, `sandbox` or `approvalPolicy` for Codex; the model and the effort are not one) has no level of its own to cap it: its child runs at the parent's level, which for Codex is at most 2.
The adapter's default is not a choice the person made, so it is not taken for one; an agent configured with `default` keeps level 1.
A child belongs to the parent session and not to the agent that holds it, so the parent can be switched, or closed and resumed, and still wait for its children.
The list of sessions leaves children out, and the clock that archives and deletes sessions ages a parent and its children as one.

**What the agents get.**
Four tools under the existing `carrier-chat` server, which already names them as `mcp__carrier-chat__<tool>`, so none needs a prefix of its own.

| Tool | What it does | Access |
| --- | --- | --- |
| `history` | Reads events of its own session, of its children if it is a parent, or of its parent if it is a child; paged by position, by view (messages or activity), and by item with a text offset for a long one. | `readsAsSession`, pre-approved |
| `agents` | Lists the configured agents with their state, the level each would have as a child of the caller and, when asked, their models and reasoning levels. | `readsAsSession`, pre-approved |
| `delegate_start` | Takes an agent, a task, an optional model and a request id so that a retry does not start a second child; answers at once with the child's id. | `actsAsSession`, pre-approved |
| `delegate_wait` | Takes child ids and a timeout of at most 45 seconds; answers each child's state (working, needs approval, done with its final message, error, usage limit, interrupted). | `readsAsSession`, pre-approved |

`capabilities` stays as it is.

**What the host leaves ready to show.**
The summary of a session says which session is its parent, and the summary of a parent lists its children with their agent, harness, state and permission level and says whether one of them waits for the person.
A client reads a child's events, as it reads any session's, with the `events` request, and answers its approvals with `answer`.
The transcript holds the notice of each agent switch, and each turn says which harness and agent ran it.
The `error` event says that it is a usage limit and when it resets.
How a client shows any of it is not decided here: the picker, the message about a limit, the cards and avatars of children, what opening a child shows and the indicator on a parent's row are another brief's.

**Order.**
The preparation comes first: the SDK raised to 0.3.326 and Codex tested on 0.169.0, with 0.122.0 as the lowest Codex that honours the pre-approval.
The usage-limit classification and `history` come next, the switch after them because the handoff points to `history`, and the delegation last.
The Codex adapter pins the app-server it was recorded against at 0.153.4 (`CODEX_APP_SERVER_VERSION`), and moving it means recording its transcripts again.

## Scope

1. As the maintainer, I find the chat on the latest Claude SDK and Codex, with the checks that the spike made on permissions repeated there and passing, so that everything below stands on current versions, and the Codex adapter's pinned app-server version and its recorded transcripts move with them.
2. As a client of the host, when a Claude turn ends in a usage limit I receive an `error` that says so and when it resets, and a rate limit that Claude retries does not become one; the limit comes out as one `error` and no `assistant` message.
3. As a client of the host, when a Codex turn ends in a usage limit I receive the same, with the reset time read from the account's limits, and a rate limit that Codex retries does not become one.
4. As a person, I can switch an idle session to another configured agent, including another account of the same harness, and the session keeps its transcript and folder and goes on with that agent; a switch that cannot be done says why and leaves the session as it was.
5. As the new agent of a switched session, I start with a handoff in my instructions that holds the first message, the newest messages up to the budget, the ids of what was left out and where to read them, and a command that opens my first message still runs as a command.
6. As an agent, I can read the history of my session with `history`, paged, by view and by item, and never see reasoning.
7. As the person who reads the usage history, I find each turn on the harness and conversation that ran it after a switch, with the old conversation counted once.
8. As a person in the terminal, I can switch the agent of the session I am in with `carrier chat`, which checks first that the host announces the capability.
9. As the macOS app, I see the `switchAgent` capability and decode its reply and the new fields of a session and of an event, with no screen using them.
10. As an agent in a session that may delegate, I can list the configured agents with `agents`, with their state, the level each would have as my child and their models when I ask.
11. As a person, when I ask my agent to launch other agents, a child session starts and receives the task, with no approval to give first.
12. As an agent, I can wait for my children with `delegate_wait` and learn the state of each and the final message of the ones that are done.
13. As a person, a child never has more privilege than its parent, and a parent whose options are off the scale cannot delegate.
14. As a person, a child cannot delegate and takes no message, and it can read its parent's history.
15. As a client of the host, I find a child from its parent with its agent, state and level, read its events and answer its approvals, and the list of sessions leaves children out.
16. As a person, archiving, deleting and the clock treat a parent and its children as one, and never remove a folder while a child works in it.
17. As the maintainer, I know how a real Codex model behaves with the handoff and with a refused tool, once the account has quota again; the maintainer owns it, and it runs after 2026-11-20.

## Decisions

The switch is decided in [0032](../adr/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md), the delegation and the scale in [0033](../adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) as [0036](../adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md) amends it, and what this section adds is how they are built.
No config key is added: the 16,000 bytes, the four children and the 45 seconds are constants, so `docs/configuration.md` does not change.

**Data.**
`sessions` gets a nullable `parentSessionId` that references `sessions.id` and a nullable `delegationRequestId`, with a unique index on the two together, so that a retried `delegate_start` returns the same child and the memory of it survives a restart of the host.
`chat_turns` gets nullable `harness`, `agent` and `nativeId`, and the migration fills them for the rows that exist from the session row, so that the code reads the columns and keeps no fallback; the usage history joins on the turn's own values.
All of it is in `src/chat/schema.ts`, and the migration is generated with `pnpm db:generate` and has the backfill written into it as SQL, because the generated one does not fill the new columns.
`summary` leaves `delegationRequestId` out.
The usage history builds the pairs of harness and native conversation that match a session to the CLIs' own files from the turns and not from the session's current `nativeId`, which a switch replaces.

**Events.**
The events are the shared language of the adapters, the host and the stored transcript, so their new fields are part of the contract:

```ts
| { kind: 'error'; text: string; reason?: 'usage_limit'; resetsAt?: number /* ms since epoch */; resetText?: string }
| { kind: 'notice'; text: string; lostNativeId?: string; switched?: { from: string; to: string } }
| { kind: 'approval'; approvalId: string; tool: string; arg?: string; choices: ChatChoice[]; questions?: ChatQuestion[] }

type ChildState = 'working' | 'needs_approval' | 'done' | 'error' | 'usage_limit' | 'interrupted';
type ChildReport = { childId: string; agent: string; state: ChildState; message?: string; waitingFor?: { tool: string; arg?: string }[] };
```

`boundEvent` in `src/chat/transcript.ts` keeps only `text` for an `error` today, so it has to keep `reason`, `resetsAt` and `resetText` (the last one cut like the rest), or a usage limit is lost when it is stored.
`switched` names the agents as the config does.
`resetsAt` is a number in milliseconds and `resetText` is the provider's own words, and an event has one, the other or neither.

**The handoff.**
A pure function builds it from the stored events of the session up to the switch: the first message of the person always, then the newest user and assistant messages walking backwards while the whole text, the frame included, stays within 16,000 UTF-8 bytes, a message that does not fit cut at the budget without splitting a character, then the ids of the messages left out, which are their positions, and the sentence that points to `history`.
A session with no message has no handoff and the switch sends none.
`ChatRunner.open` takes `instructions` for it, which the Claude adapter passes as the SDK's `systemPrompt` of `preset` `claude_code` with `append`, and the Codex adapter as `developerInstructions` of `thread/start` and `thread/resume`.
The host rebuilds it from the events before the switch notice every time it opens or resumes a conversation that a switch started, and passes it again.

**`history`.**
`history` takes an optional `sessionId`, which must be the caller's own, one of its children or its parent and is refused otherwise, a `view` of messages or activity, an `afterPosition` that starts at the beginning when it is -1, a `limit` of at most 100 events, and an `itemId` with a `textOffset` to read one item in parts.
An item's id is the position of its event, a list cuts each item's text to 1,500 characters and says which ids to read whole, and an item is read in parts of 4,000 characters with the offset of the next part or null.
Reasoning is never returned, the activity view lists a tool call as one line with its name, argument and status and no output, and a command that the person invoked is shown as the command.
An item id is checked to belong to the session being read, whichever session the caller names, the view filters before the limit, and `nextPosition` is the position of the last event scanned.

**The limit.**
On Codex the adapter emits the `error` of a usage limit only after it asked `account/rateLimits/read` or two seconds passed, so that the error keeps its place before the end of the turn, and it takes the reset of the window that is at 100% and resets last, or the error's text when none is.
On Claude it takes the reset from the `rate_limit_info` of the synthetic message when it has one and from the result's text otherwise.
The agent that ran out is the one in the turn's record, and the event does not carry it.

**The models.**
The model of an agent, whether configured or asked for, is checked against what its harness lists, which the host gets from the option probe that `agentOptions` runs, a short-lived process of the CLI that gets no MCP, and keeps for ten minutes.
Claude adds an unknown id to its list when a conversation opens, so a check against the opened conversation does not catch it, and the switch and `delegate_start` use the probe's list; a probe that fails refuses the call with words.

**The scale.**
A pure module holds it as data: it gives the level of a harness's options, `undefined` for what is off the scale, and the options of a harness that are at or under a level for the child's own agent options, which are the agent's configured ones or the adapter's defaults.
An agent whose options are off the scale is lowered to the broadest option of its harness at or under the parent's level, which always exists because level 0 does.

**Requests on a session that has a parent or that switches.**
A child is refused `send`, `resume`, `archive`, `delete`, `rename`, `setOption` and `switchAgent`, with words that say that it belongs to its parent, while `interrupt`, `close`, `answer` and `events` work on it as on any session, and the host's own first message to a child does not go through `send`.
Refusing `setOption` is what keeps a child's level from being raised, and a child's approvals offer Allow and Deny and none of the suggestions that change the mode, add folders or write rules, so nothing raises it from inside either.
A switch is refused for an archived session, for one whose preparation did not finish, for the agent that the session already has and for a child, while a closed session can be switched and then has no old conversation to close.
A switch marks the session as switching, a marker of its own and not the delete's, which every request that touches the session checks, and when the new conversation attaches the old one is detached, so that its events are no longer recorded, while its process stays recorded until it ends, so that a host that dies in between can still sweep it.

**Who may delegate.**
The token gets `act` when its session has no parent, and the delegation tools are listed and callable only while the session's current options are on the scale, in any mode, and the harness is new enough; the Codex adapter exposes the app-server's version for this, and 0.122.0 is the floor.
The options are checked when the tools are listed and again when one is called, because the person can change the mode during the session and the agent lists the tools only when it starts; the check on the call is the one that holds, and a call that is not offered fails with words that say why.
The adapters are told by name which tools of the chat MCP there are, when the conversation opens, and the Codex adapter exposes the version of its app-server.
`agents` says the same reason for the caller.
The child's folder is the parent's, recorded as a plain folder, and a child is counted as running while it works or waits for an approval, so a fifth `delegate_start` is refused with words while four are.
The slot and the request id are reserved before the conversation opens: the child's row is inserted first, counts toward the four and is deleted if the open fails, and a repeated request id returns the existing child whatever the other arguments, checked before the cap, so that a retry with four running gets its child back.
The parent's existence is checked again once the child's conversation has opened, as `resume` does.

**Approvals.**
This is what [0036](../adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md) changed: no tool of the chat MCP asks the person, `delegate_start` included.
On Claude `allowedTools` lists each tool of the chat MCP by name and not the wildcard, and in `plan`, which asks for every tool of a server whatever `allowedTools` says, the adapter's `canUseTool` allows the chat MCP's tools.
On Codex the server's default is `auto` and each tool is `approve`, so no elicitation reaches the person.
The host cannot prove that the person asked: the token of a Claude conversation sits in the environment of its process, so an agent that is allowed to run a shell command could post `delegate_start` itself, as it could start `claude` or `codex` itself.
The tool's description tells the agent to delegate only when the person asked, which is advice and not a check, and the spec accepts that and adds no proof to the MCP.
The approvals of a child that runs at a level that asks are its own, and they reach the person as before.

**`delegate_start` and `delegate_wait`.**
`delegate_start` takes `agent`, `task` of up to `chatCaps.message` characters, an optional `model` and an optional `requestId`; it opens the child, sends it the task as its first message and answers with its id as soon as that is done, and it fails with words when the agent is not configured, not found or signed out, when the model is not one it lists, when four children are running or when the session's options are off the scale.
`delegate_wait` takes between one and four child ids of the caller and a timeout that defaults to 30 seconds and is at most 45, and answers as soon as no child is working, counting a child that waits for an approval as stopped, or when the time ends.
A child is `needs_approval` while its session waits for an approval, and then `waitingFor` lists up to four of them, each the tool and its command as the host stored it (redacted) cut to 500 characters, so the parent can tell the person what is held; when it is idle it is `usage_limit` if its last error says so, `error` for another error, `interrupted` after an interrupt and `done` otherwise, with its last assistant message cut to 4,000 characters.
A child whose last turn never ended, because it was closed or its process died in the middle, is `interrupted`.
`agent` and `model` are bounded names, `requestId` has at most 64 characters, and a child id that is not the caller's is refused with the same words as one that does not exist.

**Sessions, the list and the clock.**
The `list` request leaves out the sessions that have a parent, and the summary of a parent lists its children and says whether one waits for the person.
Archiving a parent closes its idle children and is refused while one works, and deleting a parent first settles its children, closing the idle ones and refusing while one works, then removes the worktree, then deletes the children and the parent in one transaction, which `deletePreview` shows.
`applyClock` and the `deleteAt` and `kept` of the `list` reply treat the family as one: its activity is the latest of the parent's and the children's and it is live when any of them is, which covers a child that works under a parent that was closed for being idle.
A child session is never in the preparing state, and it is never archived or deleted by itself.

**The request.**
`switchAgent` takes a session and an agent, answers what `resume` answers, `{ session, options }`, refuses with the words of a `ChatRefused`, and goes through every step of the checklist in `src/control/AGENTS.md`: the `chatRequest` entry, both the `ChatCapability` and the `capabilities` array, `ChatControls` and `run()`, the golden reply (the chat's are written by hand), `capabilities.json`, and on the Swift side only the capability case, the request and reply types, the fixture server and their tests.
The new fields of a session and of an event are decoded by the Swift types without a screen using them.
The terminal client gets `/agent <name>` in `carrier chat`, which checks that the host announces `switchAgent` first, and `docs/cli.md` says it.

**Docs.**
`src/chat/AGENTS.md` lists the new files and what each does, `src/usage/AGENTS.md` and [usage-and-limits](usage-and-limits.md) say that the history reads each turn's own harness and conversation, the `--fixture` paragraph of `macos/README.md` says what the fixture server answers, the specs index notes that the exclusion of a tool that sees another session in [chat-mcp-engine](chat-mcp-engine.md) is lifted here in part, and `CHANGELOG.md` says what a person gets.

**Testing seams.**
The broadest seam for what a session does is `src/chat/sessions.test.ts`, with `FakeChatRunner`, `FakeClock`, `FakeGit` and a temporary SQLite, and `FakeChatRunner` records the `instructions` and the `options` it was opened with and learns to fail the nth open, which the refusals of a switch need.
The MCP tools and the listing of tools are tested through the real server and registry of `src/chat/mcp.test.ts` with a fake `McpSessions`, the adapters through the replays of `claude.test.ts` and `codex.test.ts` with their fake transports, and the socket through `src/chat/server.test.ts`; a message or a resume that comes in during a switch is tested through `createSessions` itself, whose calls interleave, because a socket serializes the requests of one connection.

| Story | Where it is tested |
| --- | --- |
| 1 | No new test: `pnpm typecheck` and `pnpm test` pass, the gated integration tests of both adapters pass on the new versions, and the spike's scripts of parts A and B, kept in `docs/research/spike-switch-and-delegate/`, are run again. |
| 2 | `claude.test.ts`, with the fake `query` fed a failed result with `usage_limit_reached`, a retried 429 and the real fixture, asserting the events; `transcript.test.ts` for `boundEvent` keeping the new fields. |
| 3 | `codex.test.ts`, with the fake transport fed a recording of the real limit, a retried `rateLimitExceeded` and an answer of `account/rateLimits/read`, asserting the events, including the curly apostrophe. |
| 4 | `sessions.test.ts`: the switch, each refusal (working, waiting for an approval, preparing, unknown agent, unlisted model, no MCP, a conversation that does not open, which leaves the old one), a message or resume during the switch, and the notice; `server.test.ts` for the request. |
| 5 | A unit test of the pure handoff (empty, one message over the budget, a multibyte character at the cut, exactly at the budget, nothing left out); `sessions.test.ts` for `instructions` on open and on every resume; `claude.test.ts` and `codex.test.ts` for how each adapter passes them; the gated integration tests with a skill, as the spike's part C did. |
| 6 | `mcp.test.ts` for `history`: paging, both views, an item in parts, no reasoning, and the relations that are allowed and refused. |
| 7 | `src/usage/history.test.ts` for a switched session; `db.test.ts` for the migration filling the new columns. |
| 8 | `src/terminal/cli/commands/chat.test.ts`. |
| 9 | `server.test.ts` (the hello lists), `replies.test.ts` (the golden reply), `capabilities-contract.test.ts`, and the Swift `ContractTests`, `ChatHostTests`, `RepliesTests` and `FixtureServerTests`. |
| 10 | `mcp.test.ts` for `agents`, and a unit test of the scale. |
| 11 | `sessions.test.ts` for the child that starts, the request id that returns the same one, each refusal and the mode checked again on the call; `mcp.test.ts` for the listing; `claude.test.ts` and `codex.test.ts` for what each adapter hands the harness so that `delegate_start` asks no one; the gated integration tests for a real run. |
| 12 | `sessions.test.ts` and `mcp.test.ts` with `FakeClock`, for each state and for the timeout. |
| 13 | A unit test of the scale that crosses both harnesses, the four levels and agents with options on and off the scale, and `sessions.test.ts` asserting the options a child was opened with. |
| 14 | `mcp.test.ts` for a child's token that lists no delegation tool and for the refused call, and `sessions.test.ts` for the message that a child refuses. |
| 15 | `sessions.test.ts` for the list, the parent's summary, `events` and `answer` on a child, and the golden replies. |
| 16 | `sessions.test.ts` and `sweep.test.ts` for archive, delete and the clock over a family, and for the refusal while a child works. |
| 17 | No unit test: gated integration tests on the real Codex after 2026-11-20, which the spike's scripts of parts B and C start from. |

## Out of scope

Failover by itself in the chat, and anything that moves a session without the person's say.
Resuming the earlier native conversation of an agent that the session returns to, and a handoff for a resume that finds no conversation in a session that never switched, which keeps today's notice; the lost conversation of a switched session gets the handoff like any open of it.
A summary of the session written by an agent, and the conversion of one harness's native history into another's.
Choosing the agent on every message, and queueing a switch while the agent is working.
A worktree of its own for a child, and a way to merge it back.
Raising the level of a child after it started.
Waking a parent when a child ends, a `delegate_send` or a `delegate_cancel` tool, and a child that delegates.
Antigravity as a chat agent, which `chatAccount` refuses today.
Connecting a session to an epic, which [0012](../adr/0012-sessions-and-epics-are-two-separate-worlds.md) keeps apart.
Every screen of the app: the agent picker, the message about a limit, the cards and avatars of children, what opening a child shows, the indicator on a parent's row, notifications and the marks of the providers.
The host leaves the data for them, and they are another brief.

## Open questions

Does a real Codex model keep a conversation going from a handoff, in both directions between Claude and Codex?
Codex's account is at its usage limit until 2026-11-20 at 7:11 PM, so no real Codex turn ran in the spike: whether a Codex model reads `developerInstructions`, whether it calls `history`, and how it reacts to a refused tool are not known, and the Claude to Claude case is the only one measured.
Story 17 is where it is answered (slice #1044: the adapter is pinned to Codex 0.169.0 and its no-turn messages were checked, but the account was still at its limit, so the real-model checks moved to [#1083](https://github.com/AshuLab/carrier/issues/1083), which runs when a Codex login with quota exists and does not hold this epic), and its result tunes the size of the handoff or how Codex gets it, and does not change the shape of the rest.
