# How T3 Code switches provider in the middle of a thread

> Research of 2026-11-16, for [switch-and-delegate-between-agents](../specs/switch-and-delegate-between-agents.md).
> Sources: the `pingdotgg/t3code` repository at `main` on that date, shallow-cloned into a scratch folder and only read, and the release notes of v0.1.0.
> What was read is what the code and its own documents say; none of it was run.

## Short answer

T3 Code does not use an MCP to switch, and it does not ask an agent to summarize.
It starts a new conversation on the target provider and sends, with the first message, a budgeted selection of the messages it stored.
The selection lists what it left out, and the agent can fetch those items with an MCP tool that reads a thread.
Delegating to an agent of another provider is a different feature, `delegate_task`, and the release notes recommend it over a switch for combining harnesses.

## The switch

- The release notes of v0.1.0 call the switch supported with caveats: the new provider receives a limited selection of messages, and the old provider's reasoning, tool calls and results, and attachments do not carry over.
- `docs/user/portable-handoffs.md`: short conversations transfer intact; longer ones favour the original request, the recent requests and answers, and relevant command outcomes.
  Selected messages keep their full text, order and role, and the person's new request stays separate and is never shortened.
  Codex receives the messages as real history when its version supports it, and the other providers as attributed context.
  The handoff lists the omitted items, and the agent can read them with T3 Code's thread-reading tool.
- The budget, in the same document: 16,000 tokens by default, clamped between 1,024 and 64,000, with a separate 64,000-byte ceiling on imported history, and one token charged per UTF-8 byte so that it errs towards less.
  With no capacity information it assumes a 128,000-token window and reserves a quarter of it or 16,000 tokens, whichever is larger.
  If the target has no room, it starts a fresh conversation with a bounded selection and sends the request on its own.
- `packages/provider-core/src/server/handoffBudget.ts`: the selection adds the first user message, then walks from the newest message backwards until the cap is reached, and lists the ids of what was left out.
- `apps/server/src/orchestration-v2/ContextHandoffDelivery.ts`: the text tells the agent to recover an omitted item only when the request needs it, with `t3_thread_read` by `itemId`, and to continue a long item with `textOffset` until it returns null.
- `docs/internals/context-handoffs.md`: the portable handoff is textual and claims no parity with the provider's own context; each text item is compacted, and a file change carries only its name.
- `docs/orchestration-v2/provider-switching-and-context.md` is a design document: on returning to a provider used before, it recommends resuming that provider's native conversation and injecting a delta of what happened meanwhile, and starting a new one with the full selection when the resume fails or is stale.
  The user document does not say this is built.
- Pull request #1911 proposed compacting through the old provider and sending its summary instead.
  It was closed without a merge.
- Issue #4766 reported a switch that kept the visible messages and started a blank native conversation, and asked that a non-empty thread never starts blank.

## The MCP tools around it

- `t3_thread_read` takes a thread id, a view (`activity` among them), `afterPosition` to page, `itemId` and `textOffset` to read one long item in parts.
- `t3_thread_wait` takes `timeoutMs`; on a timeout the result says whether to end the turn or call again.
- `delegate_task` starts a child agent with only a task ("No parent history"), with `target` (provider instance, model, options), `isolation` of `shared` (default) or `worktree`, `mode` of `async` (default) or `wait`, a `timeoutMs` of at most 45 seconds for `wait`, and a `clientRequestId` so a retry after a lost reply does not start a second child.
  An async task returns a `taskId`, and the server wakes the parent when it ends, with the instruction not to poll.
  A question or an approval ends a wait.
- `task_status`, `task_cancel` and `t3_thread_send` read, stop and message a child; a message to a finished child starts a new task.
- A child's runtime mode can never be broader than its parent's (`runtime_mode_escalation_denied`), and the valid targets and options come from `orchestrator_capabilities`.
- A usage limit is classified in the adapters: on Codex from the app-server's structured error (`usageLimitExceeded`, plus `rateLimitExceeded` or an HTTP 429, all as `usage_limit`) with the reset time from the limits snapshot, and on Claude from the SDK's `rate_limit_event` and, for API keys and gateways, from the text of the error.
- In the web app, children are rows of a collapsible relationships section, with their status, the provider's badge and a count of failures.

## What was not found

- No test or document says how well a switched conversation keeps going; the release notes only call the handoff lossy.
- Whether the design document's native resume on return is built.
