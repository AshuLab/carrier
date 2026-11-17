# Spike B (Codex): per-tool approval, config merge, sandbox and policy cells, models, and a real usage limit

Run on 2026-11-16 with the user's own `codex app-server` 0.167.2 (the one installed here), in temporary folders under `/tmp` that the scripts removed.
Scripts are in `codex/`, raw JSON-RPC logs (bearer token replaced by `<TOKEN>`) in `codex/logs/`.

**About the mock, read this first.** The Codex account on this machine is out of quota until 2026-11-20 7:11 PM, so a real model turn fails.
`codex/mock.ts` is a scripted fake of the Responses API on loopback (`model_provider="mock"` through `-c`); the REAL `codex app-server` runs and its REAL approval, elicitation, sandbox and config layers decide, while the "model" only issues the tool calls a script lists.
Every result marked **mock** is therefore evidence about Codex's own layers and none about how a real model behaves (whether it retries after a refusal, asks for an escalation, or picks `apply_patch`).
Text that the model "sees" was recorded from the request body Codex sent to the fake, so it is what a real model would receive.
Exactly **2 real turns** were used (`logs/turns-used.txt` = 2, both inside `b4.ts`); both failed at the provider (B4, B5). Every other turn is **mock**. `model/list`, `account/rateLimits/read` and the two `thread/start` calls of B4 are real and spend nothing.
The chat MCP is Carrier's own `startMcpServer` with two toy tools: `ping_read` (`readsAsSession`) and `ping_act` (`actsAsSession`), no annotations; the token only lives in the environment and in the redacted logs.

Checked against the raw JSONL, not the scripts' summaries: B1 (a parser over all 46 `b1-*.jsonl`), B2 (the `mcpServerStatus/list` and `config/read` answers of `b2-A0..A4`), B3 (item notifications of the six logs), B4/B5 (`b4.jsonl`).
Two finishing scripts were added: `b6.ts` (what the model receives, persistence across tools, curl with its exit code) and `b7.ts` (workspace-write with a folder that is not under `/tmp`).

## B1. One tool asks while the other is pre-approved (all rows: mock)

Variants as the scripts name them (every one set through `thread/start` `config` as `mcp_servers.carrier-chat`): **V0** server `default_tools_approval_mode = "approve"`; **V1** server `approve` plus `tools.ping_act.approval_mode = "prompt"`; **V2** server `prompt`; **V3** nothing set (the default, `auto`); **V5** nothing for the server plus `tools.ping_read.approval_mode = "approve"`.
Script per run: call `ping_read`, then `ping_act`, then say done; sandbox `workspace-write`.
Cells: which tool raised `mcpServer/elicitation/request`, and what happened to the call.

| Variant | `untrusted` and `on-request` (same result in both) | `never` |
| --- | --- | --- |
| V0 | no request; both ran, whatever the answer | no request; both ran |
| **V1** | **request for `ping_act` only**; `ping_read` ran with no request | no request; `ping_read` ran, `ping_act` failed with the denial text |
| V2 | request for `ping_read` and for `ping_act` | no request; both failed with the denial text |
| V3 | request for both, and the request offers `persist` | no request; both failed |
| **V5** | **request for `ping_act` only**, and the request offers `persist`; `ping_read` ran | no request; `ping_read` ran, `ping_act` failed |

What the answers do to the call (V1 and V5 `ping_act`, same in V2 and V3 for both tools; the turn ended `completed` in every case, the scripted model then said "done"):

| Answer | Call | Item error | Text the model receives as the tool output | Server executed it |
| --- | --- | --- | --- | --- |
| `accept` | completed | none | `"ping_act-ok"` | yes |
| `decline` | failed | `user rejected MCP tool call` | `user rejected MCP tool call` | no |
| `cancel` | failed | `user cancelled MCP tool call` | `user cancelled MCP tool call` | no |
| none asked, policy `never` | failed | `MCP tool call requires approval, but approval policy is never` | exactly that text | no |

`cancel` did not interrupt the turn: it ended `completed`, as with decline. What a real model does next is UNVERIFIED.
The answer sent was `{ action, content: {} }` for accept and `{ action, content: null }` for the others.

**What the request carries** (full params of one, V1, with the call `ping_act({note: "hello world"})`):

```
params keys: threadId, turnId, serverName, mode, _meta, message, requestedSchema
serverName: "carrier-chat"   mode: "form"
message: Allow the carrier-chat MCP server to run tool "ping_act"?
requestedSchema: {"type":"object","properties":{}}
_meta: {
  codex_approval_kind: "mcp_tool_call",
  tool_name: "ping_act",
  tool_description: "Toy ping_act: returns a fixed string.",
  tool_params: {"note":"hello world"},
  tool_params_display: [{"name":"note","value":"hello world","display_name":"note"}]
}
```

- The tool is named in `_meta.tool_name` and in `message`; the arguments are in `_meta.tool_params` (the object) and `_meta.tool_params_display` (name, value, display name).
- `_meta.persist: ["session","always"]` is present **only when the tool is in `auto` mode** (V3, V5). In V1 and V2, where `prompt` was set explicitly, the key is absent.
- No annotation-hint key appeared; the toy tools carry no annotations, so whether hints appear when they exist is UNVERIFIED.

**Persistence** (accept answered with `_meta: { persist: "session" }`; calls: `ping_act` twice in one turn, once in a second turn, once in a second thread of the same app-server):

| Variant | Same-turn second call asks | Next turn asks | Other thread asks | Verdict |
| --- | --- | --- | --- | --- |
| V1, V2 (request has no `persist`) | yes | yes | yes | key ignored; 4 requests for 4 calls, same as a plain accept |
| V3, V5 (request offers `persist`) | **no** | **no** | yes | key name that worked: **`_meta.persist = "session"`**; the allowance is per thread |

The allowance is per tool: after it for `ping_act`, `ping_read` still asked in V3 (b6). It did not depend on the arguments (first call had `note`, the second had none).
`"always"` was not tried on purpose: it would write the person's own configuration. UNVERIFIED.

**Config given at `thread/resume`:**

| Case | Result |
| --- | --- |
| Thread not loaded, resumed in a fresh app-server with V1 config | applied: request for `ping_act` only, both tools ran |
| Same, resumed with V2 config | applied: request for both |
| Thread still running in the same app-server, resumed with V1 over a thread started as V0 | **not applied**: `ping_act` ran with no request |

So a per-tool setting is read when a thread is loaded into a process, not on a `thread/resume` of a thread that process already holds. (Only approve to prompt was tried on the running thread.)

## B2. Does `thread/start` `config` merge with the person's own configuration

Only server names are listed. Person's own config: `computer-use`, `node_repl`, `sass_blueprint` (via `config/read`). `mcpServerStatus/list` with the thread id also shows the harness's own `codex_app`, `codex_apps`, `cua_repl`. Not mock-dependent (no model call).

| Run | `thread/start` config | Servers on the thread |
| --- | --- | --- |
| A0 | none | person's servers and Codex's own |
| A1 | injects `carrier-chat` | **all of A0 plus `carrier-chat`** (connected, 2 tools) |
| A2 | injects `carrier-chat`, app-server started with `-c mcp_servers.second-by-cli=...` | A0 plus `second-by-cli` plus `carrier-chat` |
| A3 | none, same `-c` | A0 plus `second-by-cli`; **no `carrier-chat` left from A1/A2**, so the injection is not written to the person's file |
| A4 | injects `carrier-chat`, started with `-c mcp_servers={}` | A0 plus `carrier-chat`: the empty `-c` did not blank the person's list |

Answer: **merge**, and per thread only. `config/read` (no thread) never shows the injected server, as expected.
Not checked: a collision with a same-named server of the person (UNVERIFIED).

## B3. What each sandbox and policy lets a shell command do without asking (all rows: mock)

Every approval was answered `decline`. The model's tool is `exec_command` (a login `zsh`); two extra probes: `apply_patch` into the folder (a1.txt) and a write under `/var/tmp`.
Cells: **ran** (no request), **asked** (a request arrived; not run), **refused** (no request, the sandbox or policy stopped it). "On disk" confirmed with `existsSync`.

| Sandbox / policy | a.txt in the folder (shell) | a1.txt in the folder (`apply_patch`) | b.txt in a new folder under `/tmp` | same under `/var/tmp` | `curl -sI https://example.com \| head -1` | `ls` |
| --- | --- | --- | --- | --- | --- | --- |
| `read-only` / `untrusted` | asked | asked | asked | asked | asked | asked |
| `read-only` / `on-request` | refused (sandbox, `operation not permitted`, exit 1); not on disk | **asked** (file-change request) | refused (`Operation not permitted`); not on disk | refused | ran, no network (below) | ran |
| `read-only` / `never` | refused (sandbox) | refused: `patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings` | refused | refused | ran, no network | ran |
| `workspace-write` / `untrusted` | asked | asked | asked | asked | asked | asked |
| `workspace-write` / `on-request` | **ran**, on disk | **ran**, on disk | **ran**, on disk | refused (`Operation not permitted`) | ran, no network | ran |
| `workspace-write` / `never` | **ran**, on disk | **ran**, on disk | **ran**, on disk | refused | ran, no network | ran |

- Under `untrusted` even `ls` asks, in both sandboxes. A request offers `accept`, `acceptWithExecpolicyAmendment` and `cancel` as its decisions.
- Network: `curl` does not reach the network in either sandbox. b6 ran it with its exit code in `read-only`/`on-request`, `workspace-write`/`on-request` and `workspace-write`/`never`: `curl: (6) Could not resolve host: example.com`, exit 6, and the same command run by hand outside the sandbox returned `HTTP/2 200`. The first script's empty output with exit 0 was the pipe to `head` hiding the failure.
- `/tmp` is writable in `workspace-write` beyond the working folder, and b7 shows it is so when the folder is **not** under `/tmp` (a scratch folder in this spike folder): `a.txt` and the `/tmp/cdxb-out-*/new/b.txt` both on disk. `/var/tmp` is not. In `read-only` the `/tmp` write was refused (b7's "on disk" flag for that row is stale from the previous iteration; the model-visible text was `operation not permitted`).
- A shell command that the sandbox made fail (exit 1) produced **no `commandExecution` item** at all in the notifications of these runs: all items in the six logs have exit 0 or were `declined`. Only the model's tool output shows the failure.
- b7 also asked for a `mktemp -d` command that ended with `rm -rf`, in both sandboxes under `on-request`: a request arrived. Which part caused it was not isolated. UNVERIFIED.

## B4. Models (real, no quota needed for the listing and for `thread/start`)

| Item | Observed |
| --- | --- |
| `initialize` | 28 ms |
| `model/list` | 2 ms (one sample); `includeHidden: true` 1 ms; `nextCursor: null`; no price field in an entry |
| Visible models | `gpt-6-luna` (isDefault, "Fast and affordable model for easier tasks."), `gpt-5.6-terra` ("Older balanced model for straightforward work."), `gpt-5.6-luna` ("Older fast and efficient model.") |
| Hidden models | `gpt-reserve` ("Fast and affordable agentic coding model."), `codex-auto-review` ("Automatic approval review model for Codex.") |
| Reasoning efforts | `low, medium, high, xhigh, max` for the luna models and `gpt-reserve`; `terra` adds `ultra`; default effort `medium` everywhere |
| Cheapest | **UNVERIFIED** by price (the list has none). By description `gpt-6-luna` and `gpt-5.6-luna` are the "fast" ones; `gpt-6-luna` is also the default, so it was used |
| `thread/start` with `gpt-6-luna` | OK in 51 ms, echoes `model: gpt-6-luna` |
| `thread/start` with `no-such-model-xyz` | **OK in 28 ms**, echoes `model: no-such-model-xyz`; no error |
| First turn on the invalid model | `warning` notification at `turn/start`: `Model metadata for \`no-such-model-xyz\` not found. Defaulting to fallback metadata...`; then, 2.5 s after `turn/start`, `thread/status/changed` `systemError`, an `error` notification with `codexErrorInfo: "modelNotFound"`, `willRetry: false`, message `The 'no-such-model-xyz' model is not supported when using Codex with a ChatGPT account.`, and `turn/completed` failed carrying the same error |

So an invalid model is accepted at `thread/start` and fails only at the first turn, as on Claude (A3). The provider checked the model before the quota: the invalid-model turn answered `modelNotFound`, not the usage limit that the valid model got seconds earlier.
The models the account may actually use is UNVERIFIED (the valid model's turn hit the limit before answering).

## B5. The first real capture of a Codex usage limit (real turn, `gpt-6-luna`, `effort: low`, `sandbox: read-only`, policy `never`, via `b4.ts`)

Order of notifications after the user message item, taken from `b4.jsonl`:

1. `account/rateLimits/updated`: `rateLimits` with `limitId: "premium"`, `primary: null`, `secondary: null`, `credits: { hasCredits: false, unlimited: false, balance: null }`, `rateLimitReachedType: null`. It carries **no reset time and no reached type**.
2. `thread/status/changed`: `status: { type: "systemError" }`.
3. **`error`**: `{ error: { message, codexErrorInfo: "usageLimitExceeded", additionalDetails: null, misalignment: null }, willRetry: false, threadId, turnId }`.
4. `thread/readState/changed`.
5. **`turn/completed`**: `turn.status: "failed"`, `turn.error` is the same object as in 3 (same message, `codexErrorInfo: "usageLimitExceeded"`), `turn.items: []`, no agent message item.

The message text, exactly (the apostrophe is U+2019, a curly one):
`You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 20th, 2026 7:11 PM.`
The failure came about 1 s after the user message item, and 3.0 s after `turn/start`.
The time in the text, 7:11 PM, equals the `resetsAt` of an `account/rateLimits/read` made minutes earlier (`primary.resetsAt` 1795212671 = 2026-11-20T22:11:11Z) in UTC-3, so the text is local time with no zone, as part D said.

Against `results-limits.md` (part D):

| Part D's statement | Real capture |
| --- | --- |
| `codexErrorInfo` = `usageLimitExceeded` on the `error` notification and on `turn/completed`'s `turn.error`; `willRetry: false` | **agrees**, both carry it |
| The `error` notification comes first, then `turn/completed` failed | **agrees** (order was error, readState, completed) |
| The reset time is not in the error; it comes from `account/rateLimits/read` or the message tail | **agrees**; the companion `account/rateLimits/updated` was sparse too (`primary` null) |
| `rateLimitReachedType` does not name a usage limit (`rate_limit_reached` in the read) | **agrees**, and in the failure's own notification it is `null` |
| The text is `You've hit your usage limit. Try again at ...` (constructed) | **disagrees in two places**: the apostrophe is U+2019, and the free-plan text is `...Upgrade to Plus to continue using Codex (...), or try again at <date>.` |
| The engine harness matches the text with `startsWith("You've hit your usage limit")` | **would not match the real text**: `src/harnesses/codex.ts` uses a straight apostrophe, the capture has a curly one. This is about the app-server's text; the `codex exec --json` text was not captured (UNVERIFIED that it is identical) |
| Real `codexErrorInfo` value on app-server was UNVERIFIED | now **verified** for this plan (free, 100% of a 30-day window) |

## Not checked (UNVERIFIED)

- Any real model behaviour: whether a model asks for escalation, retries after `user rejected`, or stops on `cancel`; whether it picks `apply_patch` or a shell write.
- What an `accept` of a command or file-change request does (sandboxed or not): every command approval was declined.
- `_meta.persist = "always"` (it would write the person's config); persistence of one tool covering another (it does not, in the one pair tried).
- Annotation hints in the request when a tool has them, and the behaviour of `auto` with a `readOnlyHint` tool: Carrier's tools have none today (`src/chat/mcp.ts`), and the toy neither.
- A same-named server in the person's config versus the injected one.
- The per-tool resume result for prompt to approve on a running thread (only approve to prompt tried); Codex 0.122.0 to 0.166.x (only 0.167.2 was run) and 0.169.0.
- The cheapest model by price; which listed models the account can use; whether `account/rateLimits/read` answers on the process that just failed (a fresh process answered in `limits.jsonl`).
- Usage-limit text for paid plans, `rateLimitExceeded` with `willRetry: true`, and the exec JSON text.
- Which part of `mktemp -d ... rm -rf` made it ask.

## Files

`codex/b1.ts`, `b2.ts`, `b3.ts`, `b4.ts`, `b6.ts`, `b7.ts`, helpers `lib.ts`, `mock.ts`, `toy.ts`; logs in `codex/logs/` (`b1-*`, `b2-*`, `b3-*`, `b4.jsonl`, `b6-*`, `b7-summary.txt`, `limits.jsonl`).
`codex/logs/b2-A0 person config only, thread without config.jsonl` is a stale log of an earlier version of `b2.ts`, superseded by `b2-A0.jsonl`.
