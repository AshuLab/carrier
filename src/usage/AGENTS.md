# src/usage

The quotas and the history of what was used ([ADR 0025](../../docs/adr/0025-usage-runs-inside-the-chat-host.md), [spec](../../docs/specs/usage-and-limits.md)), composed by the chat host (`chat/host.ts`) and read by nothing else.

- `types.ts`: the ports (`UsagePorts`), `QuotaSnapshot` and its statuses.
- `probes.ts`: one probe per provider (Claude's OAuth endpoint from the plaintext `.credentials.json` only, never refreshed and no Keychain; `codex app-server`; `agy -p /usage`; the local servers).
- `quotas.ts`: one probe per account at a time, kept a minute, the last good one marked stale on a rate limit.
- `history.ts`: the rollup of epic runs (`carrier.db`, read-only), chat turns (`chat.db`) and the CLIs' own logs (incremental, cached between calls), a session counted once in epic, chat, external.
- `agy.ts`: the protobuf reader of Antigravity's conversation databases.
- `pricing.ts`: the price table, model names and the overrides.
- `service.ts`: what `usage` and `usageOverride` answer from `providers.json`.
  An account narrows the quotas, the logs scanned and the history: an epic run by its `option`, a chat turn by its agent's account.
- `real.ts`: the ports on the real machine.
