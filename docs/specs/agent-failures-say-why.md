# Agent failures say why

Status: spec

## Problem

When an agent execution ends badly, Carrier cannot say why, and Diego has to ask an agent to dig through the logs to find out. Every execution that does not end `ok` is stored with the same text, `the agent process ended with an error` (`src/orchestration/engine.ts:238`), and the epic's `lastError` is cleared as soon as the next result is imported (`engine.ts:407`), so a week later the only trace per execution is that generic line.

The real causes exist and are lost on the way. Of 86 executions in `carrier.db`, 15 failed, all between 19 and 25 October and none since. Nine were killed by SIGKILL (the agent's own `pnpm test` or `tsc` showing `Exit code 137`, in bursts of under a minute, with no sign of who sent it), four were `usage_limit_reached` (HTTP 429, `resets 12:40pm`) and two the logs do not explain. The four epics that had failures all ended merged, so what it cost was Diego's time finding out, not lost work. The stderr of all 15 is empty: for the 429 the cause is the `result` line in stdout, and for the kills it is nowhere.

It is lost in two places. `host-runner.ts:174` reduces the end of the process to `code === 0 ? 'ok' : 'failed'`, and Node's `close` event already hands over the signal, which is thrown away. And the adapters recognize only an authentication error (`claude.ts:47`, a 401), so a 429 or a 5xx reads like any other crash.

The root is observability: to know what failed without asking an agent, and to have the errors typed and recorded so that Diego can later decide what to do about each one with evidence.

## Solution

Every execution that ends badly gets a failure kind (glossary: Failure kind), a value from a closed list kept on the execution next to its status. The statuses stay as they are because the engine, the retry streak and the clients read them; the kind is added. An execution that ended `ok` or that Carrier itself stopped has none, and neither has one from before this change, which every surface shows as it does today.

The kinds are `usage_limit`, `api_error`, `killed`, `crashed`, `spawn_error`, `auth`, `session_lost`, `timeout`, `invalid_result` and `unknown`. The first two come from the adapter reading the final `result` of the agent: for Claude, `api_error_status` 429 with `api_error` `usage_limit_reached` is `usage_limit`, and any other numeric status except the 401 that already means `auth` is `api_error`. The next three come from how the process ended: a signal is `killed`, a nonzero exit is `crashed`, and a binary that cannot start or a command that cannot be built is `spawn_error`. The existing ends keep their statuses and gain their kind: `auth_failed` is `auth`, `session_unavailable` is `session_lost`, `timed_out` is `timeout`, and an invalid result is `invalid_result`. `unknown` is a failed process that none of the above explains. When an adapter and the process both say something, the adapter's reading wins, because it names the cause and the exit only the symptom; the exit code and signal are recorded either way.

The execution records the kind, a detail line, the exit code and the signal, and for `killed`, `crashed` and `unknown` the host's free memory and load at that moment, the only clues available about the unexplained 137s. Whether Carrier sent a signal needs no field: when it stops or times out a run the runner already knows, and the end is `stopped` or `timed_out`, so a `killed` is by construction a signal from outside.

The detail is the error text the adapter parses from the `result`, for example `You've hit your session limit · resets 12:40pm`, or the signal's name or the exit code; it is not a tail of stderr, which was empty in every real failure. It is redacted where it is captured, then collapsed to one line, then cut to 300 characters, in that order so a token cut in half cannot slip through, because it reaches the panel and the app over the control socket, which has no redaction of its own (the same reason `github-unavailable-says-why` redacts at capture).

The kind lives on each execution, so the history shows it after the epic's last error is gone: the control socket's sessions reply carries it for every execution, the terminal's stage history marks a failed stage with its kind, and the macOS app shows it where it lists an epic's executions. The epic's `lastError` and the `retries_exhausted` reason name the kind too, so the line that stops an epic says `killed: SIGKILL` and not only `the agent process ended with an error`.

It changes no reaction. The retries, their limit, the streak, `needs_human` and every status stay as they are, and a `usage_limit` still burns the retries in seconds until Diego decides on a policy with this data in hand.

## Scope

1. As Diego, an execution that ends badly has a failure kind, and one that ends `ok` or that Carrier stops has none.
2. As Diego, a Claude run that ends on a usage limit is `usage_limit` and its detail carries the reset time the agent printed.
3. As Diego, a Claude run that ends on any other API error status is `api_error` and its detail carries the status.
4. As Diego, a process ended by a signal is `killed` and says which; a nonzero exit is `crashed` and says the code; a binary that cannot start is `spawn_error`.
5. As Diego, an authentication error, a lost session, a timeout and an invalid result each have their kind, with the statuses and the reactions exactly as before.
6. As Diego, a `killed`, `crashed` or `unknown` execution also records the host's free memory and load at the moment it ended.
7. As Diego, the detail is one line of at most 300 characters, and a token in what the agent printed never reaches the database, the socket, the panel or the app.
8. As Diego, the history of an epic shows the kind of every failed execution after the epic's last error has been cleared, in `carrier status`, in the terminal panel's stage history and in the control socket.
9. As Diego, the epic's last error and the reason it stops with name the kind and its detail.
10. As Diego, nothing else changes: the same failures are retried at the same times, with the same streak and limit, and an execution from before this shows as it does today.
11. As Diego, the macOS app shows an execution's kind and detail where it lists the epic's executions, and an engine that does not send them still works.
12. As someone reading `docs/troubleshooting.md`, I find each kind, what it means and what to look at.

## Decisions

The kinds are a `const` list beside the execution states, and the runner reports a failure alongside the exit it already reports. `AgentExit` does not change.

```ts
// src/storage/executions.ts
export const failureKinds = ['usage_limit', 'api_error', 'killed', 'crashed', 'spawn_error', 'auth', 'session_lost', 'timeout', 'invalid_result', 'unknown'] as const;

// src/execution/agent-runner.ts
export type AgentFailure = {
  kind: (typeof failureKinds)[number];
  detail: string; // redacted, one line, at most 300 characters
  exitCode: number | null;
  signal: string | null;
  hostFreeMemMb: number | null; // only for killed, crashed and unknown
  hostLoad: number | null; // one-minute load average, same cases
};
// AgentRun.done: Promise<{ exit: AgentExit; sessionId?: string; failure?: AgentFailure }>
```

The execution gets nullable columns for each field (`failureKind`, `failureDetail`, `exitCode`, `signal`, `hostFreeMemMb`, `hostLoad`) through `pnpm db:generate`. They are columns and not one JSON value because Diego wants to ask the database how many `killed` there were this week. `error` stays and keeps its meaning, since `failureStreak` (`retry.ts`) breaks on `error === null`: it is still written only for the ends the engine retries, now as `the agent process ended with an error (<kind>: <detail>)`. A timeout has a kind and no `error`, as today, so the streak is untouched. The check that tells a lost session (`engine.ts:285`) compares `error` with a fixed string; it moves to the kind.

The adapters' `LineSignal` gets a `failure` next to `authFailed`: `{ kind: 'usage_limit' | 'api_error'; detail }`. Only Claude fills it, because it is the only harness with a failure seen on a real run. Codex and Antigravity keep their current signals, and their other failures are classified by the process alone, with what they printed in the detail.

The host's memory and load are `os.freemem()` and `os.loadavg()[0]`, read when the process closes. On macOS `freemem` counts only free pages and understates what is available, so it is a clue and not a measure; the next step if it proves noisy is the system's memory pressure, which needs a spawn and a parse and is not worth it before the first real kill shows what is useful.

The sessions reply gets `failure: { kind, detail, exitCode, signal, hostFreeMemMb, hostLoad } | null` on each session, additive within protocol 1, and the macOS decoder reads it as optional. The detail already passes through `redact` at capture; `sessionsOf` applies its own `safe()` again as it does for every agent-written text, so the socket does not depend on the capture alone.

Testing seams, per story. The logs of the real failures are the fixtures: the 429 `result` line is copied from the execution log of epic #302, and the `Exit code 137` runs are reproduced by a process that kills itself.

- Stories 2 and 3: `claude.test.ts` on `parseClaudeLine`, with the real 429 line and a line shaped like it with a 5xx.
- Stories 4, 6 and 7 (capture): `host-runner.integration.test.ts`, which already runs a real process against `fake-claude.fixture.mjs`; new modes for a usage limit, a self-kill with SIGKILL, a nonexistent binary, and a result that prints a token.
- Stories 1, 5, 9 and 10: `engine.test.ts` with the `FakeAgentRunner`, whose `Behavior` gets a `failure`; the rows, `lastError` and the `retries_exhausted` reason are read, and the existing retry, streak and timeout tests stay as they are, which is what pins story 10.
- Story 8: `control/sessions.test.ts` for the reply, and `dashboard.test.ts` and `plain.test.ts` for the stage history; `snapshot-contract.test.ts` for the shape the macOS app decodes.
- Story 11: `macos/Tests/CarrierCoreTests`, the decoder with and without the field, and a failed execution in the fixture server.
- Story 12: no tests, it is documentation.

## Out of scope

Any change to what Carrier does after a failure: retries, their limit, the streak, `needs_human`, the limits in the config. Fixing the kills; this only makes it possible to find out who sends them. Classifying past executions. Recognizing Codex and Antigravity failures beyond exit code and signal. A `network` kind, until a real one has been captured.

## Open questions

What does a network failure look like in each harness, and how do Codex and Antigravity report a rate limit or an API error? Neither `docs/research/codex-exec-stream.md` nor `antigravity-stream.md` saw a failed turn, and no network failure appears in the 86 executions, so the shapes need a real failing run to be captured. Until then those failures are `crashed` or `unknown` with what they printed in the detail, and `network` joins the list when a real one shows its shape.
