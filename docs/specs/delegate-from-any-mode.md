# A session delegates to other agents in any mode

Status: spec
Source: AshuLab/carrier#1129

## Problem

A person in a chat session says "launch two agents, one on this model and one on that", and in Claude's `auto` mode the agent answers that it cannot: the mode does not ask before a change, and delegation needs `default` or `acceptEdits`.
The same rule shuts out Claude's `dontAsk` and `plan` and Codex's policy `never`.
The cause is [0033](../adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md), which used the harness's own approval of each `delegate_start` as the person's consent, and offered delegation only where the harness asks.
The person does not want to be asked: saying it in words is the request, and the agent must be able to call the chat MCP in whatever mode the session is in.
We know it is fixed when a session in any mode starts child sessions on request, with no refusal and no approval card, and each child runs at the permissions of its parent.

## Solution

[0036](../adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md) records the decision and amends 0033; this is how it is built.

**No refusal by mode.**
Every session with no parent receives the `act` capability when its conversation opens, whatever its mode, so `delegate_start` and `delegate_wait` are listed to it and `agents` no longer says that the mode does not ask.
`delegationRefusal` keeps what the mechanism cannot do: a session whose options are off the scale (a mode that the scale does not place yet, as 0033 requires), a harness that is neither Claude nor Codex, and a Codex app-server that is unknown or older than the floor.
The check stays in both places where 0033 put it, when the tools are listed and when one is called.

**No approval.**
`delegate_start` is pre-approved like the tools that read.
The adapters are told the names of every tool of the chat MCP and not only the ones that read.
On Claude they go in `allowedTools`, which is what T3 Code does with a wildcard ([research](../research/t3-code-provider-switching.md)), and the adapter's `canUseTool` allows them in the modes that ask for every tool of a server.
On Codex each gets `approval_mode = "approve"`, which ran under every policy including `never` in the spike.
What 0033 built for the approval of `delegate_start` goes: its card with the agent, model, level and task, the allowance for the session on both harnesses, and the elicitation that the Codex adapter showed instead of accepting.
A child's token has no `act`, so a child that is told the tool's name still cannot call it.

**A child at its parent's level.**
The scale of `levels.ts` has four levels, and every option of the chat that does not need `bypassPermissions` or `danger-full-access` sits on it:

| Level | Claude | Codex |
| --- | --- | --- |
| 0 | `dontAsk`, `plan` | `read-only` with any policy |
| 1 | `default` | `workspace-write` with `untrusted` |
| 2 | `acceptEdits` | `workspace-write` with `on-request` or `never` |
| 3 | `auto` | none |

`childOptions` keeps its rule: the options of the child's own agent, lowered to the broadest option of its harness that is at or under the parent's level, never raised.
A harness that has no option at a level (Codex at 3) takes its broadest one below it, so a Codex child of an `auto` parent runs at level 2.
An agent whose own options are off the scale is not honoured and gets the parent's level, as 0033 has it.
The level of the parent is read from its options at the moment `delegate_start` is called, so a mode changed during the session counts.
`agents` says the level each agent would have as a child, and the description of `delegate_start` tells the agent to delegate only when the person asked.

**What the person sees.**
Nothing new: the child is listed in its parent's summary with its agent, state and level, and the approvals of a child that runs at a level that asks still reach the person as they do now.

**Docs.**
The spec of [switch and delegate](switch-and-delegate-between-agents.md), `src/chat/AGENTS.md` and any text that says a delegation asks or that some modes cannot delegate are brought to 0036, and the changelog gets a line under Unreleased.

## Scope

1. A session in Claude `auto`, `dontAsk` or `plan`, or on a Codex thread with the policy `never`, is listed the delegation tools and `agents` says nothing of its mode.
2. In any mode, `delegate_start` starts the child with no approval, on Claude and on Codex.
3. A child runs at the level of its parent: read-only for a parent at 0, the parent's own level for 1 and 2, and for a parent in `auto` a Claude child in `auto` and a Codex child at 2.
4. A parent's level is read again at each call, and an agent's own options are lowered to it, never raised.
5. A session whose options are off the scale, or a child, still cannot delegate, and says why.
6. `agents` shows the level each agent would have as a child, and the tool's description says to delegate only when the person asked.
7. The docs, the glossary and the changelog say that a delegation asks no one and that a child follows its parent.

## Decisions

- The scale and the mapping of a child's options are `levels.ts` and nothing else; no new module.
- The pre-approved tools are all the tools of the chat MCP, which replaces the list of those that only read, because a list of the ones that read would have to name `delegate_start` as the exception 0033 made.
- Level 3 exists only for Claude's `auto`; a harness with nothing there steps down, as it already does when its agent is above the parent.
- A mode the scale does not place is still refused, so a new mode of a harness has to be put on the scale before a session in it can delegate.
- The approval of `delegate_start`, and the tests that pin it, are deleted and not left behind a flag.

Testing seams, by story:
- 1 and 5: `mcp.test.ts`, listing and calling the tools through the MCP server with a fake sessions view, plus the table of `delegationRefusal` in `levels.test.ts`; the broadest seam is the listing, which is what the agent sees.
- 2: `claude.test.ts` and `codex.test.ts`, on what each adapter hands the harness: `delegate_start` in `allowedTools`, and its `approval_mode` of `approve`; the existing test of the approval card is replaced by one that no card arrives.
- 3 and 4: `levels.test.ts`, whose table of levels and the test of every pair across both harnesses already pin `childOptions`; it grows to four levels and the Codex step-down; and `sessions.test.ts` through `delegation()` and `mcpView`, for a parent in each mode and the options its child opens with.
- 6: `mcp.test.ts` for the description and the output of `agents`, with an inline snapshot.
- 7: no tests; `pnpm typecheck` and a read of the docs for the words "asks" and "approval" next to delegation.
- No integration test is added: the real-harness run of `plan` is the open question below.

## Out of scope

- A setting to turn delegation off, or to list the agents allowed to receive one: the person wants it to work, and [0033](../adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) already turned the list down.
- Proof that the person asked, such as reading their last message: the host cannot judge intent, and the tool's description says to delegate only when asked.
- Claude's `bypassPermissions` and Codex's `danger-full-access`: they are not options of the chat, and the issue's "full" modes cannot happen there.
- Recursion, a message to a child, a worktree for each child, waking the parent: as 0033 leaves them.
- How a client shows a child's approvals.

## Open questions

- Does a pre-approved `delegate_start` run in Claude's `plan` mode?
  The spike's model refused to call a tool there, so a probe with a real model decides whether `plan` needs more than `allowedTools` and `canUseTool`; it belongs to the slice that does story 2.
