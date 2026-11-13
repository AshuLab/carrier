# The chat host serves an MCP of its own to the agents of its sessions

Status: spec

## Problem

An agent in a chat session is alone with its own tools: nothing lets it reach back into Carrier. Everything that would extend what the person can do with agents later needs that channel first: delegating a task to another harness or model, reading another session, and in the end connecting a conversation with the solve flow of an epic. Each of those is a capability, and none of them can be built until the host has a way to serve one to an agent without every capability reinventing the server, the credentials, the injection into each harness and the rules about who may call what.

This epic is that channel and nothing else: the engine of the MCP, a first tool that proves it end to end, and the shape every later tool follows. We know it works when, in a real session, an agent lists the tools of the MCP, calls the first one and gets a correct answer, when the credential stops working as soon as the session closes, and when an agent running an epic never sees the MCP at all.

## Solution

The chat host runs an HTTP MCP server, the [chat MCP](../glossary.md), inside its own process on `127.0.0.1` with an ephemeral port (`0`) at `/mcp`. `startChatHost` starts it before opening `chat.sock` and closes it on `stop()` alongside the socket. No new runtime package is required: the server handles JSON-RPC 2.0 over `node:http` (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`, plus `server/discover` and unknown notifications cleanly) and validates inputs with `zod`. The engine (`src/orchestration`, `src/execution`, `src/harnesses`) never imports, starts or passes MCP configuration, keeping [0013](../adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md), [0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) and [0024](../adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) intact.

Every real session receives the MCP on by default, registered under the server key `carrier-chat` so it cannot collide with a `carrier` server the person configured in their own CLI settings. Each live conversation gets a random bearer token (`McpSessionRegistry`), kept only in memory as its SHA-256 hash—never persisted to SQLite, never logged, never passed in CLI `argv` or `ps`, and never written to `~/.claude.json` or `~/.codex/config.toml`. Tokens carry `{ sessionId, invocationId, capabilities, lastAliveAt }`, start with `['read']` today, refresh `lastAliveAt` on valid MCP requests, expire after 24 hours without activity on the injected clock, and are revoked by `invocationId` when the conversation closes, ends or loses a concurrent `resume` race. `sessions.ts` allocates `sessionId` before opening the runner in `open()`, revokes by `invocationId` if `openConversation()` or `checkOption()` throws (across `open`, `prepare`, and `resume`), and passes no MCP configuration for disposable `agentOptions()` probes in `tmpdir()`.

`ChatRunner.open(args)` gains an optional `mcp?: { serverName: string; url: string; token: string }`, and `ChatConversation` gains an optional `readonly mcpProblem?: string`. Claude receives `mcpServers: { [mcp.serverName]: { type: 'http', url: mcp.url, headers: { Authorization: 'Bearer ${CARRIER_MCP_TOKEN}' } } }` with the token in the `env` of its process as `CARRIER_MCP_TOKEN` (the SDK turns `mcpServers` into `--mcp-config` in the `argv` of the process, where any user of the machine can read it; Claude Code expands the variable in the header) and `allowedTools` including `` `mcp__${mcp.serverName}__*` `` in `query({ options })`, and reads `mcpServerStatus()` after `initializationResult()` to set `mcpProblem` if the injected server failed to start (the init reply itself carries no MCP status). Codex receives `"mcp_servers.${mcp.serverName}": { url: mcp.url, http_headers: { Authorization: `Bearer ${mcp.token}` } }` in the `config` of both `thread/start` and `thread/resume` over its stdio pipe, auto-accepts `mcpServer/elicitation/request` (`{ action: 'accept', content: {} }`) only when `params?.serverName === mcp.serverName` (still returning `-32601` for other unknown requests), translates `item.type === 'mcpToolCall'` in `item/started` and `item/completed` into `tool_start` and `tool_end` events so MCP calls count toward `chatTurns.toolCalls` and appear in transcripts, and records `mcpProblem` if `mcpServer/startupStatus/updated` reports a failure or a cancelled start for `mcp.serverName`, waiting up to five seconds after `thread/start` for that notification so `open` returns knowing it, and sets `default_tools_approval_mode: 'approve'` on the injected server so the tools run under every approval policy.

If the HTTP server fails to bind when the host starts, the host logs the error and continues running with no MCP endpoint. Whenever a real session opens or resumes without an MCP endpoint or with `conversation.mcpProblem` set, `sessions.ts` stores a `{ kind: 'notice', text }` event on the session (honoring `runner.ts`'s rule that only the host emits `notice`). A broken MCP never blocks a chat.

Tools live in toolkits under `src/chat/mcp/` (today one file), each defined through `defineTool`, which forces every tool to declare an `access` level (`'reads' | 'readsAsSession' | 'actsAsSession'`). The server checks the bearer token and enforces the declared level before executing any handler. The first toolkit is `capabilities` (`'readsAsSession'`), which takes an empty object (`{}` or omitted arguments) and returns the current session's metadata and live options alongside the configured chat agents and `health()` verdicts (`ready`, `missing`, `signedOut`, `unknown`), never reading `providers()` (which exposes local binary and `configDir` paths) and never spawning `agentOptions()` probes for other harnesses.

## Scope

1. As an agent in a Claude or Codex chat session, I discover the `carrier-chat` HTTP MCP server on both session open and resume without altering the user's CLI configuration or placing the credential in `argv`.
2. As an agent in a Claude or Codex chat session, I invoke `carrier-chat` tools without prompting the user for approval, and every call appears as `tool_start` and `tool_end` events in the session transcript and increments the turn's `toolCalls`.
3. As the chat host, I authenticate `/mcp` requests with per-conversation bearer tokens stored only as SHA-256 hashes in memory, enforce each tool's declared access level before running its handler, expire idle tokens after 24 hours, and revoke tokens cleanly on close, end, open failure, or concurrent resume loss.
4. As an agent in a chat session, I call `capabilities` to read my current session metadata (`id`, `agent`, `harness`, `folder`, `model`, `options`) and the `health()` verdicts for `git`, `gh`, and configured chat agents, with no secrets and no paths of this machine beyond the session's own `folder`, where the agent already runs.
5. As a person using chat, a failure to bind the MCP server or connect to it in a harness still opens the conversation and appends a host `{ kind: 'notice' }` event, while disposable `agentOptions()` probes never receive MCP configuration or mint tokens.
6. As a developer adding future chat MCP tools, I organize them in a toolkit defined through `defineTool`, which refuses a tool without a valid access level; the host owns the list of tools it serves.
7. As a user running Carrier epics, no engine harness (`claude`, `codex`, `agy`) ever receives chat MCP configuration.

## Decisions

The placement in the chat host, per-session injection, pre-approval exception to [0013](../adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md), and isolation from engine agents are settled in [0024](../adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md); folder layout in [0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md).

Mandatory tool access declaration and normalization of `tools/call` arguments (checked against omitted `undefined`, `{}` and wrong-typed payloads: omitted arguments normalize to `{}` so `capabilities` succeeds when a client omits `arguments`, while arrays, strings, or unknown keys like `{ extra: 1 }` fail schema validation and return an MCP tool error; `defineTool` rejects missing or unrecognized `access` at registration time):

```ts
export type McpAccessLevel = 'reads' | 'readsAsSession' | 'actsAsSession';
export type McpCapability = 'read' | 'act';

export type McpToolSpec<Input extends z.ZodTypeAny = z.ZodTypeAny> = {
  name: string;
  description: string;
  access: McpAccessLevel;
  input: Input;
  handler: (args: z.infer<Input>, ctx: McpInvocationContext) => Promise<unknown> | unknown;
};
```

Before invoking `handler`, the dispatcher checks the token's scope and session state uniformly:

```ts
// 'reads': valid non-expired token
// 'readsAsSession': valid token + token.capabilities.has('read') + session row exists in db
// 'actsAsSession': valid token + token.capabilities.has('act') + session is live in host
```

Token registry (`McpSessionRegistry`): generates 32 random bytes (`base64url`), indexes in a `Map<string, CredentialRecord>` by `sha256(rawToken)` (computed with `node:crypto`), stores `{ invocationId, sessionId, capabilities, lastAliveAt }`, expires records when `clock.now() - record.lastAliveAt > 24 * 60 * 60_000`, and revokes by `invocationId` (using `revokeByInvocation(invocationId)` in `open`, `prepare`, `resume`, `close`, and `onEnd`, plus `revokeAll()` on host shutdown). HTTP `/mcp` rejects missing/invalid `Authorization: Bearer <token>` with `401`, non-`POST` methods with `405`, bodies larger than 1 MiB with `413`, and malformed JSON with JSON-RPC `-32700` without logging headers or tokens.

Codex `mcpToolCall` and elicitation handling in `src/chat/codex.ts` (checked against `id: 0` falsiness—must test `m.id !== undefined`—and against missing `arguments` or failed calls):

```ts
// In serverRequest(requestId, method, params):
if (method === 'mcpServer/elicitation/request' && this.mcpServerName !== undefined && params?.serverName === this.mcpServerName) {
  this.respond(requestId, { action: 'accept', content: {} });
  return;
}
// In translate() item/started:
// when item?.type === 'mcpToolCall' && typeof item.id === 'string' -> { kind: 'tool_start', callId: item.id, tool: mcpToolName(item), ...(item.arguments !== undefined && { arg: JSON.stringify(item.arguments) }) }
// In translate() item/completed:
// when item?.type === 'mcpToolCall' && typeof item.id === 'string' -> { kind: 'tool_end', callId: item.id, tool: mcpToolName(item), ...(output && { output }), status: item.status === 'completed' && !item.error ? 'ok' : 'err' }
```

Testing seams per story:

- Stories 1 & 2: `src/chat/claude.test.ts` (replaying `sdkQuery` to assert `options.mcpServers['carrier-chat']`, `options.allowedTools` wildcard, and `mcpProblem` when `mcpServerStatus()` reports the injected server down) and `src/chat/codex.test.ts` (replaying transport lines to assert `mcp_servers.carrier-chat` on `thread/start` and `thread/resume`, auto-accepting `mcpServer/elicitation/request` including `id: 0` only for `carrier-chat` while rejecting others with `-32601`, translating `mcpToolCall` into `tool_start`/`tool_end`, and setting `mcpProblem` on failed startup status); real end-to-end tool round-trips in `src/chat/claude.integration.test.ts` (`CARRIER_IT_CLAUDE_CHAT=1`) and `src/chat/codex.integration.test.ts` (`CARRIER_IT_CODEX_CHAT=1`).
- Stories 3 & 6: `src/chat/mcp.test.ts` hitting the real loopback HTTP server with `FakeClock` (401 on missing/bad/revoked/expired tokens, 24h liveness refresh, 405/413/JSON-RPC errors, omitted vs invalid tool arguments, `reads`/`readsAsSession`/`actsAsSession` enforcement, and `defineTool` refusing a tool without a valid `McpAccessLevel`, and a server refusing a tool listed twice).
- Stories 4 & 5: `src/chat/sessions.test.ts` with `FakeChatRunner`, `FakeClock`, `FakeGit`, fake `HealthProbes`, and temp SQLite (`open`, `openPlan`, `resume` concurrency race revoking only the loser's `invocationId`, `close`, `agentOptions` receiving `mcp: undefined`, `capabilities` returning redacted health verdicts + live session options without local paths, and host fallback emitting `{ kind: 'notice' }` when MCP server is absent or `conversation.mcpProblem` is set), plus `src/chat/host.test.ts` verifying `startChatHost` starts and stops the MCP server alongside `chat.sock`.
- Story 7: `src/harnesses/claude.test.ts` and `src/harnesses/codex.test.ts` asserting `buildClaudeCommand` and `buildCodexCommand` never include `--mcp-config` or `mcp_servers`, verifying engine harnesses stay isolated from chat MCP.

## Out of scope

- Delegating tasks to another harness or model, reading or messaging other sessions, session lineage, approvals of child sessions and schedules. Each is a toolkit with its own spec. The first of them is the one that needs session lineage in `sessions.ts` and a decision about what a child may do.
- Handing a conversation over to another harness or model inside one session. It shares a primitive with delegation (opening a conversation on another harness with the context of the previous one) and has its own spec.
- Connecting the chat with the solve flow: guiding the person through setting up the repo, its skills and its labels, and closing a session into an epic that Carrier runs. A guide needs no link between the two worlds, but associating a session with an epic does, and [0012](../adr/0012-sessions-and-epics-are-two-separate-worlds.md) says no session id is stored on an epic and no epic id on a session. That needs its own ADR that supersedes 0012, and it is not this one.
- An off switch, OAuth, clients that are not launched by the host, and any tool that sees a session other than the caller's.
- Anything in the macOS app beyond showing the notice when a session opens without the MCP.
