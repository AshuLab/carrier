# carrier

Carrier is a local orchestrator: it polls GitHub repos for `solve:epic:ready` epics, runs an author agent (`ship`) and a reviewer agent with another identity as child processes on this machine, and leaves the epic `ready-for-test` or `needs-human`. It never merges the final PR. Read [README.md](README.md) first, then [the spec](docs/specs/autonomous-orchestrator.md) when you need the why; terms are in [the glossary](docs/glossary.md).

## Commands

pnpm only (never npm or yarn). Node 26 runs the TypeScript directly.

- `pnpm typecheck` and `pnpm test` (unit, fakes and a temp SQLite: no network, no real agents). Run both before a PR.
- `pnpm test:integration`: real tools, each file skips itself unless its `CARRIER_IT_*` / `CARRIER_TEST_*` variables are set (the header of each file lists them).
- `pnpm build`: compiles to `dist/` (what is published as `@ashulab/carrier`).
- `pnpm db:generate`: new Drizzle migration after changing the schema in `src/storage`.
- Run from source: `node src/cli/main.ts <init|doctor|schema|--config file>`.

## Layout

Each folder has one job (details in the README):

- `cli` is only the command line: `main.ts` parses and dispatches, `args.ts` is the option table, `commands/` has one file per command, `config-file.ts` reads the config, `compose.ts` wires the real engine. A failure to report is a `CliError`; only `main.ts` turns it into an exit code.
- `ui` is the terminal contract (`Ui`, `Cancelled`) and its clack implementation. Commands depend on the contract, tests script it.
- `init` is `carrier init`: `wizard.ts` is the flow, `questions/` one file per thing asked, `deps.ts` everything that touches the machine (replaceable in tests), `prior.ts` and `summary.ts` the edit mode and the recap.
- `doctor` is `carrier doctor`: `doctor.ts` the checks, `fixes.ts` the remedy for each failure.
- `panel` is the dashboard: `snapshot.ts` reads SQLite, `types.ts` is what it shows, `dashboard.ts` and `plain.ts` draw it, `ui-state.ts` is the pure key reducer, `interactive.ts` wires keys to actions.
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

**Tracker:** GitHub Issues via the `gh` CLI - work is labelled `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw`.

**The flow** - how work moves, who does what, when to use each skill: `docs/agents/solve-flow.md`.

**Operations** - tracker, branching and worktree commands: `docs/agents/solve.md`.
