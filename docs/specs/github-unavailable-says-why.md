# GitHub unavailable says why

Status: spec

## Problem

When GitHub fails, Carrier logs and shows only "GitHub unavailable", so the failure cannot be diagnosed afterwards. On the first start of a real run the panel showed `GitHub is unavailable: it will be tried again` and `REPOS GITHUB REFUSED ▲ melisource/fury_team-hub-dollar`, and `orchestrator.log` held two `[error]` lines with `"error":"GitHub unavailable"` and a stack ending in `createLabel`. Nothing said whether it was an HTTP 403, a 5xx, a timeout or a network error. The next poll succeeded and the same calls run by hand worked, so the failure was transient and its cause is lost for good. It matters to whoever leaves Carrier running and finds the repo marked refused: with the reason they can tell a rate limit from an outage from a bad network, and without it they can only wait and hope.

The reason exists. `GitHubUnavailable` keeps it in `cause` (`HTTP 403`, `timed out after N ms`, the first 300 characters of `gh`'s stderr) and in `retryAfterMs`. It is lost on the way out: the engine logs the error with `log.error('poll failed', e)`, and `@ashulab/universal-logger` writes for an `Error` only `error: message` and `stack`; its serializer drops `cause`. Carrier's own logger only redirects `console.*` to the file through `redact`, so the loss is not there. The per-repo reason shown by the panel and the app is the constant `GitHub is unavailable` (`engine.ts:691`).

## Solution

The reason goes into the error's message, not into the logger. `GitHubUnavailable` stays one class and gets a `kind`: `rate_limited` (HTTP 429, and 403 with a rate-limit body or `retry-after`), `server_error` (5xx), `timeout` and `network`. The message is `GitHub unavailable (<kind>: <detail>)`, where the detail is `HTTP 429`, `timed out after N ms` or the stderr of `gh` on one line. The `cause` string goes, since the detail now lives in the message and two copies would drift. `retryAfterMs` stays: it is the one thing the engine acts on, and a 5xx that carries `Retry-After` keeps it.

The message is what the library already writes as `error`, so every existing `log.error(…, e)` carries the reason with no change to the logger or the library, and so will any future one. The same message is the per-repo reason of the last check, so `REPOS GITHUB REFUSED` shows `GitHub unavailable (rate_limited: HTTP 403)` in the terminal panel and in the macOS app, which already print that string. The line at the top of the panel (`GitHub is unavailable: it will be tried again`) stays as it is.

The `kind` only diagnoses. The reaction does not change: the engine still waits `max(interval, retryAfterMs)` and retries on the next poll. A backoff for repeated 5xx or network failures would be a policy invented before any log shows how often each kind happens; with the kind in the log that decision can be made with evidence.

Token safety: the stderr detail is a child's output, which `AGENTS.md` says never to echo when it could hold a token. The log path already goes through `redact`, but the per-repo reason reaches the panel and the app over the control socket without it. So the stderr is redacted where it is captured in `src/integrations/github.ts`: redact first, then collapse whitespace, then cut to 300, so a token cut in half cannot slip through. The other details are fixed text built from a status or a duration.

What was cut. Making the library serialize `cause` fixes every error type but needs a release of a dependency this repo does not own, and the next error with a `cause` would still depend on it. Logging `cause` and `retryAfterMs` as context at the two engine sites repeats the fix at every call site and leaves the panel without the reason. Three error classes instead of a `kind` would make every `instanceof GitHubUnavailable` (`engine.ts:132`, `:693`, `:769`) learn three types for nothing. Showing the reason in the panel's top line was left out because the per-repo line already says it where the person looks. Nothing matches the old constant message, so the change breaks no code. The `'github unavailable'` of the control socket (`ResumeRefusal`, `availableRepos`) is a different string, a contract with the app, and does not change.

## Scope

1. As Diego, when GitHub fails, the `error` of the log line (`poll failed`, `startup step failed`) says the kind and the detail, for example `GitHub unavailable (server_error: HTTP 502)`, so I can diagnose it after the fact.
2. As Diego, a rate limit, a 5xx, a timeout and a network error each say which one they are, in the log and in the per-repo line.
3. As Diego, `REPOS GITHUB REFUSED` shows that same reason next to the repo, in the terminal panel and in the macOS app.
4. As Diego, a network error shows what `gh` said, on one line and at most 300 characters, and a token in it never appears in the panel, the app or the log.
5. As Diego, nothing else changes: the same failures are retried at the same times, and the top line of the panel reads as before.
6. As someone reading `docs/troubleshooting.md`, I find that the log and the refused line carry the kind and what it means.

## Decisions

The error, in `src/orchestration/github.ts`. The class has no parameter properties because Node strips types at runtime and cannot run that syntax, as the file already notes.

```ts
export type UnavailableKind = 'rate_limited' | 'server_error' | 'timeout' | 'network';

export class GitHubUnavailable extends Error {
  readonly kind: UnavailableKind;
  readonly retryAfterMs?: number;

  constructor(kind: UnavailableKind, detail: string, retryAfterMs?: number) {
    super(`GitHub unavailable (${kind}: ${detail})`);
    this.kind = kind;
    this.retryAfterMs = retryAfterMs;
  }
}
```

The three places that build it, all in `src/integrations/github.ts`: `statusFailure` gives `rate_limited` for a 429 and for a rate-limited 403, `server_error` for any 5xx, both with detail `HTTP <status>` and the wait it computes; the timeout gives `timeout` with `timed out after N ms`; the network stderr gives `network` with `redact(stderr)` collapsed to one line and cut to 300. The wait stays the third argument, so `new GitHubUnavailable('server_error', 'HTTP 503', 5000)` is the 503 with `Retry-After: 5`. `redact` is imported from `src/logging/redact.ts`, which has no imports of its own. An empty detail cannot happen: the network branch is only reached when the stderr matched a network pattern, so it is not empty.

The engine, in `src/orchestration/engine.ts:691`: the reason of the repos not read in a failed poll is `e.message` for a `GitHubUnavailable` and stays `authentication error for profile …` for an `AuthError`. `failed`, the backoff at `:693` and the refusal at `:769` do not change.

`docs/troubleshooting.md` line 38 (GitHub is down or rate limiting) gets one sentence: the log and the refused line say which kind it was.

Testing seams. Stories 1, 2 and 4 go through `src/integrations/github.test.ts`, the seam that already drives `GhGitHub` with a fake `gh` and observes what it throws: the `failures` block's cases (429 with `Retry-After`, 403 with a rate-limit body, 502 and 503, network stderr, the timeout) also assert the message, one per kind; a network stderr that holds a token (`ghp_…`) shows `[redacted]` in the message and not the token, with a stderr longer than 300 characters and a newline in it coming out cut and on one line. Stories 3 and 5 go through `src/orchestration/engine.test.ts` with its fake GitHub: the case that pins the last check of a repo not read (`error: 'GitHub is unavailable'`, line 224) now pins the message of the error the fake throws, the auth case is untouched, and the backoff test keeps passing with its hand-built errors moved to the new constructor, which is the proof that the reaction did not change. Story 1 needs no test at the logger: the library writes `error.message` as `error`, and `logger.test.ts` already pins that (`parsed.error` is the message). Story 6 has no test; it is one sentence in a doc.

## Out of scope

- Any new reaction by kind: no backoff for 5xx or network failures, no retry inside `ensureLabels`. A transient failure on `createLabel` still marks the repo as refused until the next poll; the "retried every cycle" behaviour is by design and is revisited when the logs show whether a retry would have helped.
- A per-call trace of the `gh` invocations. The log of the failed run held three lines; a trace is its own feature and the reason in the error covers the diagnosis asked for.
- Changing `@ashulab/universal-logger` to serialize `cause` or extra fields.
- The `'github unavailable'` strings of the control socket and the app's `ResumeRefusal`.
- Telling HTTP failures that are not `GitHubUnavailable` (`HttpError`, `AuthError`) apart any better.
