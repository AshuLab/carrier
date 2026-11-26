# src/usage

The quotas and the history of what was used ([ADR 0025](../../docs/adr/usage/0025-usage-runs-inside-the-chat-host.md), [spec](../../docs/specs/usage-and-limits.md)), composed by the chat host (`chat/host.ts`) and read by nothing else.

- `types.ts`: the ports (`UsagePorts`), `QuotaSnapshot` and its statuses.
- `probes.ts`: one probe per provider (Claude's OAuth endpoint with the login from `.credentials.json` or, on a Mac, its Keychain item (read only, never refreshed, never logged; [ADR 0026](../../docs/adr/usage/0026-claude-usage-reads-the-login-from-the-keychain-and-never-refreshes-it.md)); `codex app-server`; `agy -p /usage`; the local servers).
- `quotas.ts`: one probe per account at a time, kept a minute, the last good one marked stale on a rate limit.
  A snapshot's `message` has `messageCode` and `messageParams` beside it (`ProbeError` takes its code first after the status), and `PriceOverrideInvalid` carries its code the same way.
- `history.ts`: the rollup of epic runs (`carrier.db`, read-only), chat turns (`chat.db`) and the CLIs' own logs (incremental, cached between calls and kept in `chat.db`'s `usage_scan_files` across host restarts, with `SCAN_VERSION` to bump when a parser changes; a log not written since the range began is not read, and a call for one account leaves the cache of the other roots alone), a session counted once in epic, chat, external.
  Each chat turn carries its own harness, agent and native conversation, and the history reads those and not the session's current ones, so a session that changed agent keeps its earlier turns on their harness and its old conversation counted once.
- `agy.ts`: the protobuf reader of Antigravity's conversation databases.
- `pricing.ts`: the price table (LiteLLM's, copied into `prices.generated.ts`; `pnpm prices:update` refreshes it, see THIRD-PARTY-NOTICES.md), model names and the overrides.
- `service.ts`: what `usage` and `usageOverride` answer from `providers.json`.
  An account narrows the quotas, the logs scanned and the history: an epic run by its `option`, a chat turn by its agent's account.
- `real.ts`: the ports on the real machine.
