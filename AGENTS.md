# carrier

Carrier is a local orchestrator: it polls GitHub repos for `solve:epic:ready` epics, runs an author agent (`ship`) and a reviewer agent with another identity as child processes on this machine, and leaves the epic `ready-for-test` or `needs-human`. It never merges the final PR. Read [README.md](README.md) first, then [the spec](docs/specs/autonomous-orchestrator.md) when you need the why; terms are in [the glossary](docs/glossary.md).

## Commands

pnpm only (never npm or yarn). Node 26 runs the TypeScript directly.

- `pnpm typecheck` and `pnpm test` (unit, fakes and a temp SQLite: no network, no real agents). Run both before a PR.
- `pnpm test:integration`: real tools, each file skips itself unless its `CARRIER_IT_*` / `CARRIER_TEST_*` variables are set (the header of each file lists them).
- `pnpm build`: compiles to `dist/` (what is published as `@ashulab/carrier`).
- `pnpm db:generate`: new Drizzle migration after changing the schema in `src/storage`.
- `pnpm replay:events <stdout.log>`: prints the events a Claude log yields as JSON lines (`--db <file> --execution <id>` stores them for an execution that predates events).
- Run from source: `node src/terminal/cli/main.ts <init|doctor|schema|start|status|watch|stop|pause|resume|check|restart|chat|chat-host|--config file>`.

## Layout

Everything a terminal user sees lives under `src/terminal`, so a future web UI is a sibling folder and not a rename. What any front-end would need stays outside it. Each folder has one job (details in the README):

- `terminal/cli`: only the command line. `main.ts` parses and dispatches, `args.ts` is the option table, `commands/` one file per command (`control.ts` serves stop, pause, resume and check), `control-client.ts` the client of the control socket that `status`, `watch`, `start` and the control commands use, `config-file.ts` reads the config, `compose.ts` wires the real engine. A failure to report is a `CliError`; only `main.ts` turns it into an exit code.
- `terminal/prompts`: the terminal contract (`Ui`, `Cancelled`) and its clack implementation. Commands depend on the contract, tests script it.
- `terminal/wizard`: `carrier init`. `wizard.ts` is the flow, `questions/` one file per thing asked, `deps.ts` everything that touches the machine (replaceable in tests), `prior.ts` and `summary.ts` the edit mode and the recap.
- `terminal/dashboard`: the panel. `dashboard.ts` and `plain.ts` draw it, `history.ts` the stage history of a card and its cache, `ui-state.ts` is the pure key reducer, `interactive.ts` wires keys to actions.
- `status`: what the panel shows (`types.ts`) and how it is read from SQLite (`snapshot.ts`), for any front-end.
- `control`: the control socket (`orchestrator/control.sock`), newline-delimited JSON for a local client: the macOS app and the CLI (`status`, `watch`, ...). `server.ts` holds the request schema and the server, and the hello's `capabilities` list the optional requests an engine answers (a client checks it before asking, so an older engine still works); `terminal/cli/compose.ts` starts it once the engine is up.
- `chat`: the chat host ([ADR 0013](docs/adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), a process of its own under `<root>/chat/` that holds user sessions and shares no state with the engine: `host.ts` is its lifecycle (lock, `chat.db`, socket), `server.ts` the socket (`chat.sock`, a strict request union and a hello like the engine's), `idle.ts` the rule that ends it, `sessions.ts` what the requests do (open, send, events, close, the one-minute idle close), `runner.ts` the chat runner port with `fake.ts` its test double (no provider adapter is registered yet), `folder.ts` the check of a session's folder, `transcript.ts` the redact-then-cut limits, `schema.ts`/`db.ts`/`migrations/` its own database (`pnpm db:generate` generates both). `terminal/cli/commands/chat.ts` is its client and starts it detached (`detached.ts`, shared with `start`).
- `macos`: the native app, a client of the socket; it has its own README, build and tests.
- `doctor`: the checks (`doctor.ts`) and the remedy for each failure (`fixes.ts`).
- `prompts`: what the agents are told, one file per part. `build-prompt.ts` joins `intro.ts` (role, rules, earlier turns), one stage (`ship.ts`, `fix.ts`, `review.ts`) and `result.ts` (the JSON contract). To change what an agent is asked, edit the stage file.
- `config`, `orchestration` (the engine, behind the `GitHub` port), `execution` (the `AgentRunner`/`Workspaces` ports, result import), `harnesses` (Claude/Codex/Antigravity runners), `integrations`, `storage`, `logging`: as their names say.

## Conventions

- The engine depends on ports (`GitHub`, `AgentRunner`, `Workspaces`) and an injected clock; tests use fakes of those, never the real thing. Real tools only in the gated integration tests.
- Node strips types, it does not compile them: no `enum`, no parameter properties, relative imports end in `.ts`.
- SQLite is the authority and labels are its mirror ([ADR 0002](docs/adr/0002-sqlite-authority-labels-mirror.md)). Importing a result and its transition is one idempotent transaction.
- No secrets in config, state or logs. Never echo a child's output that could hold a token.
- All repo content (code, docs, tests, strings) is in English.
- Config schema lives in `src/config/schema.ts`; changing it means updating `docs/configuration.md`.

## Docs

For users: [configuration](docs/configuration.md), [preparing a repo](docs/preparing-a-repo.md), [troubleshooting](docs/troubleshooting.md). Decisions: [ADRs](docs/adr/). Evidence behind them: [research](docs/research/).

## solve skills

This repo uses the **solve** skill set - ideas ship through `sharpen -> to-spec -> to-tickets -> ship -> land`, reaching for `tdd` / `code-review` / `code-post` / `code-resolve` when they earn it.

**Tracker:** GitHub Issues via the `gh` CLI - work is labelled `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw`, `solve:epic:ready`.

**The flow** - how work moves, who does what, when to use each skill: `docs/agents/solve-flow.md`.

**Operations** - tracker, branching and worktree commands: `docs/agents/solve.md`.
