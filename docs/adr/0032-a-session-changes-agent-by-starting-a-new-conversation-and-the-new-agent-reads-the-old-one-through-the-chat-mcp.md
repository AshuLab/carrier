# 0032 - A session changes agent by starting a new conversation, and the new agent reads the old one through the chat MCP

- Status: accepted
- Date: 2026-11-16

## Context

A session is one conversation with one agent, and [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) splits what each side keeps: the provider keeps the context the model reads, and Carrier keeps the transcript for showing, searching and counting.
A provider's conversation id is worth something only under the login and the harness that wrote it, which is why an epic that changes option rebuilds its session instead of resuming it ([0014](0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md)).
People want to continue a session on another agent: when a quota runs out, to plan with one and build with another, or because the other suits the task.
Today the only way is a new session and an explanation typed again.
The chat does not even tell a usage limit apart from any other error, so nothing says that another agent could take over.
T3 Code does this, and its way is the closest thing to evidence of what works ([research](../research/t3-code-provider-switching.md)).

## Decision

The person changes the agent of a session through a client, and nothing changes it by itself.
The new agent is any configured chat agent, including another account of the same harness; changing only the model of the same agent stays an option change and keeps the native conversation, so it is not a switch.
A switch is only allowed while the session is idle, and it is refused while the session is working, waiting for an approval or preparing.

The session keeps its transcript, folder and worktree, and takes the new agent and harness, forgets its native id and takes the new agent's default options.
The transcript says that the agent changed with a notice.
The new conversation is always a new one, also when the person returns to an agent that the session used before.

Each turn records the harness, the agent and the native conversation that ran it, because the usage history reads them from the session today: it joins each turn to the session's current harness and matches the CLIs' own files by the session's native id (`src/usage/history.ts`), and after a switch the first would put the earlier turns on the wrong harness and the second would count the old conversation twice.

The new conversation carries a handoff, and it travels in the instructions the conversation opens with, Claude's appended system prompt and Codex's `developerInstructions`, and not in front of the person's first message.
Put in front of a command it made Claude's model run the skill itself instead of the harness expanding it, a turn of its own costs one more turn, and instructions cost none ([research](../research/switch-and-delegate-spike.md)).
The handoff holds the first message of the person, the newest messages up to 16,000 bytes counted as UTF-8 bytes on the whole text of the handoff, frame included, the ids of what was left out, and a sentence saying that the chat MCP's `history` tool reads the rest.
The person's new messages are never shortened by it.
The handoff is a selection that Carrier makes of what it stored, not a summary written by an agent, and it carries no reasoning, tool state or attachments.
A message that is longer than what is left is cut, and `history` reads it whole.
The event that stores the person's message holds only what they typed and never the handoff.
`history` never returns reasoning, and a command that the person invoked earlier is shown as the command it was.

The chat MCP gets a read-only `history` tool.
A session reads its own events, paged by position, by kind of view and by item, with a text offset to read one long item in parts.
It is a `readsAsSession` tool and reads the caller's session, the one of the token, unless an optional session id names another one that [0033](0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) allows: a child of the caller or its parent.

The new conversation opens when the person switches, and the old one closes only after the new one has opened with the chat MCP.
A switch is refused when the new conversation could not get the chat MCP, because the handoff would point to a tool that is not there, or when it could not open at all, and then the session stays as it was, on its agent and with its conversation.
The handoff is given when the conversation opens, so nothing waits for the person's next message, and it is given again whenever that conversation is resumed, so it does not matter whether the harness keeps it.
An agent whose configured model the harness does not list is refused at the switch, because both harnesses accept an unknown model when the conversation opens and fail only on the first turn.
A switch holds the session as a delete does, so that a message, a resume or another switch that comes in meanwhile is refused.

A usage limit is classified by the adapters as its own error, apart from a rate limit that the provider retries by itself.
The error says that it is a usage limit and carries the reset time when the provider gives it, and the agent that ran out is the one in the turn's record, so that a client can tell the person to pick another agent.
The adapters classify on a structured field and not on the text: on Claude the failed result's `api_error` of `usage_limit_reached`, with the SDK's `USAGE_LIMIT_ERROR_PREFIXES` as a fallback, and on Codex the `codexErrorInfo` of `usageLimitExceeded` with `willRetry` false.
Claude's reset time is the timestamp of its rate-limit event when there is one and the result's text otherwise, and Codex's comes from `account/rateLimits/read`, because its error does not carry it.

## Alternatives considered

Asking the old agent to compact or summarize before the switch, as a pull request of T3 Code proposed and did not merge.
It spends a turn on the account that may be out of quota, which is the main reason to switch, and it makes the quality of the handoff depend on that agent.

Converting the native history of one harness into the other's.
The formats are private and change with every version, and the agents' own histories are not Carrier's to write.

Resuming the earlier native conversation when the person returns to an agent, with only what happened meanwhile.
T3 Code's design document recommends it.
It needs several native ids per session and rules for when one is stale, and it matters little once delegation exists for the second opinion that goes back and forth.
It can be added later without changing this decision.

Moving by itself when a limit is hit, as an epic's failover does.
It would send the transcript to another provider and spend another account without being asked, the reason 0014 made failover opt-in.

Sending the whole transcript with no tool.
No fixed size fits every context window, and a cut hides what the agent can no longer get back.

A tool and no handoff text.
The agent could answer a message such as "go on" with no context at all.

Choosing the agent on every message.
It adds a choice to each send and a switch to each turn, and nothing asked for it.

## Consequences

The new agent sees text and not the old agent's reasoning, tool calls or attachments, it starts without its prompt cache, and the first turn costs more input.
A long session depends on the agent calling `history` for what the handoff left out, and the handoff carries the newest messages so that a model that does not call it still has something to go on.
With Claude the first use of `history` costs one more call, because it loads an MCP tool through `ToolSearch` first.
The handoff was checked from Claude to Claude and not yet between the two harnesses, and whether a Codex model reads `developerInstructions` is not known.

The `agent` and `harness` of a session stop being fixed.
The list of sessions reads the current agent, and the usage history reads the record of each turn, so a switch moves no earlier turn to the new harness and the old conversation is still matched to the CLI's own files.
The transcript of one session can hold events of several agents, and the notice and the turns' records tell which.
The turns' table gets columns, so there is a migration.

The redacted transcript goes to the other provider, which the person chose by switching.
A harness that stops accepting a per-session MCP breaks the handoff together with the rest of the chat MCP ([0024](0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)).
A resume that finds no conversation and starts over in a session that never switched keeps today's notice and gets no handoff; in a switched session the handoff is given as at any open of that conversation.
