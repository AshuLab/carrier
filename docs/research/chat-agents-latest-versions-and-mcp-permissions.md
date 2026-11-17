# The latest Claude and Codex, and how the chat MCP's tools are approved and timed

> Research of 2026-11-16, for [switch-and-delegate-between-agents](../specs/switch-and-delegate-between-agents.md).
> Sources: Claude's permissions page (read directly), the npm registry, Claude's MCP page and changelog, and the Codex source at tag `rust-v0.169.0` (read by a research agent, not run against a live app-server).
> Nothing in Carrier was changed.

## Short answer

Carrier pins `@anthropic-ai/claude-agent-sdk` 0.3.311 and was last verified on Codex 0.167.2.
The latest stable are SDK 0.3.326 (Claude Code 2.1.326) and Codex 0.169.0, so both are behind by a few releases; the release notes of Claude Code 2.1.326 and of Codex 0.168.0 and 0.169.0, read on 2026-11-17, change nothing about MCP approvals, system prompts, usage-limit signals or the app-server fields that these documents use.
Nothing found changes how a pre-approved MCP tool behaves on either harness.
Both harnesses can ask the person for one tool of an MCP server while the rest stay pre-approved, which is what the spec's delegation needs.
The MCP timeouts are not a constraint for a wait of 45 seconds on either harness.

## Versions

| | In Carrier | Latest stable | Note |
| --- | --- | --- | --- |
| `@anthropic-ai/claude-agent-sdk` | 0.3.311 (pinned in `package.json`) | 0.3.326, 2026-11-16, bundles Claude Code 2.1.326 (0.3.325 of 2026-11-13 bundled 2.1.325) | The SDK runs the person's own `claude` binary, installed here at 2.1.325. |
| `@openai/codex` | 0.167.2 installed, the one [0024](../adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) was verified on | 0.169.0, 2026-11-13 | An alpha, 0.171.0-alpha.8, exists and is not a target. |

The first Codex versions that have each setting we use or want to use:

| Setting under `mcp_servers.<name>` | First version |
| --- | --- |
| `startup_timeout_sec`, `tool_timeout_sec` | 0.40.0 |
| `enabled_tools`, `disabled_tools` | 0.48.0 |
| `tools.<tool>.approval_mode` | 0.117.0 |
| `default_tools_approval_mode` on a server of our own | 0.122.0 |

Before 0.122.0 `default_tools_approval_mode` existed only for Codex's own `codex_apps` server, so 0.122.0 is the floor for [0024](../adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)'s pre-approval.

## Claude: how an MCP tool is approved (read directly from the SDK's permissions page)

The page's order of evaluation is: hooks, deny rules, ask rules, the permission mode, allow rules, and last the `canUseTool` callback.
A call that matches an allow rule, such as an `allowedTools` entry, is approved at the allow step and never reaches `canUseTool`.
`mcp__<server>__*` and `mcp__<server>__<tool>` are valid allow rules, and an entry such as `mcp__*` is ignored.
The page does not say that `plan` mode takes MCP tools away from an allow rule: it names only file edits and `AskUserQuestion` as the calls plan mode sends to the callback.

An allowed MCP tool still asks, or is denied, when one of these holds:

- a deny or ask rule in a settings file the SDK loads matches it, and `settingSources` defaults to all sources, which Carrier does not narrow;
- a hook denies it;
- its server sets `_meta["anthropic/requiresUserInteraction"]` on it (Claude Code 2.1.199 or later);
- it is a claude.ai connector tool that the person's organization set to ask.

In `dontAsk` mode a call that no allow rule approves is denied without calling `canUseTool`.
A tool that is left out of `allowedTools` and has no other rule goes to `canUseTool` in `default` mode, which is where Carrier's approval card already lives.
The SDK emits a process warning, `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED`, when an `allowedTools` entry is a bare tool name while a `canUseTool` is set; it blocks nothing.

## Claude: MCP timeouts (read by an agent from the MCP page and the SDK types)

`MCP_TOOL_TIMEOUT` sets a hard wall-clock limit in milliseconds, and it is about 28 hours when unset.
A `timeout` field on a server's config overrides it; progress notifications do not extend either.
Separately, an idle timeout aborts a call that has no response and no progress: 5 minutes for HTTP, SSE and WebSocket servers, 30 for stdio, and `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` changes it.
A wait of 45 seconds is far below all of them.

## Codex: how an MCP tool is approved and timed (read by an agent in the source at `rust-v0.169.0`)

The approval modes of a server or of one tool are `auto` (the default), `prompt`, `writes` and `approve`, and a per-tool value beats the server's.
In `approve` mode the call is approved with no request, whatever the thread's `approvalPolicy` and sandbox.
In `prompt` mode it always asks, and in `auto` it asks unless the tool's `readOnlyHint` is true or it is marked destructive or open-world.
When it asks, `never` denies the call with "approval policy is never", and the other policies make the app-server send `mcpServer/elicitation/request` for the thread, turn and server.
The client answers `accept`, `decline` or `cancel`, and an accept can carry keys in `_meta` that persist it for the session or for always; Carrier's adapter uses none of that, and its approval choices today are those of a command.
Since 0.167.0 the approval's metadata carries the tool's name and its annotation hints.
Since 0.148.0 a strict auto-review can override `approve` and force a review, and an approvals reviewer can take the request.

`tool_timeout_sec` is 300 seconds in the source (it was 120 at 0.140.0) and `startup_timeout_sec` is 30, while Codex's own documentation page says 60 and 10.
The source is the stronger evidence, and a wait of 45 seconds fits under either figure.
A per-call timeout is combined with the server's by taking the smaller.

## Changelogs, 2026-08-16 to 2026-11-16

Claude Code:

- 2.1.274: a streamable-HTTP MCP call no longer times out at 5 minutes when the server's `timeout` is longer.
- 2.1.299: an MCP allow rule matches only the named server, so `mcp__a` no longer matches a server `a__b`, and `mcp__<server>__*` is the form to write.
- 2.1.310: the error for an MCP call that times out while an elicitation is unanswered changed in a non-interactive session.
- 2.1.323: a session gives a server named in `--allowedTools` at least 2 seconds before the first turn.
- 2.1.325: a headless MCP elicitation is no longer cancelled when a connection is replaced mid-call.

Codex:

- 0.148.0: MCP calls go through the shared approval handling, and a strict auto-review exists for them.
- 0.163.0 and 0.164.0: unanswered elicitations are signalled, and cancellations have distinct reasons.
- 0.166.0: MCP inputs and timeouts are isolated between callers that share a connection.
- 0.167.0: tool names and annotation hints in approval metadata.
- 0.169.0: read-only hints are honoured in automatic approval.

## What it means for Carrier

- Raise the SDK pin to 0.3.326 and test on Codex 0.169.0, and record 0.122.0 as the lowest Codex that honours our pre-approval.
- Keep `mcp__carrier-chat__*` for the read tools, and list them by name instead when one tool of the server must ask.
- A tool that must ask on Codex gets `tools.<name>.approval_mode = "prompt"`, and its elicitation is shown to the person instead of being accepted by the adapter as it is today for the whole server.
- A person's own Claude settings can add ask or deny rules for our tools, because Carrier does not narrow `settingSources`.

## Not verified

- Whether `thread/start.config`, which Carrier uses to inject the server on Codex, merges with the person's own config or replaces it.
- Whether Codex honours MCP progress notifications; the agent found no handling of them.
- Whether Claude's idle timeout applies to in-process SDK servers (Carrier's is an HTTP server, so it does not matter here).
- Whether `plan` mode sends an allowed MCP tool to the callback; the page implies it does not.
- The Codex figures were read in the source and not run against an app-server.
