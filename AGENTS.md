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

`src/cli` entry and composition root, `config` schema/defaults/merging, `orchestration` the engine (polling, scheduler, stages, retries, restart) behind the `GitHub` port, `execution` the `AgentRunner`/`Workspaces` ports and result import, `harnesses` Claude/Codex runners, `integrations` GitHub through Agent Forge, `storage` SQLite, `panel`, `logging`, `init` and `doctor` (the friendly CLI). Details in the README.

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
