# carrier

Carrier is a local orchestrator: it polls GitHub repos for `solve:epic:ready` epics, runs an author agent (`ship`) and a reviewer agent with another identity as child processes on this machine, and leaves the epic `ready-for-test` or `needs-human`.
It never merges the final PR.
Read [README.md](README.md) first, then [the spec](docs/specs/autonomous-orchestrator.md) when you need the why; terms are in [the glossary](docs/glossary.md).

## Commands

pnpm only (never npm or yarn). Node 26 runs the TypeScript directly.

- `pnpm typecheck` and `pnpm test` (unit, fakes and a temp SQLite: no network, no real agents). Run both before a PR.
- `pnpm test:integration`: real tools, each file skips itself unless its `CARRIER_IT_*` / `CARRIER_TEST_*` variables are set (the header of each file lists them).
- `pnpm build`: compiles to `dist/` (what is published as `@ashulab/carrier`).
- `pnpm db:generate`: new Drizzle migration after changing the schema in `src/storage`.
- `pnpm replay:events <stdout.log>`: prints the events a Claude log yields as JSON lines (`--db <file> --execution <id>` stores them for an execution that predates events).
- Run from source: `node src/terminal/cli/main.ts <init|doctor|schema|start|status|watch|stop|pause|resume|check|reload|restart|chat|chat-host|usage>`; `--config file` points the engine at another config, the chat takes only `CARRIER_HOME`.

## Layout

Everything a terminal user sees lives under `src/terminal`, so a future web UI is a sibling folder and not a rename.
What any front-end would need stays outside it.
Each folder has one job (the folder tree is in [CONTRIBUTING.md](CONTRIBUTING.md#repository-structure)); a folder with an `AGENTS.md` keeps its detail there.

- `terminal`: the command line, the terminal prompts, `carrier init` and the panel ([detail](src/terminal/AGENTS.md)).
- `status`: what the panel shows (`types.ts`) and how it is read from SQLite (`snapshot.ts`), for any front-end.
- `control`: the engine's control socket, for the macOS app and the CLI ([detail](src/control/AGENTS.md), with the checklist for a new request).
- `config`: the engine's `config.json`, the accounts' `providers.json` and the Carrier folder's paths ([detail](src/config/AGENTS.md), with the checklist for a new field).
- `chat`: the chat host, its own process with its own socket and database ([detail](src/chat/AGENTS.md)).
- `usage`: the quotas and the history of what was used, inside the chat host ([detail](src/usage/AGENTS.md)).
- `doctor`: the checks, their remedies and the one detector of harnesses and accounts ([detail](src/doctor/AGENTS.md)).
- `prompts`: what the agents are told ([detail](src/prompts/AGENTS.md)).
- `orchestration` (the engine, behind the `GitHub` port), `execution` (the `AgentRunner`/`Workspaces` ports, result import), `harnesses` (Claude/Codex/Antigravity runners), `integrations`, `storage`, `logging`: as their names say.
- `macos`: the native app, a client of the socket; it has its own README, build and tests, and its code map is [`macos/AGENTS.md`](macos/AGENTS.md) (what it does, area by area, is in `docs/macos/`).

## Conventions

- The engine depends on ports (`GitHub`, `AgentRunner`, `Workspaces`) and an injected clock; tests use fakes of those, never the real thing. Real tools only in the gated integration tests.
- Node strips types, it does not compile them: no `enum`, no parameter properties, relative imports end in `.ts`.
- SQLite is the authority and labels are its mirror ([ADR 0002](docs/adr/0002-sqlite-authority-labels-mirror.md)). Importing a result and its transition is one idempotent transaction.
- No secrets in config, state or logs. Never echo a child's output that could hold a token.
- All repo content (code, docs, tests, strings) is in English.
- Config schema lives in `src/config/schema.ts` (the engine's), `src/config/providers.ts` (the accounts' `providers.json`) and `src/chat/config.ts` (the chat's `chat.json`); changing any of them means updating `docs/configuration.md`.
- A new table file under `src/storage` goes into the list in `drizzle.config.ts`, or drizzle-kit misses it (the chat's tables all live in `src/chat/schema.ts`).
- A prompt change updates the inline snapshots with `pnpm test -u`, and `src/prompts/result.ts` stays in step with `src/execution/caller-result.ts`.
- New or edited prose has one sentence per line.

## Docs

For users: [configuration](docs/configuration.md), [preparing a repo](docs/preparing-a-repo.md), [troubleshooting](docs/troubleshooting.md). Decisions: [ADRs](docs/adr/). Evidence behind them: [research](docs/research/).

**The macOS app's look** - [macos-ui](docs/macos-ui.md) is the guide to how `Carrier.app` is drawn: the kinds of button and which to use, the divider, text fields, selects, rows that open a form (chevron), lists, menus, empty states, spacing, and the mistakes already made. Read it before you touch any view under `macos/Sources/Carrier`, reuse the pieces it names instead of drawing new ones, and update it in the same change when you add or change a piece.

How to contribute: [CONTRIBUTING.md](CONTRIBUTING.md). Every user-visible change adds a line under Unreleased in [CHANGELOG.md](CHANGELOG.md), in the same PR.

A release is a pushed tag `vX.Y.Z`, run by `.github/workflows/release.yml`; how a release flows to an installed Carrier, the update key and the checks of the first real release are in [releasing](docs/releasing.md). The `release` skill (`.claude/skills/release`) is the same procedure by hand for when Actions is unavailable; change one, change the other.

## solve skills

This repo uses the **solve** skill set - ideas ship through `sharpen -> to-spec -> to-tickets -> ship -> land`, reaching for `tdd` / `code-review` / `code-post` / `code-resolve` when they earn it.
A change outside an epic (docs, a dependency, a contained fix, CI) goes through the direct lane in [CONTRIBUTING.md](CONTRIBUTING.md#direct-lane): no epic, no tickets.

**Tracker:** GitHub Issues via the `gh` CLI - work is labelled `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw`, `solve:epic:ready`.

**The flow** - how work moves, who does what, when to use each skill: `docs/agents/solve-flow.md`.

**Operations** - tracker, branching and worktree commands: `docs/agents/solve.md`.
