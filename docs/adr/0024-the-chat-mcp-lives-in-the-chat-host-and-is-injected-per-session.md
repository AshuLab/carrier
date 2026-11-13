# 0024 - The chat MCP lives in the chat host and is injected per session, never into the engine's agents

- Status: accepted
- Date: 2026-11-12

## Context

The agents of a chat session can only use their own tools. We want them to reach back into Carrier: to see which harnesses and accounts exist, and later to delegate to another one or read other sessions. The way agents are given tools is an MCP server, and the question is where it runs, who receives it and who decides what a tool may do.

The engine runs agents on epics unattended, for hours. An agent there that could open sessions, delegate or read other conversations could use them in the middle of an autonomous flow where nobody is looking. The two kinds of agent also run the same CLIs with the same user configuration ([0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), so a server written into that configuration reaches both. And [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) says Carrier adds no permission policy of its own, while the MCP is on in every session and its calls are not meant to stop for the person.

## Decision

The MCP server runs inside the chat host process, on loopback, and is part of the chat's state under `<folder>/chat/`. The engine has no code that starts it or hands it to an agent, and a test fails if any harness of the engine is given MCP configuration.

It is injected when a real session opens or resumes and for that session only, under the server key `carrier-chat` through the options each harness takes in memory or over its stdio pipe (the SDK's query options for Claude, the `config` of `thread/start` and `thread/resume` for Codex), never in CLI `argv` and never written to the user's CLI configuration. Disposable option-listing probes get no MCP. Every real session has it; it is on by default, with no off switch in the first version.

Each live conversation has its own credential, random, kept hashed in memory and never stored, keyed to the conversation instance and its session so concurrent resumes or failed opens revoke cleanly, and revoked when the session closes. The tools of the MCP are grouped in toolkits and every tool declares an access level, enforced by the server before its handler runs. A tool without one does not register.

The tools of Carrier's own MCP are pre-approved in the harness (via `allowedTools` on Claude and setting `default_tools_approval_mode = "approve"` on the injected `carrier-chat` server and auto-accepting `mcpServer/elicitation/request` for it on Codex, because with the approval policy "Never ask" Codex refuses any MCP call that would need approval). This is the only exception to Carrier having no permission policy of its own, limited to tools Carrier serves; their safety is their access level and not a prompt.

If the MCP cannot start or a harness refuses it, the session opens without it and the person is told.

## Alternatives considered

The MCP in the engine process or on the control socket. One process less, but it ties the lifetime of the channel to the engine's stop, pause and lock, and puts a surface for agents on the socket that supervises unattended epics.

The server written into the user's CLI configuration, once for every agent. Nothing to inject per session, but it reaches the engine's agents, which is the one thing this decision exists to prevent.

An engine with no tool in the first delivery. It would separate the engine from the tools cleanly but leave the contract untested until the first real tool arrives, when changing it costs the most. One tiny tool proves the whole chain.

Off by default and opt-in. Safer on paper, but a channel nobody switched on is a channel no later capability can count on, and the credentials and levels already limit what an agent can do.

Each handler checking its own access. No framework to build, but the check then depends on every future author remembering it, and with calls pre-approved nobody would see a miss.

Asking the person to approve each call, or only the writing ones. Closer to 0013's letter, but it stops an agent that works unattended on every call to the channel, which is what the channel is for.

OAuth and clients Carrier did not launch, as T3 Code has. They need a sign-in and a consent page, and only the agents the host launches connect here.

## Consequences

Every session pays for a server that most conversations never call, and a harness that stops accepting per-session MCP configuration breaks the channel for it until its adapter changes; the Codex app-server is experimental, so this one is likely.

Pre-approval means a mistake in an access level has no second line of defence: it is the only barrier of a tool, so the test that every tool declares one and the review of each toolkit carry the weight.

A later tool that changes anything (delegating, messaging another session) needs a decision of its own about what it may do and what a child session may inherit; this ADR gives the place for it and not the answer.

Connecting a session to an epic is not allowed by this decision, and still contradicts [0012](0012-sessions-and-epics-are-two-separate-worlds.md). It would need its own ADR that supersedes that one.
