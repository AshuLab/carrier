# Carrier — Autonomous epic orchestrator

Status: spec

## Problem

Diego wants to spend his time preparing several ideas, specs and tickets with Solve while agents implement the work that is already prepared. Today he has to chain implementation, external review and fixes by hand to reach a PR he can test. The goal is to delegate that coordination without delegating his decision to test and merge the final PR.

The expected result is that an epic marked `solve:epic:ready` enters execution with no manual follow-up between turns, ends with a final PR ready for test or an explicit reason for intervention, and can continue after the process is interrupted. Several epics can advance in parallel within a configured concurrency. The detailed definitions and decisions are in the [working document](../research/working-document.md) and the [glossary](../glossary.md).

## Solution

A standalone TypeScript app on Node.js 26, with ESM and pnpm, initially for macOS. It starts from any folder, reads a list of GitHub repos and keeps running with an informational panel in the same terminal. This scope was chosen to test the flow before investing in a web UI or an OS app. Diego decided to build the full scope described below (catalog of n identities, per-repo overrides, log retention, `unlimited` time); cutting it down to two fixed identities and global configuration was evaluated and rejected.

### Startup, single instance and configuration

One active instance per `orchestrator/` folder: before starting work the app takes an exclusive lock. A second instance reports that it is already running and exits. An unexpected shutdown does not leave the lock stuck, and two simultaneous startups cannot take it at the same time.

The app ships a default configuration and accepts a user JSON file that overrides it: objects are merged field by field, the user's simple values replace the defaults, and lists are replaced whole; an incompatible type is not silently converted. The resulting configuration is validated at startup with Zod, with errors that name the field and the problem, and the TypeScript types are inferred from those schemas. Required fields, types, allowed limits and references between profiles, repos and roles are validated.

Identity (GitHub profile), harness and model of author and reviewer have global values and per-repo overrides; each repo inherits whatever it does not replace. The author and the reviewer of the same PR must have different profiles after the overrides are resolved. The user declares the available profiles, including Diego's personal one, and chooses the orchestrator's profile for reading issues and updating labels; it can reuse one of the agents' profiles. Agent Forge resolves the authentication of each profile. When an epic starts, its effective configuration is saved, without credentials, and kept when it resumes even if the defaults change. A harness is the agent CLI that runs the loop and the tools: Claude Code and Codex at first, Antigravity (`agy`) added later. The model it uses comes from the harness's own cloud or, optionally, from a local server (LM Studio or Ollama) through Claude Code or Codex: an agent is a harness, a model provider and a model, three separate things ([glossary](../glossary.md)).

The initial limits, all configurable, are three simultaneous epics, five reviews, three execution retries, four hours per agent execution (or `unlimited`; zero does not mean infinite) and 30 s per short call to GitHub or Forge.

### Setup, checks and the terminal

`carrier init` writes the configuration: it looks at the machine, asks only what it cannot infer (repos, the identity, harness, model provider and model of each role), shows a recap, saves it to `~/.carrier/config.json` (the file `carrier` reads when there is no `--config`) and runs the checks. `carrier doctor` runs them on any config: the tools are installed, author and reviewer are really different identities, each identity can get a token for each repo, the orchestrator can read it, and a local model's server has the model; each failure comes with its remedy. `carrier schema` prints the JSON Schema of the file. Every question of `init` has a flag and `--yes` never asks, so an agent can set Carrier up too.

### Discovery and queue

Every 5 minutes by default (configurable, as is the wait before the first query at startup) the app queries all configured repos, walks all pages and records in SQLite the open epics with `solve:epic:ready` that it does not know yet. The epic is identified by repo and issue. The label is enough to queue; there are no webhooks or adaptive intervals. Selection order is FIFO by queue entry and is kept across restarts. Solve adds that label when it finishes its preparation, in its skills and outside this app.

If GitHub is down or rate-limits requests, the queue and state are kept, the error is shown and the query is retried at the next interval, or after the longer wait that GitHub indicates. A failed query never equals an empty list and does not consume agent retries. Every GitHub call runs with a short timeout.

### Execution and stage loop

When a slot is free, the scheduler reserves the oldest epic with an atomic SQLite operation; an epic never has two active executions. On reserving it, it checks that the issue is still open and ready, moves it to `solve:epic:running` and persists the start. Time in the queue does not count toward the execution limit.

The author invokes `ship` with the epic's identity, harness, model and context and leaves the final integration PR. Then the reviewer, with another identity and a separate checkout, receives spec, tickets, PR, SHA and context from earlier rounds, reviews with `code-review` and publishes the findings with `code-post`. If there are blockers and rounds remain, the author fixes or answers each finding and the reviewer reviews again, verifying fixes and regressions. The skills keep their reports; the caller agent interprets them and hands over one result JSON file per execution. The loop advances when that result arrives, without waiting for the polling interval.

The engine combines the stage with the caller result:

| Stage | Result | Next step |
| --- | --- | --- |
| `ship` | `completed` | review, round 1 |
| `review` | `completed` (conclusive, no blockers, checks confirmed on the reviewed commit) | `solve:epic:ready-for-test` |
| `review` | `changes_requested` | `fix` if the round is below the maximum; otherwise `needs_human` |
| `fix` | `completed` | review, next round |
| any | `needs_human` | `solve:epic:needs-human` with the reason |

A review that is inconclusive for lack of context is `needs_human` from the reviewer. A new commit invalidates the previous verdict: a commit that was not reviewed is never declared ready. Each imported result is validated against GitHub: the PR exists, is open, references the epic and its head matches the reported SHA. If the reference does not match, or the head changed during a review, the epic goes to `needs_human` with that reason; repeating the execution does not fix it.

Author and reviewer apply the repo's rules to choose and evaluate tests, CI and blockers; the engine does not ([ADR 0001](../adr/0001-separate-coordination-from-repo-evaluation.md)). Test/CI fixes and reruns are the agent's internal work and the engine does not count them. In a repo without CI, the review and the test evidence reported by the skills are enough, and the absence of CI is recorded. Diego tests the PR and decides the merge.

Technical failures (the agent process ends badly, missing or invalid JSON, transport error) are retried up to the configured limit, after the initial attempt. The retry is a new execution that resumes the session (or rebuilds the context) with the instruction to verify the real state first, so as not to duplicate PRs, comments or commits. It does not consume review rounds. Exhausting the retries, exceeding an execution's time limit or exhausting the rounds ends in human intervention; the timeout is not retried. A finding or a disagreement is not a technical failure.

### Epic outcomes

`solve:epic:ready-for-test` and `solve:epic:needs-human` replace `solve:epic:running` on the issue. An epic in human intervention stays stopped with its reason while the others advance; Diego resolves it outside Carrier and it is not reactivated from the app or on restart.

If the final PR is merged while there is active work, its executions are stopped, sessions and history are kept and no new turns are launched. If the epic's issue or its final PR is closed without merge, the epic is cancelled: its agents are stopped, what was done is kept and the reason is shown in the terminal. Neither merges nor closures of slices done by `ship` trigger these rules. The PR state check is technical coordination, not code evaluation.

An authentication error reported by Forge for a profile stops the epics that use it, with the reason in the terminal; the others continue. If the orchestrator's profile fails, its GitHub operations are suspended. The profile is never switched automatically.

### Agents on the host

The orchestrator runs on the system where it is invoked and the agents are the client's normal CLI (Claude, Codex) run as a child process on that same computer, with the user, login and permissions it already has, without additional isolation. The token's minimum scopes per role and the repos' branch protection are the boundary on GitHub. Hardening the security of unattended agents is left as later work. See [ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md), which supersedes [ADR 0003](../adr/0003-agents-in-containers.md).

The runner is our own, with one adapter per harness that translates the task into the CLI, prepares that execution's credentials without mixing them with those of a parallel one, and captures output, session and errors. Agent Forge is an external dependency for identity and credentials; no copy is incorporated. The orchestrator's GitHub operations go through the chosen profile, with `gh` via Forge.

### Shared root, state and logs

Solve and the app share a configurable root, by default `~/.solve/`: `repos/` for clones (separated by organization and name), `worktrees/` for the workspaces that Solve manages and `orchestrator/` for SQLite, results and logs. Sessions are stored by each CLI where it already does so, not in `orchestrator/`. The paths are shared to reuse Solve's work instead of creating another worktree structure. The location of the app's code is independent of the root.

Solve does not receive the root: it has no variable, flag or key for it. It derives the workspace from the Worktrees line of each repo's `docs/agents/solve.md` (by default `~/.solve/worktrees/<repo>/<feature>/`, with lanes `<feature>--lane-<N>`) and works in the clone where it is invoked, without managing clones. `repos/`, `orchestrator/` and `reviews/` belong to the app. That is why the app derives the workspace path, verifies it with `git worktree list` and saves the real one; it does not assume it. With a root different from the one in `solve.md`, each repo's `path` must match. Because the repo's folder name does not include the organization, the configuration rejects two repos with the same folder name. The `ship` task always asks to isolate the epic in a worktree, whatever the mode in `solve.md`.

The reviewer uses `<root>/reviews/<repo>/<epic>/` (the epic's issue number), a detached worktree (`--detach`) of the managed clone at the reviewed SHA, which each round repoints, outside `worktrees/` so as not to collide with Solve's paths. Agents are launched, and resumed, with the workspace's saved `cwd`: a resumed session operates in the `cwd` of the new process, not the original one. Spec, ADR and glossary prepared as files must be committed and pushed before setting `solve:epic:ready`; the epic and the tickets are read through `gh`. See [research](../research/shared-root.md).

SQLite, with Drizzle ORM, `better-sqlite3` and versioned Drizzle Kit migrations, is the authority for state; labels are its mirror and are reconciled at startup and after a failure ([ADR 0002](../adr/0002-sqlite-authority-labels-mirror.md)). Stored per epic: repo and issue, queue entry, workspace, final PR, stage, round, effective configuration, reviewed SHA, blockers, executions with their session, errors, caller results and event history. Importing a result and recording the transition happen in a single transaction and are idempotent. No tokens are stored in the state or in the logs.

The app uses `@ashulab/universal-logger` as its logger, without building another one. A central integration configures it and adds repo, epic, execution, role and stage context. Process logs go to `orchestrator/logs/orchestrator.log` and each agent's full output to `orchestrator/logs/executions/<executionId>/`, separate from SQLite and from the panel. An epic's logs and sessions are deleted 30 days after it ends or is cancelled (sessions are looked up by their id in each CLI's folders: `$CLAUDE_CONFIG_DIR/projects/*/<id>.jsonl` and `$CODEX_HOME/sessions/**/rollout-*-<id>.jsonl`); while it is still pending, interrupted or in intervention they are kept. The cleanup does not touch SQLite or the workspaces.

### Interruption and recovery

`Ctrl+C` stops the active executions, with their processes, without waiting for the stages to finish. Sessions, context, workspaces and uncommitted work are kept. On restart, processes and external effects are reconciled against GitHub before continuing, and an interrupted stage is not restarted blindly. If the session cannot be recovered, a new one is opened with the same identity, the persisted context and the real state of the workspace and GitHub, and the agent verifies what was left done; the recovery is recorded in the history.

If a repo was removed from the configuration, on restart its pending epics are stopped with that reason, keeping sessions, workspaces, history and order, without consuming retries or acting on the repo. When it is configured again they are recovered, except those that already required human intervention.

### Terminal panel

An informational panel drawn with ANSI sequences without dependencies, in the same terminal. It shows occupied slots, queued epics and, per epic, stage, round, blockers, time in the stage, last activity, links to the issue and PR, errors and intervention reasons. Stage and last activity are different data. Without an interactive terminal it emits plain lines. On a terminal it also reads a few keys (select an epic, open its PR or issue, read the output of its agent, check GitHub now, pause or resume taking new epics, help, quit); none of them changes what an epic does, and `Ctrl+C` still stops the process. The cursor is hidden while the panel runs and always given back.

## Scope

1. I run `carrier` from any folder with my configuration file and the app starts with the effective configuration (defaults plus mine), without depending on the current directory.
2. If the configuration is invalid (missing field, wrong type, reference to a nonexistent profile, author and reviewer with the same profile), the app prints each error with the field and exits without starting work.
3. I define identity, harness and model overrides per repo and the epic keeps the effective configuration it started with, also when resuming after the configuration changes.
4. If an instance is already running on the same folder, the second one reports and exits; if the previous one was closed abruptly, the next one starts.
5. Every interval the app records, once and in order of arrival, the open epics with `solve:epic:ready` from all configured repos, even if there is more than one page of results.
6. If GitHub fails or rate-limits requests, the queue and state are kept, the error is shown and the query is retried at the next interval or after the wait GitHub indicates, without consuming agent retries.
7. When a slot is free the oldest queued epic is started, never more than the configured concurrency nor two executions of the same epic, and the issue goes from `ready` to `running`.
8. On startup, the app creates in each configured repo the `running`, `ready-for-test` and `needs-human` labels that are missing.
9. The author runs `ship` as a host process with the epic's workspace and the engine records the final PR validated against GitHub.
10. The reviewer, with another identity and a separate checkout, reviews the final PR and its `completed` result leaves the epic in `ready-for-test` only if the reviewed SHA is the PR's current head.
11. If the reviewer requests changes and rounds remain, the author gets a fix turn and the reviewer reviews again; with the last round exhausted the epic goes to `needs-human`.
12. A `needs_human` result from the author or the reviewer, including an inconclusive review, stops the epic with the reason while the others continue.
13. A reference that does not match (PR of another epic, closed PR, SHA that is not the head, head that changed during the review) stops the epic in `needs-human` with that reason.
14. A technical failure is retried up to the configured limit with an execution that verifies the real state before continuing, without consuming rounds and without duplicating PRs, comments or commits; when exhausted, the epic goes to `needs-human`.
15. A missing, incomplete or invalid JSON result does not advance the stage and is treated as a technical failure; importing the same result twice does not duplicate the transition.
16. An execution that exceeds the time limit (or none with `unlimited`) is stopped, keeps its session and workspace and leaves the epic in `needs-human`, without retry.
17. If the final PR is merged with active work the epic is stopped without launching new turns, and if the issue or that PR is closed without merge the epic is cancelled with the reason in the terminal; merges and closures of slices have no effect.
18. A Forge authentication error stops only the epics of the affected profile; if it is the orchestrator's, its GitHub operations are suspended, and the profile is not switched.
19. With `Ctrl+C` the active executions and their processes are stopped without waiting and sessions, workspaces and uncommitted work are kept.
20. On restart, interrupted stages are reconciled with GitHub and the existing processes and are resumed with the session, or with a rebuilt context if it cannot be recovered, without duplicating agents or actions; epics in `needs-human` are not reactivated.
21. If I remove a repo from the configuration, on restart its pending epics are stopped with the reason and are recovered when it is configured again, except those that required intervention.
22. I see in the panel slots, queue and, per epic, stage, round, blockers, time in stage, last activity, links, errors and intervention reasons; without an interactive terminal I get plain lines.
23. Process logs and the full output of each execution end up in files under the root, without tokens and without interfering with the panel.
24. An ended or cancelled epic's logs and sessions are deleted 30 days later; those of a pending, interrupted or in-intervention epic are kept, and SQLite and the workspaces are not touched.

## Decisions

The skills and the repos keep their rules and formats; the coordination decisions are in [ADR 0001](../adr/0001-separate-coordination-from-repo-evaluation.md), [ADR 0002](../adr/0002-sqlite-authority-labels-mirror.md) and [ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md) (which supersedes [ADR 0003](../adr/0003-agents-in-containers.md)), and are not repeated here.

**Structure.** A single package, grouped by responsibility (the current folders are in the README). Everything a terminal user sees (the command line, the prompts, the setup wizard and the panel) lives under `terminal/`, so another front-end, a web UI say, is a sibling folder; what any front-end needs (the view of what Carrier is doing, `status/`, and the checks, `doctor/`) stays outside it. `config/` owns the configuration schema and `execution/` the caller-result schema; there is no general `utils.ts`.

**Versions.** The latest stable version of TypeScript, pnpm and each dependency is taken when implementing or updating, without prereleases, compatibility with Node 26 is checked and `pnpm-lock.yaml` is versioned with `packageManager` pinned. The runtime dependencies are `zod`, `@ashulab/universal-logger`, `drizzle-orm` and `better-sqlite3`; the tooling includes `drizzle-kit` and `vitest`. Drizzle, Drizzle Kit and `better-sqlite3` are installed and tested on macOS before building on them, because their current documentation shows RC releases.

**Single instance.** The lock is an exclusive SQLite transaction on a lock file in `orchestrator/`, with no wait, held by the process while it runs. The operating system releases it when the process dies, so there are no stale locks to tell apart. A second attempt receives `SQLITE_BUSY` and exits.

**Engine ports.** The engine (`orchestration/`) depends on two interfaces, `GitHub` and `AgentRunner`, and on an injected clock. `GitHub` exposes what the engine needs: list ready epics, change labels, read issue and PR state. `AgentRunner` launches an execution with task, profile and time limit, and returns its session, its technical termination and the JSON path, and can stop it. They exist so the engine can be tested with fakes; there is only one real implementation of each. The real `GitHub` implementation runs `gh` via Forge with `execFile`, without a shell, and validates the responses with Zod.

**States.** An epic is in `queued`, `running` (with its stage and round), `ready_for_test`, `needs_human`, `cancelled`, `merged` or `repo_removed`. An execution is in `running`, `finished`, `failed`, `timed_out`, `interrupted` or `invalid_result`. An interruption by `Ctrl+C` leaves the epic in `running` with its execution in `interrupted`; `repo_removed` does not change labels.

**Caller result contract.** The caller returns exactly one of the three results. `executionId`, `repo`, `epic` and `stage` repeat what the engine expected, to check the correspondence. `changes_requested` is only valid in `review`. A `completed` carries the result of the checks, and CI may be `absent`; a failed CI is not a `completed`. Validation was tested with empty inputs, wrong types, short or uppercase SHA, number 0 or non-integer, `repo` with extra slashes or a line break, empty `blockers` and `changes_requested` outside `review`; all are rejected.

```ts
const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
const Common = {
  executionId: z.string().min(1),
  repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/),
  epic: z.number().int().positive(),
  stage: z.enum(['ship', 'review', 'fix']),
  summary: z.string().min(1),
};
export const CallerResult = z.discriminatedUnion('outcome', [
  z.object({ ...Common, outcome: z.literal('completed'), pr: Pr,
    verification: z.object({ ci: z.enum(['passed', 'absent']), evidence: z.string().min(1) }) }),
  z.object({ ...Common, outcome: z.literal('changes_requested'), stage: z.literal('review'), pr: Pr,
    blockers: z.array(z.object({ title: z.string().min(1), url: z.string().url().optional() })).min(1) }),
  z.object({ ...Common, outcome: z.literal('needs_human'), reason: z.string().min(1) }),
]);
```

**Configuration.** The app's defaults include the root, the interval, the log level (`logLevel`, `info`) and the limits; profiles, repos and per-role assignments are always declared by the user. Each profile is `{ "kind": "forge", "agent": "<name in Forge>" }` (bot, via Agent Forge) or `{ "kind": "gh" }` (`gh`'s own login, for the personal account that Forge does not support); no secrets in the configuration. The shape was set by the [Forge spike](../research/agent-forge.md). Example of the shape, not of values:

```json
{
  "pollIntervalMinutes": 5,
  "repos": [{ "name": "AshuLab/carrier", "agents": { "reviewer": { "model": "<model>" } } }],
  "profiles": {
    "author-bot":   { "kind": "forge", "agent": "<forge-author-agent>" },
    "reviewer-bot": { "kind": "forge", "agent": "<forge-reviewer-agent>" },
    "diego":        { "kind": "gh" }
  },
  "orchestratorProfile": "author-bot",
  "agents": {
    "author":   { "profile": "author-bot",   "harness": "claude", "model": "<model>" },
    "reviewer": { "profile": "reviewer-bot", "harness": "codex",  "model": "<model>" }
  },
  "limits": { "maxConcurrentEpics": 3, "maxReviews": 5, "maxExecutionRetries": 3, "maxExecutionHours": 4, "githubCallTimeoutSeconds": 30 }
}
```

**Labels.** Carrier owns `solve:epic:running`, `solve:epic:ready-for-test` and `solve:epic:needs-human` and creates them in the configured repos if missing; `solve:epic:ready` belongs to Solve and is not created.

**Panel.** Drawn with ANSI sequences from the standard library, without TUI dependencies.

**Testing seams.** There is no code yet, so there are no existing seams. The widest ones that isolate each story are chosen:

- Stories 1 to 3: `loadConfig(defaults, user)` is a pure function that returns the effective configuration or the list of per-field errors. Unit tests with Vitest; they cover merging of objects, values and lists, incompatible type, references and the author-different-from-reviewer rule.
- Story 4: the function that takes the lock, on a real temporary folder, with two child processes and one terminated with `kill -9`.
- Stories 5 to 21, except 9 (which here only covers the coordination part): the engine through its public interface, with `GitHub` and `AgentRunner` simulated, an injected clock and a real temporary SQLite with migrations. A fake `AgentRunner` writes the JSON, fails, hangs or is cut depending on the case. Restarting the engine on the same database covers recovery and reconciliation.
- Stories 10 to 15: within the same seam, besides the engine's public interface, `parseCallerResult(raw, expected)` is a pure function with the table of cases from the contract section.
- Story 9: the coordination (launching the stage, validating the PR against GitHub, recording it) is tested in the same engine seam with a simulated `AgentRunner`. Running `ship` with the real agent and the real Claude and Codex adapters, Forge and logs are verified in the separate integration, with a test repo and explicit configuration.
- Story 22: `renderPanel(snapshot)` returns text and is tested by its output; drawing in the real terminal has no test.
- Story 23: no automatic tests in the usual suite; it is a thin integration whose real behavior is validated in the logs spike.
- Story 24: the cleanup function with an injected date on a temporary folder.

The test or CI policy of the repo that the agents implement is not part of these tests. Tests with real Claude, Codex, Forge and Solve are a separate integration and do not run in the usual suite.

## Out of scope

Web UI, OS app, keys that act on an epic (stop it, reactivate it, change its stage), reactivation commands for cases that require intervention and initial Linux/Windows support. The engine stays portable, but additional support requires validation.

Automatic merge of the final PR, reproducing repo policies inside the engine, changing the skills' current reports or incorporating a copy of Agent Forge. `ship` keeps its slice flow; this app's review loop works on the epic's final PR.

Dependencies between epics and unblocking by merge. That work will be resolved in Solve separately; this version takes the ready epics directly.

## Open questions

These are technical validations that only a test with the real tools can answer; none is a product decision. Each becomes a spike with a clear success criterion, and its result can change the decisions above. The first one (headless agents) conditions the rest: if they fail, the design of the runner or of identity changes.

Headless Claude and Codex. Check that both run the skills flow without interaction, expose and keep their sessions, resume after an interruption and deliver the caller's JSON. Include the work delegated by `ship` and check that stopping the process reaches its child processes without losing what is needed to rebuild the context.

Result (2026-10-15, [research](../research/headless-agents.md)): both CLIs run a skill without interaction, expose their session id, resume after a cut and write a JSON that validates against `CallerResult`. Killing the CLI does not always kill its children: Codex leaves the command's process orphaned even with `SIGTERM`, and both with `SIGKILL`, a known limitation when running without a container ([ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md)). The adapter must invoke the real binary, close stdin (`</dev/null`), pass `--add-dir` for paths outside the workspace and use `-c sandbox_mode=...` in `codex exec resume`.

Agents in containers. Discarded on 2026-10-15 for this version: the agents run on the host ([ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md)). The partial research stays in [agent-containers.md](../research/agent-containers.md) as material for AFK agent security.

Partial result (2026-10-15, [research](../research/agent-containers.md), Docker Desktop 4.95.0): viable with conditions. With the clone and worktree mounted at the same paths as on the host, `git worktree list` matches inside and outside; Claude 2.1.301 and Codex 0.153.4 run on Linux, run `git status`, commit and push through their shell tool, and their session resumes in a new container if `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are in a host folder and the `cwd` does not change. `pnpm test` runs on a base image with Node and pnpm, the network can be restricted with an internal network and a proxy with an allowlist, and `docker kill` leaves no processes (0.09 s), including the one that leaves the group. Runner conditions: Codex with `--sandbox danger-full-access` (its `bwrap` does not work in the container), Claude as a non-root user, `safe.directory` in the image and a state directory per execution. Claude's login lives in the macOS keychain, so the container needs another credential. Not verified, for lack of a test repo and a Forge bot (slice #7): CLIs truly authenticated inside the container, push to GitHub, `gh` for more than 70 minutes with token renewal and the network list with a real login; the tests used a simulated model and a local remote.

Agent Forge. Validate the adapter for bot and personal identities, especially credential renewal during long executions, and that `gh` via Forge works for the orchestrator's operations. The [earlier research](../research/autonomous-ship-review.md) found that the observed launcher did not implement our headless task contract; the app must integrate the identity capabilities without assuming that launcher already solves the runner.

Shared root with Solve. Test the shared root, the creation and reuse of worktrees and two simultaneous epics from a managed clone. Check that the material prepared before ready is accessible to the caller and that sessions can continue at the same paths. While Solve does not add `solve:epic:ready` on its own, the label can be set by hand for this test.

Partial result (2026-10-15, [research](../research/shared-root.md)): Solve does not receive the root, it only reads the worktrees `path` from each repo's `solve.md`; with the default root everything matches and with another one that `path` has to be equalized. With Worktrees `off`, `ship` works in the clone unless it is asked to isolate the epic. The reviewer goes in `<root>/reviews/<repo>/<feature>/`, without colliding with `worktrees/` (tested with a disposable repo). Spec and ADR in uncommitted files do not reach a managed clone. A resumed Claude session operates in the `cwd` of the new process, so the runner must use the saved one. Two real epics (2026-10-16, against a disposable repo that was later deleted, so the evidence is no longer kept) were drained in parallel with `ship` (headless Claude, Sonnet) from one clone at `<root>/repos/<org>/<repo>`: their worktrees ended up in `<root>/worktrees/<repo>/<feature>/` with lanes `<feature>--lane-1`, the clone did not move, relaunching `ship` reused the worktree and the integration PR, and the README conflict between the two epics only shows up when integrating them. Not verified: Worktrees `off` with "worktree this epic".

Recovery from cuts. Test interruptions between publishing to GitHub and local persistence, including an incomplete JSON. Verify that results are imported only once and work resumes without duplicating agents, PRs, comments or state changes.

Result (2026-10-16, real Claude and Codex against a disposable repo, since deleted): what was specified is confirmed. With `kill -9` in the middle of `ship` the restart stops the orphaned agent and resumes the same session with no duplicated PR, comments or commits; with `kill -9` between the JSON and its import the result is imported once (a second import is ignored by `executionId`); a truncated JSON is `invalid_result`, does not spend a round and is retried in the same session; with `Ctrl+C` the exit is clean, no processes remain and the restart resumes the preserved session. Two implementation adjustments: git in the agent process authenticates with the execution's token (not with the person's credential helpers) and the caller's JSON is written to `$CARRIER_RESULT_PATH`, because a Codex reviewer retyped a long path with one segment missing and the retries repeated the error.

Logs and panel. Validate how to direct stdout and stderr of `@ashulab/universal-logger` to files without interfering with the terminal panel. The reviewed package writes to the console and offers no general transport; the integration must reuse the library as the logging implementation and keep the output when the process is stopped.

Result (2026-10-15, [research](../research/logging-panel.md), `@ashulab/universal-logger` 0.1.1): replacing `console.log/info/warn/error/debug` with synchronous writes (`writeSync`) to an append file is enough: the panel receives only its own bytes and `Ctrl+C` does not lose logs, with or without a `SIGINT` handler. `logError` with an `Error` keeps the stack in the `stack` field. The library needs no changes, but the integration must set `NODE_ENV` to something other than `development` (it emits several lines per log), add the level from the `console` method (the JSON does not carry it) and use `logError` or `scoped.error` for errors with a stack (`scoped.info/warn` with an `Error` loses it).
