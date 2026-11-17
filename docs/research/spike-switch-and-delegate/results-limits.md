# Results, part D: the signal of a usage limit

Written on 2026-11-16. Reading and replay only: no agent turn, no quota used.
Installed here: Claude Code CLI 2.1.325, `@anthropic-ai/claude-agent-sdk` **0.3.311** (the types in `node_modules`, and the version in `package.json`; the spike README and the spec say 0.3.325), Codex **0.167.2** (the spec says 0.169.0; the adapter's `CODEX_APP_SERVER_VERSION` is 0.153.4 and only logs a warning when it differs).
Scripts: [`limits/replay.ts`](limits/replay.ts) (the real adapters, fake `query` and fake transport) and [`limits/codex-rate-limits-read.ts`](limits/codex-rate-limits-read.ts) (one `account/rateLimits/read`, shape only).

## Short answer

- Claude: the signal that tells a usage limit from a retried rate limit is **structured**: `api_error: "usage_limit_reached"` (with `api_error_status: 429`) on the failed `result`.
  It is a real capture in the fixture, and the CLI binary documents it as the typed kind for "the account's own usage limit" and says the other `rate_limit` refusals never carry it.
  Caveats: it is `@internal` in the CLI's own schema ("the text stays the fallback and may change") and it is **not in the SDK's `.d.ts`**.
  The reset time is a **timestamp** (`resetsAt`, epoch seconds) on the `rate_limit_event` message and on the synthetic assistant message (`api_error_params.rate_limit_info`), and only **text in local time** (`resets 12:40pm (America/Montevideo)`) on the `result`.
- Codex: the signal is **structured**: `CodexErrorInfo` = `"usageLimitExceeded"` on the `error` notification and on `turn/completed`'s `turn.error`.
  The retried rate limit is `"rateLimitExceeded"` with `willRetry: true` on the `error` notification.
  The reset time is **not** in the error: it comes from `account/rateLimits/read` (epoch seconds per window, observed) or from the tail of the message (text, local time, no zone).
- Today neither adapter classifies anything: both turn a limit into `{ kind: 'error', text }` plus `turn_end` with outcome `error`.

## D1. Claude

### What the SDK types say (0.3.311, `sdk.d.ts`)

| Message | Fields that matter | Notes |
| --- | --- | --- |
| `SDKRateLimitEvent` `{ type: 'rate_limit_event', rate_limit_info, uuid, session_id }` | `rate_limit_info: SDKRateLimitInfo` | "for claude.ai subscription users"; emitted "when rate limit info changes" |
| `SDKRateLimitInfo` | `status: 'allowed' \| 'allowed_warning' \| 'rejected'`, `resetsAt?: number`, `rateLimitType?: 'five_hour' \| 'seven_day' \| 'seven_day_opus' \| 'seven_day_sonnet' \| 'seven_day_overage_included' \| 'overage'`, `utilization?`, `overageStatus?`, `overageResetsAt?`, `overageDisabledReason?`, `isUsingOverage?`, `surpassedThreshold?` | `resetsAt` is epoch seconds (the CLI's own description says "unix epoch seconds") |
| `SDKResultSuccess` | `subtype: 'success'`, `is_error: boolean`, `result: string`, `api_error_status?: number \| null`, `terminal_reason?` | a usage limit is a `success` subtype with `is_error: true` (the fixture), not an `error_*` subtype |
| `SDKResultError` | `subtype: 'error_during_execution' \| 'error_max_turns' \| 'error_max_budget_usd' \| 'error_max_structured_output_retries'`, `errors: string[]` | none of these is a limit |
| `SDKAssistantMessage` | `error?: SDKAssistantMessageError` (`'rate_limit'` among 13 values), `limitScope?: 'service' \| 'channel' \| 'group_pool'`, `errorCode?: 'credits_required'` | a usage limit and a throttle are both `error: 'rate_limit'`: this field alone does not tell them apart |
| `SDKAPIRetryMessage` `{ type: 'system', subtype: 'api_retry', attempt, max_retries, retry_delay_ms, error_status, error }` | | "a retryable error that will be retried after a delay": the rate limit the CLI retries by itself |
| `TerminalReason` | includes `'blocking_limit'`, `'api_error'` | the fixture's result has `terminal_reason: "api_error"` |
| `USAGE_LIMIT_ERROR_PREFIXES` (exported at runtime, `@alpha`) | `"You've hit your"`, `"You've reached your"`, `"You're out of usage credits"`, `'Your org is out of usage · add funds to continue'`, ... 12 prefixes | "messages meaning a usage limit was genuinely reached"; `USAGE_WARNING_PREFIXES` (`"You've used"`, `"You're close to"`) and `USAGE_TRANSITION_PREFIXES` are the non-errors |

NOT in the `.d.ts` but present in the shipped CLI 2.1.325 (strings of the binary, read only):

- On the stream-json `assistant` wrapper: `is_api_error_message`, `api_error_status`, `api_error` (an enum of 37 kinds that includes `usage_limit_reached`, `model_requires_usage_credits`, `long_context_credits_required`), `api_error_params`, `api_error_code`, `api_error_type`.
- The binary's own comment for `usage_limit_reached`: "the request was refused by the account's own usage limit, a plan limit (session, weekly or per-model) or a spend cap on usage credits; `api_error_params.rate_limit_info` says which and when it resets. The other refusals that share error `rate_limit` never carry it: an organization policy that turned the service off, a temporary server throttle, a capacity switch-off, an entitlement refusal shown in the server's own words, or a 429 on an API key or a third-party cloud provider."
- `rate_limit_info` there is "in the shape `rate_limit_event` carries": `status: 'rejected'`, `rateLimitType`, `resetsAt`, `overageStatus`, `overageResetsAt`, `overageDisabledReason`, `limitScope`, `dailyCapPaused`; "it is that refusal's record and is never updated, so compare `resetsAt` with the clock".
- The synthetic message builder in the binary sets `error: "rate_limit"` and, only when the limit is a plan limit (or daily cap paused), `apiError: "usage_limit_reached"` and `apiErrorParams: { rate_limit_info }`; otherwise it is `error: "rate_limit"` with a generic text.
- On the `result` of subtype `success`: `api_error_status`, `api_error_code`, `api_error_type`, `api_error_origin`, `api_error` are copied; **`api_error_params` is not**. So the structured reset time is not on the `result`.
- The CLI's own internal check for "this result is a usage limit" is `subtype === 'success' && (api_error === 'usage_limit_reached' || api_error === 'model_requires_usage_credits')`.

### What a usage limit looks like on each path today

Fixture `src/harnesses/claude-usage-limit.fixture.jsonl`: one line, a **real capture** (the harness comment says shapes observed with 2.1.301).
It is a `result` with `subtype: "success"`, `is_error: true`, `api_error_status: 429`, `api_error: "usage_limit_reached"`, `terminal_reason: "api_error"`, `stop_reason: "stop_sequence"`, `usage` zeroed, `modelUsage` with the real totals, and `result: "You've hit your session limit · resets 12:40pm (America/Montevideo)"`.
No `resetsAt`, no `rate_limit_info`, no assistant line and no `rate_limit_event` are in it (only the result was kept).

| Path | Today |
| --- | --- |
| Engine harness `parseClaudeLine` (`src/harnesses/claude.ts:75-81`) | classifies: `is_error` and numeric `api_error_status`; `429` plus `api_error === 'usage_limit_reached'` gives `failure: { kind: 'usage_limit', detail: text }`, any other status gives `api_error` with `HTTP <n>: <text>`. The reset stays in the text. A 401 is `authFailed`. |
| Chat adapter `turnEnd` (`src/chat/claude.ts:353-369`) | `if (m.is_error && !interrupted) emit { kind: 'error', text: failureText(m) }`, then `turn_end` with outcome `error`. `failureText` = `errors.join` if any, else `result.trim()`, else `'The turn failed'`. `api_error`, `api_error_status`, `terminal_reason` are not read. |
| Chat adapter `translate`, `assistant` (`:326-339`) | the synthetic message (`model: '<synthetic>'`) only skips `lastModel`; its text block is emitted as a normal `assistant` event, so the limit text appears as an assistant message **and** as the `error` text. `message.error`, `api_error*` are not read. |
| Chat adapter `translate`, `default` (`:348`) | `rate_limit_event` (any status) and `system/api_retry` give no event. |
| `src/usage` | does not read the stream. `probes.ts:45-59` reads `resets_at` (ISO string, to ms) from `https://api.anthropic.com/api/oauth/usage` for the windows shown in the quota panel. That is a separate read, not a failure signal. |

## D2. Codex

Generated with `codex app-server generate-ts` and `generate-json-schema` into `/tmp/limits-d-ts` and `/tmp/limits-d-schema` (0.167.2).

| Type | Shape |
| --- | --- |
| `ServerNotification` `error` | `ErrorNotification = { error: TurnError, willRetry: boolean, threadId: string, turnId: string }` |
| `TurnError` | `{ message: string, codexErrorInfo: CodexErrorInfo \| null, additionalDetails: string \| null, misalignment: MisalignmentErrorDetails \| null }` |
| `turn/completed` | `{ threadId, turn: Turn }`; `Turn.status: 'completed' \| 'interrupted' \| 'failed' \| 'inProgress'`; `Turn.error: TurnError \| null` ("Error associated with a failed or interrupted turn") |
| `CodexErrorInfo` (strings) | `contextWindowExceeded`, `sessionBudgetExceeded`, **`usageLimitExceeded`**, **`rateLimitExceeded`**, `flexUnavailable`, `serverOverloaded`, `modelNotFound`, `policyCapacityUnavailable`, `cyberPolicy`, `misalignmentPolicyViolation`, `tooManyDenials`, `internalServerError`, `unauthorized`, `badRequest`, `threadRollbackFailed`, `sandboxError`, `other` (the TS type ends with `\| string \| { [key: string]: unknown }`, the JSON schema does not: unknown values are expected) |
| `CodexErrorInfo` (objects) | `httpConnectionFailed`, `responseStreamConnectionFailed`, `responseStreamDisconnected`, `responseTooManyFailedAttempts`, each `{ httpStatusCode: number \| null }`; `activeTurnNotSteerable { turnKind }` |
| `account/rateLimits/read` (request, no params needed) | `{ ordinaryUsageAllowed: boolean \| null, rateLimits: RateLimitSnapshot, rateLimitsByLimitId: { [id]: RateLimitSnapshot } \| null, rateLimitResetCredits, accountId, rateLimitUpsell }` |
| `RateLimitSnapshot` | `{ limitId, limitName, normalModelSlug, primary: RateLimitWindow \| null, secondary: RateLimitWindow \| null, credits: { hasCredits, unlimited, balance } \| null, individualLimit: SpendControlLimitSnapshot \| null, spendControlReached: boolean \| null, planType, rateLimitReachedType: RateLimitReachedType \| null }` |
| `RateLimitWindow` | `{ usedPercent: number, windowDurationMins: number \| null, resetsAt: number \| null }` (epoch seconds) |
| `SpendControlLimitSnapshot` | `{ limit, used, remainingPercent, resetsAt: number }` |
| `RateLimitReachedType` | `rate_limit_reached`, `workspace_owner_credits_depleted`, `workspace_member_credits_depleted`, `workspace_owner_usage_limit_reached`, `workspace_member_usage_limit_reached` |
| `account/rateLimits/updated` (notification) | `{ rateLimits: RateLimitSnapshot }`, "sparse rolling update": merge into the last read or refetch |

Observed (one read of `account/rateLimits/read`, shape only, no turn): the call works with the person's login and answers `primary: { usedPercent: 100, windowDurationMins: 43200, resetsAt: 1795212671 }`, which is `2026-11-20T22:11:11Z`, a number in epoch seconds; `ordinaryUsageAllowed: false`, `credits: { hasCredits: false, balance: null }`, `planType: "free"`, **`rateLimitReachedType: "rate_limit_reached"`**.
That is: the Codex account on this machine is out of quota right now (reset in four days), and the snapshot names that state `rate_limit_reached`, not a "usage" word. So `rateLimitReachedType` does not separate a usage limit from a rate limit by its name; `usedPercent: 100` with `ordinaryUsageAllowed: false` and a `resetsAt` days away does.

### What the chat adapter does with it today (`src/chat/codex.ts`)

- `translate` has no case for the `error` notification: it falls to `default: return []`. `willRetry`, `codexErrorInfo` and the text are dropped there.
- `turn/completed` goes to `turnEnd` (`:425-435`): outcome `error` for any status that is not `completed` or `interrupted`; emits `{ kind: 'error', text: turn.error.message }` (or `'The turn failed'`), then `turn_end`. `turn.error.codexErrorInfo` is not read.
- `account/rateLimits/updated` is not handled either (default).
- Engine harness `src/harnesses/codex.ts:42-64` (exec JSON, not app-server): text only, `turn.failed` whose `error.message` starts with `You've hit your usage limit`, `You hit your spend cap`, `Your workspace is out of credits` or `Quota exceeded.` gives `usage_limit`. The fixture `codex-usage-limit.fixture.jsonl` is **constructed**, not captured (said in `agent-usage-limit-signals.md`): `error` event then `turn.failed`, message `You've hit your usage limit. Try again at Oct 28th, 2026 3:45 PM.`
- `src/usage/probes.ts:159-239` already calls `account/rateLimits/read` and keeps `resetsAt * 1000` per window (`codexWindows`), plus `credits`, `planType` and `rateLimitResetCredits`. So the reset-time read exists in the codebase; the chat adapter has no use of it.

## D3. Replay (`limits/replay.ts`, output saved in this section)

The real `claudeChatRunner` and `codexChatRunner`; only the SDK `query` and the app-server transport are fake. Events shown without `option` and `delta`.
The Codex lines are **constructed** from the generated schema (no real failure was captured); the Claude `result` is the real fixture; the synthetic assistant line's `api_error*` fields in b2/b3 are **constructed** from the binary's schema.

| Case | What went in | What came out (ChatEvents) |
| --- | --- | --- |
| a1 Codex usage limit | `error` notification (`codexErrorInfo: 'usageLimitExceeded'`, `willRetry: false`) then `turn/completed` failed with the same `TurnError` | `error {text: "You've hit your usage limit. Try again at Nov 17th, 2026 3:45 PM."}`, `turn_end {outcome: 'error'}` |
| a2 Codex transient | `error` notification (`rateLimitExceeded`, `willRetry: true`, `Reconnecting... 1/5`) then `turn/completed` completed | `turn_end {outcome: 'ok'}` only: the retry notice is dropped, correctly |
| a3 retried to exhaustion | failed turn, `{ responseTooManyFailedAttempts: { httpStatusCode: 429 } }`, text `exceeded retry limit, last status: 429 Too Many Requests` | `error {text}`, `turn_end error` |
| a4 failed turn, `rateLimitExceeded` | `Rate limit reached. Please try again in 11s` | `error {text}`, `turn_end error` |
| a5 workspace credits | text `Your workspace is out of credits...`, `codexErrorInfo: 'usageLimitExceeded'` | `error {text}`, `turn_end error` |
| a6 failed turn, `error: null` | | `error {text: 'The turn failed'}`, `turn_end error` |
| b1 Claude real result | the fixture line alone | `error {text: "You've hit your session limit · resets 12:40pm (America/Montevideo)"}`, `turn_end {outcome: 'error', model: 'claude-sonnet-5-5' (from modelUsage)}` |
| b2 with the synthetic message and a `rate_limit_event` | `rate_limit_event` rejected, synthetic assistant (`api_error: 'usage_limit_reached'`, `api_error_params.rate_limit_info`), then the fixture result | `assistant {text: limit text}`, `error {same text}`, `turn_end error`: the limit text twice, no event from `rate_limit_event`, none of the structured fields carried |
| b3 Claude 429 that is not a usage limit | synthetic `error: 'rate_limit'` 429 without `api_error`; result 429 without `api_error` | `assistant`, `error {text}`, `turn_end error`: identical in kind to b2 |
| b4 `error_during_execution` | `errors: ['boom']` | `error {text: 'boom'}`, `turn_end error` |
| b5 only `rate_limit_event` (`allowed_warning`, `rejected`) then an ok result | | `turn_end ok` only |

Answer to "is it a plain `error` with text only": **yes, on both**. a1 and a4 (a usage limit and a rate limit) give the same events, and b2 and b3 as well; only the text differs.
The existing test in `src/chat/claude.test.ts:254` pins this behaviour for Claude (the `error` event equals the CLI's text, the synthetic model is not kept).
In b3 the synthetic message text reused the limit text by mistake of the script; it does not change the result, since the adapter ignores `message.error`.

## D4. Table per harness

### Claude (CLI 2.1.325, SDK 0.3.311)

| Signal | Exact field or text | Structured or text | Usage limit vs retried rate limit | Reset time |
| --- | --- | --- | --- | --- |
| Primary: failed `result` | `type: 'result'`, `is_error: true`, `api_error_status: 429`, `api_error: 'usage_limit_reached'` (real capture) | structured, but `api_error` is `@internal` and not in the `.d.ts`; `api_error_status` is typed | yes: the CLI says the other `rate_limit` refusals never carry it (a throttle, an org-policy refusal, an API-key 429, a capacity switch-off). A transient 429 is retried first (`system/api_retry`, typed) and, if it fails at the end, has no `api_error` (b3 is constructed; UNVERIFIED on a live throttle) | `result.result` text `resets 12:40pm (America/Montevideo)`: local time of the machine with an IANA zone name; weekly limit gives a weekday (`resets Mon 9am` in the existing test, constructed). No timestamp on the `result` |
| Structured reset: synthetic `assistant` | `api_error_params.rate_limit_info.{status: 'rejected', rateLimitType, resetsAt, overage*, limitScope}` on the same line as `api_error: 'usage_limit_reached'` | structured, `@internal`, per the binary's schema (not captured) | yes, same key | `resetsAt` epoch seconds (timestamp); the record is never updated, compare with the clock |
| Structured reset: `rate_limit_event` | `rate_limit_info.status === 'rejected'`, `resetsAt`, `rateLimitType` (`five_hour`, `seven_day*`, `overage`) | structured and typed in the `.d.ts`; only for claude.ai subscriptions | a `rejected` window alone "does not mean requests are refused" (the CLI's own words for per-window records), so it is a hint, not the key | `resetsAt` epoch seconds; also `overageResetsAt` |
| Text fallback | `result` starts with one of `USAGE_LIMIT_ERROR_PREFIXES` (`"You've hit your"`, ...) | text, but exported and versioned by the SDK | yes (they list only genuine limits; warnings and transitions are separate lists) | same text |
| Not a signal | `assistant.error === 'rate_limit'` | typed | no: throttles and limits share it | none |
| Not a signal | `terminal_reason: 'api_error'` | typed | no: any API failure | none |

### Codex (0.167.2)

| Signal | Exact field or text | Structured or text | Usage limit vs retried rate limit | Reset time |
| --- | --- | --- | --- | --- |
| Primary: `turn/completed` `params.turn.status === 'failed'` with `turn.error.codexErrorInfo === 'usageLimitExceeded'`, and the `error` notification with the same `error.codexErrorInfo` and `willRetry: false` | `CodexErrorInfo` string | structured (generated schema); real value on a real failure UNVERIFIED | yes: a retried rate limit is `rateLimitExceeded` and `willRetry: true` on the `error` notification (the retry is inside Codex; the notice is a `Reconnecting...` text per `agent-usage-limit-signals.md`); after retries run out, `responseTooManyFailedAttempts { httpStatusCode: 429 }` / text `exceeded retry limit, last status: 429` | not in `TurnError`. Two sources: (1) `account/rateLimits/read` right after, `rateLimits.primary/secondary.resetsAt` (or `rateLimitsByLimitId`), epoch seconds, observed; the window that is `usedPercent >= 100` is the one that blocks; (2) the tail of `message`: `Try again at 3:45 PM.` / `Try again at Nov 17th, 2026 3:45 PM.` / `Try again later.`, local time, no zone or offset |
| Companion: `account/rateLimits/updated` notification | `rateLimits` snapshot, `rateLimitReachedType`, windows | structured, sparse (merge) | `rateLimitReachedType` is `rate_limit_reached` even for the plan limit observed here; do not classify on its name | `resetsAt` epoch seconds |
| Text fallback | `message` starts with `You've hit your usage limit`, `You hit your spend cap`, `Your workspace is out of credits`, `Quota exceeded.` (engine harness list) | text | yes, for those texts | tail of the message |
| `codexErrorInfo` is `null` or an unknown string or object | | | treat as not a usage limit unless the text matches | |
| Not a signal | `httpConnectionFailed.httpStatusCode: 429` and `responseTooManyFailedAttempts` | structured | no: a 429 that was retried to exhaustion is not the plan limit (the usage limit body is a distinct `usage_limit_reached`, mapped to `usageLimitExceeded`) | |

Other `CodexErrorInfo` worth keeping apart: `sessionBudgetExceeded` (a budget, UNVERIFIED whether it resets), `unauthorized`, `serverOverloaded`, `modelNotFound`, `policyCapacityUnavailable`.

### What Carrier's `error` event would need

Today `{ kind: 'error'; text: string }`. To carry the classification:

- `reason`: at least `'usage_limit'`, `'other'` (a retried-to-exhaustion rate limit and an auth failure may get their own later; not needed for this feature).
- `resetsAt?: number` (epoch ms, as `src/usage` already stores it) when the provider gives a timestamp (Claude's `rate_limit_info.resetsAt` x 1000, Codex's `account/rateLimits/read` window `resetsAt` x 1000), and `resetText?: string` (or keep it inside `text`) for the case where only the CLI's local-time words exist.
- The agent that ran out is known by the session, not by the adapter; the host adds it. For Codex the limit is per window and per `limitId` (`codex`, or a model alias), and for Claude per `rateLimitType`; a `window` label (`five_hour`, `seven_day`, `weekly`) could ride along, UNDECIDED.
- `text` stays: it is the fallback for a client that does not know `reason`.

How each adapter would fill `resetsAt` (inferred, not built): Claude keeps the last `rate_limit_event` with `status: 'rejected'` (and the synthetic message's `api_error_params.rate_limit_info`) while the turn runs and reads its `resetsAt` when the `result` says `usage_limit_reached`; Codex, on a `usageLimitExceeded` failure, calls `account/rateLimits/read` (a second app-server, as `src/usage/probes.ts` does, or the same process: the request works on the running conversation, UNVERIFIED) and takes the blocking window's `resetsAt`, falling back to the message tail.

## Surprises

- The installed Codex account is at 100% of a 30-day window right now (`ordinaryUsageAllowed: false`); a real Codex turn could not have been run anyway, and the snapshot calls this state `rate_limit_reached`.
- The Claude fixture is a real capture and already classified by the engine harness through `api_error: 'usage_limit_reached'`; the chat adapter, in the same repo, does not read that field.
- `api_error` and `api_error_params` are not in the SDK's types (0.3.311) but are in the CLI and documented there as `@internal`; the SDK-typed field that is stable (`rate_limit_event.rate_limit_info.resetsAt`) is only a hint of a rejected window.
- The synthetic message is emitted twice today: as an `assistant` event and as the `error` text.
- `result` carries `api_error` but not `api_error_params`: the structured reset is on other messages.
- Codex's `error` notification is dropped in full by the chat adapter, including `willRetry`.

## UNVERIFIED

- A real Claude usage limit stream: the order and content of `rate_limit_event`, the synthetic assistant line and the `result` (only the `result` is captured; the other two are read from the binary's schema and the types). Whether `rate_limit_event` with `rejected` arrives before the failed `result`.
- A real Codex failure on app-server: whether `turn.error.codexErrorInfo` on `turn/completed` is populated (the types say it can be), whether the `error` notification precedes it, and the real `message` for each plan. No turn was run; Codex 0.167.2 here is exhausted, and replay was the only option.
- Whether `account/rateLimits/read` on the conversation's own app-server process answers during or right after a failed turn (it answered on a fresh process).
- Which Codex `limitId` and window blocks a model-specific limit (`rateLimitsByLimitId` had only `codex` here).
- Claude on an API key, Bedrock or Vertex: per the binary's comment, a 429 there never carries `usage_limit_reached` and the SDK's `rate_limit_event` is for claude.ai subscriptions only; what the failure looks like is not checked.
- Whether a live Claude throttle ends as `result` 429 without `api_error` (b3 is constructed).
- The zone behaviour of Claude's text for a weekly limit and the format in other locales.
- Antigravity: outside this part.
