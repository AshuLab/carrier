# carrier

Carrier is a local orchestrator: it polls GitHub repos for `solve:epic:ready` epics, runs an author agent (`ship`) and a reviewer agent with another identity as child processes on this machine, and leaves the epic `ready-for-test` or `needs-human`. It never merges the final PR. Read [README.md](README.md) first, then [the spec](docs/specs/autonomous-orchestrator.md) when you need the why; terms are in [the glossary](docs/glossary.md).

## Commands

pnpm only (never npm or yarn). Node 26 runs the TypeScript directly.

- `pnpm typecheck` and `pnpm test` (unit, fakes and a temp SQLite: no network, no real agents). Run both before a PR.
- `pnpm test:integration`: real tools, each file skips itself unless its `CARRIER_IT_*` / `CARRIER_TEST_*` variables are set (the header of each file lists them).
- `pnpm build`: compiles to `dist/` (what is published as `@ashulab/carrier`).
- `pnpm db:generate`: new Drizzle migration after changing the schema in `src/storage`.
- `pnpm replay:events <stdout.log>`: prints the events a Claude log yields as JSON lines (`--db <file> --execution <id>` stores them for an execution that predates events).
- Run from source: `node src/terminal/cli/main.ts <init|doctor|schema|start|status|watch|stop|pause|resume|check|restart|chat|chat-host>`; `--config file` points the engine at another config, the chat takes only `CARRIER_HOME`.

## Layout

Everything a terminal user sees lives under `src/terminal`, so a future web UI is a sibling folder and not a rename. What any front-end would need stays outside it. Each folder has one job (details in the README):

- `terminal/cli`: only the command line. `main.ts` parses and dispatches, `args.ts` is the option table, `commands/` one file per command (`control.ts` serves stop, pause, resume and check), `control-client.ts` the client of the control socket that `status`, `watch`, `start` and the control commands use, `config-file.ts` reads the config, `compose.ts` wires the real engine. A failure to report is a `CliError`; only `main.ts` turns it into an exit code.
- `terminal/prompts`: the terminal contract (`Ui`, `Cancelled`) and its clack implementation. Commands depend on the contract, tests script it.
- `terminal/wizard`: `carrier init`. `wizard.ts` is the flow, `questions/` one file per thing asked, `deps.ts` everything that touches the machine (replaceable in tests; the agent CLIs, their logins and the local servers go through `doctor/detect.ts`, the one detector), `prior.ts` and `summary.ts` the edit mode and the recap.
- `terminal/dashboard`: the panel. `dashboard.ts` and `plain.ts` draw it, `history.ts` the stage history of a card and its cache, `ui-state.ts` is the pure key reducer, `interactive.ts` wires keys to actions.
- `status`: what the panel shows (`types.ts`) and how it is read from SQLite (`snapshot.ts`), for any front-end.
- `control`: the control socket (`<folder>/engine/state/control.sock`), newline-delimited JSON for a local client: the macOS app and the CLI (`status`, `watch`, ...). `server.ts` holds the request schema and the server, and the hello's `capabilities` list the optional requests an engine answers (a client checks it before asking, so an older engine still works); `terminal/cli/compose.ts` starts it once the engine is up.
- The Carrier folder (`~/.carrier`, or `CARRIER_HOME`, [ADR 0016](docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) holds the engine's config at `<folder>/config.json`, the accounts at `<folder>/providers.json` ([ADR 0020](docs/adr/0020-accounts-live-in-a-file-both-processes-read.md); `config/providers.ts` is its schema and reader, and `config.json` refuses a `providers` key) and the engine's files in `<folder>/engine/`: `state/` (`carrier.db`, `control.sock`, `carrier.lock`), `logs/`, `repos/`, `reviews/` and `worktrees/`. `config/engine-places.ts` computes them from the folder, and nothing else decides them; `--config` only chooses the config file.
- `chat`: the chat host ([ADR 0013](docs/adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), a process of its own that holds user sessions and shares no state with the engine. It starts from the Carrier folder alone (`~/.carrier`, or `CARRIER_HOME`, [ADR 0016](docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)), reads no engine config (only `providers.json`, the accounts a chat agent names, read at each request through `account.ts`), and keeps everything in `<folder>/chat/`: `state/` (`chat.db`, `chat.sock`, `carrier.lock`), `logs/`, `projects/`, `worktrees/` and its optional `chat.json`. `config.ts` is that file's schema, its defaults and the paths of the folder (a wrong file stops the host with the key named), `host.ts` is its lifecycle (lock, `chat.db`, socket), `server.ts` the socket (`chat.sock`, a strict request union and a hello like the engine's), `idle.ts` the rule that ends it, `sessions.ts` what the requests do (open, send, events, close, the one-minute idle close, and `openPlan`: a plan for a folder, a repository to clone or a new project, with the branch to check out (`checkout` in `workspace.ts`, refused on a folder with uncommitted changes) or a worktree from it, becomes a `preparing` session whose steps (`clone` or `fetch` through `projects.cloneRepo`, whose latest git progress line the `events` reply carries as `progress`, never stored) run in the background and are stored as `step` events, `retryPreparation` repeats a failed one from where it stopped (the worktree recorded on the session and a checkout done are reused) and `cancelPreparation` aborts the running step, deletes the session like a delete does and answers the plan, [ADR 0018](docs/adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)), `plan.ts` the plan's request schema and the step types, `runner.ts` the chat runner port with `fake.ts` its test double (no provider adapter is registered yet), `folder.ts` the check of a session's folder, never inside `<folder>/engine/` (and `checkProjectsFolder`, the same rule for the projects folder), `projects.ts` what the chat brings onto the Mac with the person's own `gh` login: `cloneRepo` (waiters share one clone, which stops when nobody waits; only git's progress lines pass on, one a second), `createProject`, the `githubRepos` listing and `repoBranches`, under the projects folder ([ADR 0015](docs/adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)), `health.ts` the `health` request (whether `git`, `gh` and each agent's CLI work and are signed in, as `ready`, `missing`, `signedOut` or `unknown`, only the verdicts; [spec](docs/specs/chat-host.md)), `git.ts` the port to the machine's git (`realGit` in production, `FakeGit` in `fake.ts`), `workspace.ts` what a folder is as a repository and its fetch, `names.ts` and `words.ts` the worktree name and its word lists, `worktree.ts` the creation, the delete preview and the removal of a session's worktree under `<folder>/chat/worktrees` ([ADR 0014](docs/adr/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)), `transcript.ts` the redact-then-cut limits, `schema.ts`/`db.ts`/`migrations/` its own database (`pnpm db:generate` generates both). `terminal/cli/commands/chat.ts` is its client and starts it detached (`detached.ts`, shared with `start`).
- `macos`: the native app, a client of the socket; it has its own README, build and tests.
- `doctor`: the checks (`doctor.ts`), the remedy for each failure (`fixes.ts`) and the detector (`detect.ts`: per harness the binary found through `resolveBinary` with its version, per account whether it is signed in, and the local servers that answer; it takes its machine as a port and creates no account). `carrier doctor --json` prints them as one JSON array of `{ name, status, detail?, fix? }` and nothing else, with the same exit code; the macOS app's Health tab runs it.
- `prompts`: what the agents are told, one file per part. `build-prompt.ts` joins `intro.ts` (role, rules, earlier turns), one stage (`ship.ts`, `fix.ts`, `review.ts`) and `result.ts` (the JSON contract). To change what an agent is asked, edit the stage file.
- `config`, `orchestration` (the engine, behind the `GitHub` port), `execution` (the `AgentRunner`/`Workspaces` ports, result import), `harnesses` (Claude/Codex/Antigravity runners), `integrations`, `storage`, `logging`: as their names say.

## Conventions

- The engine depends on ports (`GitHub`, `AgentRunner`, `Workspaces`) and an injected clock; tests use fakes of those, never the real thing. Real tools only in the gated integration tests.
- Node strips types, it does not compile them: no `enum`, no parameter properties, relative imports end in `.ts`.
- SQLite is the authority and labels are its mirror ([ADR 0002](docs/adr/0002-sqlite-authority-labels-mirror.md)). Importing a result and its transition is one idempotent transaction.
- No secrets in config, state or logs. Never echo a child's output that could hold a token.
- All repo content (code, docs, tests, strings) is in English.
- Config schema lives in `src/config/schema.ts` (the engine's), `src/config/providers.ts` (the accounts' `providers.json`) and `src/chat/config.ts` (the chat's `chat.json`); changing either means updating `docs/configuration.md`.

## Docs

For users: [configuration](docs/configuration.md), [preparing a repo](docs/preparing-a-repo.md), [troubleshooting](docs/troubleshooting.md). Decisions: [ADRs](docs/adr/). Evidence behind them: [research](docs/research/).

A release is a pushed tag `vX.Y.Z`, run by `.github/workflows/release.yml`. The `release` skill (`.claude/skills/release`) is the same procedure by hand for when Actions is unavailable; change one, change the other.

## solve skills

This repo uses the **solve** skill set - ideas ship through `sharpen -> to-spec -> to-tickets -> ship -> land`, reaching for `tdd` / `code-review` / `code-post` / `code-resolve` when they earn it.

**Tracker:** GitHub Issues via the `gh` CLI - work is labelled `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw`, `solve:epic:ready`.

**The flow** - how work moves, who does what, when to use each skill: `docs/agents/solve-flow.md`.

**Operations** - tracker, branching and worktree commands: `docs/agents/solve.md`.
