# 0036 - A session delegates in every mode, and a child runs at its parent's permission level

- Status: accepted; amends [0033](0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md): a delegation no longer asks, and the scale of levels covers the modes that never ask
- Date: 2026-11-19

## Context

[0033](0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) offered delegation only where the harness asks the person, because the harness's own approval was the consent for each `delegate_start`.
So a session in Claude's `auto`, `dontAsk` or `plan` mode, or on a Codex thread whose policy is `never`, did not receive the delegation tools, and an agent in `auto` answered that it could not launch another agent ([#1129](https://github.com/AshuLab/carrier/issues/1129)).
The person's call is that saying "launch these agents" in a session is the request, that the agent must be able to call the chat MCP in any mode, and that it must not ask again.
T3 Code's `delegate_task` is the prior art: on Claude it pre-approves its whole MCP with a wildcard in `allowedTools`, except in a read-only sandbox, where it pre-approves only the tools that read, and a child inherits its parent's mode and never has a broader one ([research](../research/t3-code-provider-switching.md)).

## Decision

`delegate_start` is pre-approved in every mode, as the tools that read already are, and the person gets no approval for it.
A session with no parent receives the `act` capability whatever its mode, so the delegation tools are listed to it and `agents` no longer refuses on the mode.
What still refuses is what the mechanism cannot do: a child, which never delegates, and a Codex app-server older than the floor of [0024](0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)'s pre-approval.

A child has the parent's permissions: the options of its own agent, lowered to the broadest option of its harness that is at or under the parent's level, never raised.
That rule is 0033's.
What changes is the scale, which now carries the modes that never ask, so that every session has a level.

| Level | Claude | Codex |
| --- | --- | --- |
| 0 | `dontAsk`, `plan` | sandbox `read-only` with any policy |
| 1 | `default` | `workspace-write` with `untrusted` |
| 2 | `acceptEdits` | `workspace-write` with `on-request` or `never` |
| 3 | `auto` | none |

A parent in `plan` or `dontAsk` has a child that only reads, and a parent in `auto` has a Claude child in `auto` and a Codex child at level 2, the broadest Codex has.
A parent in `default` or `acceptEdits` has a child that asks the person for what the parent would ask, and the person answers those approvals as before.
Claude's `bypassPermissions` and Codex's `danger-full-access` are still not options of the chat, so no level is above 3.

The limit of four children running, no recursion, one task per child, the request id, and the check of the model against what the agent lists stay as 0033 has them.

## Alternatives considered

Carrier asks for the approval of a delegation itself where the harness does not.
It was the first idea in the issue.
The person does not want a question for a request they just made, and it would be a second approval path to build beside the harness's own.

Delegation keeps asking in `default` and `acceptEdits`, where the harness asks, and does not ask elsewhere.
It would leave one rule for each mode, and the person asked for the same behaviour in all of them.

Every child runs in `auto`, so that it is always autonomous.
A parent that asks for every change would then have a child that asks for none, and a parent that only reads would have a child that writes.
The cap at the parent's level is what keeps the chosen mode of the session in charge of what it launches.

A level only for `auto` and nothing for `plan` and `never`.
A child needs a level whatever its parent's mode is, so each mode that never asks has to sit somewhere on the scale.

## Consequences

Nothing stands between an agent and a delegation any more.
An agent that reads hostile text could start a child that carries the conversation and the code to another provider and spends another account, with no approval first, and the host cannot check that the agent obeys the person.
In `auto` the agent could already reach the network, so little is added.
In `dontAsk`, `plan` and Codex `never` the delegation becomes the one way for the conversation to leave, and the cap only limits what the child does, not what it is told.
The person accepts that, and what bounds it is the cap, the four children, and the child listed in its parent's summary.

The tool's description says to delegate only when the person asked, which is advice and not a check.

The person's own Claude settings can still add a rule that denies or asks for the tool, as 0033 says of all of them.

A person who says "launch two agents" from a session in `default` may then answer the questions of those agents, as the approvals of a child already reach them.

Whether a pre-approved `delegate_start` runs in Claude's `plan` mode is not known: in the spike the model refused to call a tool there ([research](../research/switch-and-delegate-spike.md)).
