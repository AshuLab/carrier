# Usage and limits

Status: spec

## Problem

People using Carrier today have to open third-party utilities such as CodexBar outside Carrier to understand how much quota remains on their registered models and accounts and when windows reset, while having no unified view inside Carrier of total model consumption across cloud and local models, epics, chats, and external terminal or IDE sessions.

The gap is felt both when deciding which account or model has headroom before starting a chat or epic, and when reviewing how much each provider, account, and model (including local servers such as LM Studio and Ollama) is actually consuming over time. Today [executions](../../src/storage/executions.ts) does not persist token or cost data for epic runs, [chat_turns](../../src/chat/schema.ts) stores raw per-turn usage that nothing aggregates or renders, and [agent-failures-say-why](agent-failures-say-why.md) only surfaces `usage_limit` reactively after an execution has already failed.

We know it is solved when a person can stay inside Carrier (in the macOS app and via `carrier usage`) to inspect remaining live quotas, reset times, extra credits, and filterable historical consumption across their registered accounts and models without reaching for a separate app.

## Solution

Usage and limits lives inside Carrier as an isolated `src/usage/` collection module served by the chat host over `chat.sock` (new `usage` and `usageOverride` capabilities) and rendered in two places: a dedicated `Usage` destination in the macOS app sidebar placed in the fixed bottom foot directly below `Settings`, and a matching `carrier usage` CLI command. Running collection inside the chat host rather than adding a third background daemon avoids another lock, socket, and update-restart lifecycle while still working when the engine is stopped ([0023](../adr/0023-usage-runs-inside-the-chat-host.md)); running it inside the engine was cut because the engine may be unconfigured or stopped, and parsing in Swift was cut so CLI/database collection is not duplicated away from `carrier usage`. Placing `Usage` in the sidebar foot below `Settings` (leaving `Archive` and folded `Carrier` above the foot divider) was chosen over placing it under `Carrier` in the scroll area so workspace/epic navigation stays separate from account observability.

Throughout the backend contract and UI, three concepts remain strictly separated ([glossary](../glossary.md)): **live quota** (rolling window utilization %, reset timestamps, scoped/grouped model pools, and **extra credits** or prepaid spend where natively exposed; marked N/A for `lmstudio`/`ollama`), raw **tokens** (`input`, `cachedInput`, `cacheCreation`, `output`, `reasoning`), and **estimated API cost** (notional USD from a bundled model price table, explicitly labeled as an API-equivalent reference for fixed-plan subscriptions and `$0` for local compute, never added to or conflated with real prepaid/extra credits). Unknown or unpriced models stay visible with an orange `Unpriced` indicator and can be mapped or priced locally (`$0.00 local`, catalog alias, or custom per-1M rates) via `usageOverride` rather than guessing rates or dropping totals.

Live quotas use **native CLI, JSON-RPC, and read-only OAuth mechanisms** scoped per account in `providers.json` ([codexbar-usage-fetching.md](../research/codexbar-usage-fetching.md)), backed by an in-memory ~60s cache and explicit error/auth states (`ready`, `signedOut`, `missing`, `stale`, `error`) so one expired account never blocks sibling accounts:

- **Claude (`CLAUDE_CONFIG_DIR`)**: invokes `@anthropic-ai/claude-agent-sdk`'s `get_usage` control probe (`usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true })`, ~4.3s, `persistSession: false`, `disableAllHooks: true`, `mcpServers: {}`, `strictMcpConfig: true`) via the user's `claude` binary, reading `five_hour`, `seven_day`, `model_scoped` limits, `seven_day_breakdown`, and `spend` / `extra_usage` (converting minor units using `exponent` / `decimal_places`) with zero macOS Keychain ACL prompts in an unsigned app ([0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)); when plaintext `.credentials.json` is present and valid, `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` serves as a fast path without ever refreshing tokens externally.
- **Codex (`CODEX_HOME`)**: reads `account/rateLimits/read` over `codex app-server` JSON-RPC (already spoken by [src/chat/codex.ts](../../src/chat/codex.ts)) or read-only `$CODEX_HOME/auth.json` against `https://chatgpt.com/backend-api/wham/usage`, surfacing `primary` (5h), `secondary` (7d), secondary `rateLimitsByLimitId` buckets (`spark`, etc.) without letting model-specific buckets overwrite the main `codex` windows, `planType`, `credits.balance`, and `rateLimitResetCredits`.
- **Antigravity (`agy`)**: executes `BROWSER=true agy -p "/usage" --output-format json </dev/null` (~5s, zero tokens), surfacing all three pools (`Gemini Models`, `Claude and GPT models`, `Gemini 4 Argon`) with `5h`/`weekly` remaining fractions and reset timestamps while explicitly marking numeric AI credits balance unavailable because neither the CLI nor Google's `retrieveUserQuotaSummary` endpoint exposes it without scraping Keychain/cookies.
- **Local servers (`lmstudio`, `ollama`)**: reuses [listLocalModels](../../src/harnesses/local.ts) to report running/offline state and loaded models with `quotaAvailable: false`.

Historical consumption unifies four local sources inside the chat host without double-counting: persisted token/cost telemetry on epic [executions](../../src/storage/executions.ts) (opened read-only from `<CARRIER_HOME>/engine/state/carrier.db` when present, plus parsed token usage captured in [host-runner.ts](../../src/harnesses/host-runner.ts) / harness adapters on completion), per-turn `usage` already saved in `chat_turns` (`chat.db`), and incremental fingerprint-cached scanners across Claude (`$CLAUDE_CONFIG_DIR/projects/**/*.jsonl`, globally deduplicated across forked/resumed files by `(message.id, requestId)` keeping the highest/final token counts, where `input_tokens` excludes cache reads/writes), Codex (`$CODEX_HOME/sessions/**/*.jsonl`, deduplicating consecutive equal `token_count` snapshots and computing uncached input as `max(0, input_tokens - cached_input_tokens)` while treating `reasoning_output_tokens` as a subset of `output_tokens`), and Antigravity (`~/.gemini/antigravity-cli/conversations/*.db` opened read-only with a minimal protobuf reader for `gen_metadata` and `steps` modeled on `pingdotgg/t3code`'s `antigravityUsageReader.ts`). Canonical `sessionId` matching against `sessions.nativeId` and `executions.sessionId` prevents double-counting Carrier runs, assigns source (`epic`, `chat`, `external`), and marks `lmstudio`/`ollama` sessions as `$0.00` local compute even when launched via Claude or Codex harnesses.

In `Carrier.app`, `Usage` uses a compact **Option B pooled provider layout** styled per [macos-ui](../macos-ui.md) rather than a multi-column card grid above the fold: a single `SettingsTabCard` grouped by provider (`Claude`, `Codex`, `Antigravity`, `Local Servers`) separated by `SettingsDivider`, with pooled `5h`/`Weekly` bars, a hatched next-refill preview band, earliest reset label, and a `16pt` `StatusMark`. Expanding any provider row (`chevron.right`) reveals every underlying account or server/pool row (all `agy` pools + `"AI credits: Unavailable via native CLI"`, Claude `model_scoped` + `seven_day_breakdown` + `extra_usage`/`spend` + inline `Sign in` when signed out, Codex `rateLimitsByLimitId` + `credits.balance` + `rateLimitResetCredits`, and expandable `LM Studio`/`Ollama` rows), and clicking any expanded account or local server filters the consumption dashboard below (4-column KPI summary card, `Est. API Cost ($)` / `Tokens` toggle, `7d`/`14d`/`30d` range, source menu, `FilterChip`s, repo/model search, daily stacked bar chart, `By model` with `in · cache · out` channels + custom price override sheet, and `By workspace & source`). Live quotas refresh on opening `Usage`, app activation, manual `Check again`, after `usage_limit` execution failures, and on a gentle background interval only while `Usage` stays open.

## Scope

1. When an epic execution ends (`ok`, `failed`, `timed_out`, `stopped`), Carrier extracts token counts and any reported cost from the Claude, Codex, or Antigravity harness stream and persists them on the execution row in SQLite (`carrier.db`) without failing runs whose output omits usage.
2. Reading `providers.json`, the `src/usage/` module queries live quotas natively per account (`Claude` Agent SDK `get_usage` or plaintext `.credentials.json`, `Codex` `app-server` `account/rateLimits/read` or `$CODEX_HOME/auth.json`, `agy -p "/usage" --output-format json`, and local `lmstudio`/`ollama` server probes), caches results for ~60s (`force` bypasses cache), surfaces missing/signed-out states cleanly, and never touches browser cookies or foreign Keychain items.
3. The historical aggregator combines `chat_turns` (`chat.db`), optional read-only `executions` (`carrier.db`), and incremental fingerprint/offset-cached local scans of `$CLAUDE_CONFIG_DIR/projects/**/*.jsonl`, `$CODEX_HOME/sessions/**/*.jsonl`, and `~/.gemini/antigravity-cli/conversations/*.db`, deduplicating forked transcripts and Carrier-launched sessions by canonical provider/session IDs, tagging source (`epic`, `chat`, `external`), and keeping `lmstudio`/`ollama` runs at `$0.00` local cost.
4. `chat.sock` exposes strict `usage` and `usageOverride` commands on the chat host (advertised in `hello.capabilities`), and `carrier usage` (`--json`, `--refresh`, `--days`, `--provider`, `--source`) connects to or starts the chat host and renders live quotas plus consumption in the terminal.
5. In `Carrier.app`, `Usage` sits in the fixed sidebar bottom foot directly beneath `Settings` (below the foot divider), selecting into its own centered detail page with Carrier's neutral sidebar highlight and light/dark theme fidelity.
6. The live quota card shows pooled `5h` and `Weekly` bars, hatched next-refill preview, earliest reset time, and `StatusMark` per provider (`Claude`, `Codex`, `Antigravity`, `Local Servers`), with expandable `chevron.right` rows revealing every underlying account, all three `agy` pools, scoped buckets, surface mix, extra credits/spend (or unavailable notice), and inline `Sign in` / `Check again` actions.
7. Clicking any expanded account or local server row (or using the `Est. API Cost ($)` / `Tokens` toggle, `7d`/`14d`/`30d` range, Source selector, `FilterChip`s, and search input) filters the KPI summary card, daily stacked bar chart, `By model` (`in · cache · out`), and `By workspace & source` cards consistently.
8. Unknown or unpriced models show an orange `Unpriced · Map` badge instead of `$0.00` or dropped totals; clicking opens an override popover/sheet (`$0.00 local`, catalog alias, or custom `$/1M` rates) validated and persisted via `usageOverride`.
9. `UsageView` triggers refreshes on view appear, app foregrounding, manual `Check again`, execution `usage_limit` notifications, and gentle background polling only while `Usage` is visible.
10. Update `CHANGELOG.md` under `Unreleased` (and `docs/configuration.md` if any host config key is added).

## Decisions

The feature keeps its collection module under `src/usage/` inside the chat host process ([0023](../adr/0023-usage-runs-inside-the-chat-host.md)), reading `<CARRIER_HOME>/providers.json` ([0020](../adr/0020-accounts-live-in-a-file-both-processes-read.md)), `<CARRIER_HOME>/chat/state/chat.db`, and `<CARRIER_HOME>/engine/state/carrier.db` (opened read-only with graceful empty fallback if the engine DB does not exist yet), plus persisting user model-price overrides in SQLite (`chat.db`) via a Drizzle migration generated with `pnpm db:generate`. Running `get_usage` through `@anthropic-ai/claude-agent-sdk` keeps OAuth/Keychain handling inside the user's `claude` binary so an unsigned app ([0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)) triggers zero Keychain ACL dialogs, while `$CODEX_HOME/auth.json` and `codex app-server` stay plaintext/RPC-only and `agy -p "/usage" --output-format json` avoids Google Keychain probes.

The `chatRequest` union in [src/chat/server.ts](../../src/chat/server.ts) adds `usage` and `usageOverride` with strict validation rejecting negative, non-finite, or empty inputs:

```ts
export const usageOverrideRequest = z.strictObject({
  id,
  cmd: z.literal('usageOverride'),
  model: z.string().trim().min(1).max(200),
  action: z.enum(['local', 'alias', 'custom', 'clear']),
  aliasTo: z.string().trim().min(1).max(200).optional(),
  inputPerMillionUsd: z.number().finite().nonnegative().max(10_000).optional(),
  cachedInputPerMillionUsd: z.number().finite().nonnegative().max(10_000).optional(),
  outputPerMillionUsd: z.number().finite().nonnegative().max(10_000).optional(),
}).refine((r) => {
  if (r.action === 'alias') return r.aliasTo !== undefined;
  if (r.action === 'custom') return r.inputPerMillionUsd !== undefined && r.outputPerMillionUsd !== undefined;
  return true;
});

export const usageRequest = z.strictObject({
  id,
  cmd: z.literal('usage'),
  refresh: z.boolean().optional(),
  days: z.union([z.literal(7), z.literal(14), z.literal(30), z.literal(90)]).optional(),
  provider: z.enum(['all', 'claude', 'codex', 'agy', 'local']).optional(),
  source: z.enum(['all', 'epic', 'chat', 'external']).optional(),
  account: z.string().trim().min(1).max(200).optional(),
});
```

On the Swift side, navigation adds `Selection.usage` to [WindowShell.swift](../../macos/Sources/CarrierCore/WindowShell.swift) and pure pooling/filtering/formatting logic (`UsagePage.swift` / `UsageModels.swift`) lives in `CarrierCore` alongside `ChatHost.swift` decoders tolerant of omitted optional quota/override fields, while `UsageView.swift` under `macos/Sources/Carrier` remains a thin rendering layer reusing `SettingsPageHeader`, `SettingsTabCard`, `SettingsDivider`, `StatusMark`, `FilterChip`, and `ChoicePopUp` ([macos-ui](../macos-ui.md)).

Testing seams, story by story:

- Story 1: Unit tests in `src/harnesses/claude.test.ts`, `codex.test.ts`, `agy.test.ts` pinning usage extraction from real JSONL fixtures (including `usage_limit` error lines); `src/storage/migrations.test.ts` verifying old `executions` rows migrate cleanly with null telemetry; `src/orchestration/engine.test.ts` verifying `FakeAgentRunner` telemetry persists on `executions`.
- Story 2: Unit tests on `src/usage/quotas.test.ts` against injected fake probe ports (`ProbeRunner`, `Clock`, temp `providers.json`), covering SDK minor-unit spend scaling, `rate_limits_available: false`, Codex `rateLimitsByLimitId` isolation, `agy` 3-bucket fractions with `creditsBalance: null`, local running/offline states, and ~60s cache expiry + `force`. Optional gated test in `*.integration.test.ts` for live CLI probes.
- Story 3: Fixture tests on `src/usage/history.test.ts` and `src/usage/pricing.test.ts` over temp directories holding synthetic forked Claude JSONLs (`(message.id, requestId)` dedup), Codex duplicate `token_count` rollouts (`input - cached`), Antigravity SQLite/protobuf `.db` fixtures (`gen_metadata`/`steps`), temp `chat.db` + read-only `carrier.db` (`sessionId`/`nativeId` dedup and missing `carrier.db` fallback), and `lmstudio`/`ollama` `$0` tagging; plus a byte-offset append / guard-hash rewrite cache test.
- Story 4: `src/chat/server.test.ts` and `src/chat/host.test.ts` covering schema validation (including invalid/negative `usageOverride` payloads), `hello.capabilities`, and end-to-end request/reply over `chat.sock`; `src/terminal/cli/args.test.ts`, `main.test.ts`, and `src/terminal/cli/commands/usage.test.ts` covering `carrier usage --json` and `--days/--provider/--source`.
- Story 5: `CarrierCoreTests` (`SidebarTests` / `WindowShell` selection tests) pinning `Selection.usage` placement, non-regression on `OpenSection` (`sessions`, `carrier`, `archive`), and keyboard/selection state.
- Stories 6 to 8: Pure model tests in `macos/Tests/CarrierCoreTests/UsagePageTests.swift` and `ChatHostUsageTests.swift` pinning provider pooling/sorting by earliest refill, hatched refill share calculation, `Unpriced` / override recalculation, account/source/provider/search filtering, and tolerant JSON decoding when an older `chat host` lacks `usage` capability.
- Story 9: Refresh cadence / trigger controller test in `CarrierCoreTests` pinning cooldown (~60s cache respect vs `force`) and active-visibility gating; `UsageView.swift` itself has no UI test and is verified visually with `macos/build-app.sh --open` in dark and light themes.
- Story 10: No tests; documentation / changelog check.

## Out of scope

Importing or decrypting browser cookies (Chrome, Safari, Firefox), reading foreign macOS Keychain items owned by other apps, or scraping web dashboards when native CLI/RPC/OAuth mechanisms do not expose a field.

Intercepting or proxying direct LM Studio/Ollama HTTP traffic made outside Carrier and Claude/Codex sessions.

Changing engine scheduling, pre-flight blocking, or automated failover policies based on live quota readings (this feature provides visibility; automated failover decisions remain separate).

Vendor billing/invoice reconciliation; estimated USD remains a local catalog estimate.

A standalone third background daemon (`usage host`) running independently when the macOS app is closed.
