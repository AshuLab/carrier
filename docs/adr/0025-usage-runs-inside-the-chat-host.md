# 0025 - Usage collection and serving run inside the chat host

- Status: accepted
- Date: 2026-11-12

## Context

Carrier needs to collect and serve two kinds of usage data across every account in `providers.json`: live provider quotas (rolling windows, reset timestamps, and extra credits via native CLI or OAuth mechanisms) and historical token and estimated API cost breakdowns (from Carrier's own chats and epic executions as well as incremental scans of local Claude and Codex JSONL session logs). Users must be able to open the app's Usage view and query `carrier usage` even when the autonomous engine is stopped or unconfigured.

Today Carrier runs two detached processes under the Carrier folder ([0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)): the engine (`<folder>/engine/`, `control.sock`, `carrier.db`) and the chat host (`<folder>/chat/`, `chat.sock`, `chat.db`). Although [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) introduced the chat host for user conversations, it has already become the host for non-chat, Mac-side account operations (`providers` and `health`), because it starts without an engine config, inherits the user's login-shell `PATH`, and is already lifecycle-managed, capability-checked, and restarted on updates by the macOS app.

## Decision

We run live quota probing, local JSONL scanning, and historical aggregation in a dedicated, self-contained usage module served by the chat host behind a new `usage` capability on `chat.sock`, while `carrier usage` in the CLI asks the same host over `chat.sock`, starting it when none runs. The engine continues to record its own epic execution token and cost data in `carrier.db` (`executions`), which the usage module reads in read-only mode alongside `chat.db` (`chat_turns`), `providers.json`, and local Claude/Codex session logs.

## Alternatives considered

A third detached daemon under `<folder>/usage/` with `usage.sock`, its own `carrier.lock`, its own log folder, and its own update-restart lifecycle. It cleanly separates usage from chat restarts and could keep polling when the macOS app is closed, but it forces the macOS app to manage three Unix sockets instead of two, adds a third detached launcher and version-check target, and still has to read `providers.json`, `chat.db`, and `carrier.db` anyway; meanwhile, closing the app loses no quota data because live quotas live on the provider and historical tokens live on disk.

Putting usage inside the engine (`control.sock`). It reuses a socket when epics run, but fails whenever the engine is stopped or unconfigured, whereas users check remaining quotas precisely before starting work or when using chat alone.

Polling directly from the macOS Swift app. It splits provider CLI/OAuth/JSONL parsing between Swift and TypeScript, breaks `carrier usage` CLI parity, and loses the login-shell `PATH` and `providers.json` runtime resolution already wired in Node.

## Consequences

What is built for Claude is the file-only path: the probe reads the account's plaintext `.credentials.json` and asks the OAuth usage endpoint, never refreshes a token and (until [0026](0026-claude-usage-reads-the-login-from-the-keychain-and-never-refreshes-it.md)) never reads the Keychain, so an account whose login lives only in the macOS Keychain reports `missing` (its message says the Keychain is not read). Asking through the Claude Agent SDK's `get_usage`, which would reach that login inside the user's own `claude` binary, is a deferred follow-up. A snapshot's status is one of `ok`, `signed_out`, `missing`, `unavailable`, `rate_limited` and `error`, with a `stale` flag when a rate-limited probe kept the last known windows.

The macOS app stays a client of two sockets (`control.sock` and `chat.sock`) and gets usage updates through the existing host connection, capability handshake, and update-restart flow. Keeping the usage collector and scanner isolated in their own module preserves a clean extraction seam if a future requirement (such as background quota alerts while the app is completely quit) ever justifies promoting it to a third daemon.

The chat host now reads `carrier.db` (strictly read-only) in addition to `chat.db` and `providers.json`, and its idle-exit rule means background quota polling only runs while the app or a client keeps `chat.sock` open. [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) and [0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) remain valid, with the chat host explicitly recognized as the app's Mac-side host for `providers`, `health`, and `usage`.
