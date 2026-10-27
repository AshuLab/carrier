# 0013 - The chat host is its own process, with transcripts in SQLite and one adapter per provider

- Status: accepted
- Date: 2026-10-27

## Context

The app is going to let a person talk to the agent of their choice. Carrier runs agents only as unattended executions today: `AgentRunner.run(task)` spawns a child with the prompt in argv and no input, waits for one result and imports it with the epic's state transition. A conversation is the opposite: it is long-lived, idle between turns, takes input all the time, asks the person for approvals, and belongs to no epic ([0012](0012-sessions-and-epics-are-two-separate-worlds.md)).

Three things are hard to undo once built on. Where the conversation runs, because the engine's stop, lock, slots and control socket are written for epics ([0005](0005-engine-independent-of-the-macos-app.md), [0010](0010-carrier-runs-in-the-background-as-a-detached-process.md)). What Carrier owns of a conversation, because each provider already keeps its own context and history. And what shape Carrier speaks to a provider, because Claude's SDK, Codex's app-server and ACP agents each speak a different one.

## Decision

The chat host is a process of its own, with its own lock and its own control socket, started by the first client that opens a chat and ended when no session is running and no client is attached. It shares code with the engine (config, logger and its redaction, `childEnv`, process handling) and none of its state: not its lock, its slots, its epics or its labels. Stopping the engine does not stop it, and the other way round.

Carrier keeps its own copy of every user session in SQLite: the session, the agent and options it runs with, the provider's native session id so it can be resumed, and a transcript of chat events, bounded and redacted with the pattern of [0006](0006-agent-events-stored-in-sqlite-with-bounded-output.md) but with its own retention: a session is kept until the person deletes it. Each turn also records what is needed for statistics later (model, usage as the provider reports it, duration, tool calls, outcome). The provider keeps the context the model reads; Carrier's copy is for showing, searching and counting.

Carrier drives a provider through its own port, the chat runner, which speaks normalized chat events, with one adapter per provider and a fake for tests. Claude goes through the Claude Agent SDK pointed at the user's own `claude` binary, Codex through `codex app-server`. ACP is a later adapter behind the same port, not the seam. The permission modes, the model and the reasoning level are the provider's own options, listed by the adapter and chosen per session; Carrier adds no permission policy of its own.

## Alternatives considered

The chat inside the engine process. It saves a process and reuses the socket, but ties the lifetime of conversations to the engine's stop, pause and lock, and puts a command-running surface on the socket that supervises unattended epics.

Keeping no transcript and reading the provider's own history. Nothing to store or redact, but the list, the search and the statistics would depend on each provider's files and formats, which differ and change, and a session could not be shown if the provider's copy is gone or its folder moved.

ACP as the seam for every provider. One protocol for all, but ACP v2 is alpha, the Claude and Codex agents exist as adapters on top of the same SDK and app-server, and a Carrier-owned shape keeps the app independent of any protocol's churn.

A terminal pane with the unmodified CLI for every provider. Simplest and the closest to the vendors' terms, but Carrier would see no messages, approvals or usage, and could not draw a conversation of its own. It stays as the fallback for a provider whose native path fails its spike.

## Consequences

A second process with its own socket and lock to keep correct, and a client (the CLI first, the app later) that has to find or start it. The app becomes a client of two sockets. The chat host shares code with the engine, so a change to `childEnv` or the logger affects both.

Transcripts hold what the person typed, which can contain secrets; redaction catches tokens the way it does for epics but cannot know a secret in free text, so the retention is "until deleted" and the person is the one who deletes. Statistics need nothing beyond the per-turn record, so they can be built later without a migration of the transcripts.

Each provider is an adapter to keep alive, tested by recording a real transcript and replaying it through the real adapter. The Codex app-server is described by OpenAI as experimental and ACP v2 is alpha, so versions are pinned and the adapters are expected to change.

The terms under which Anthropic allows a Claude subscription to be used from an app that starts the user's own `claude` are not settled. Carrier is for personal use and nothing is published, so this does not block building; it must be answered in writing before any build with sessions is published.
