# Contributing

Read [README.md](README.md) first, then [AGENTS.md](AGENTS.md) for the layout and conventions. Docs: [configuration](docs/configuration.md), [preparing a repo](docs/preparing-a-repo.md), [troubleshooting](docs/troubleshooting.md), [glossary](docs/glossary.md) and the [ADRs](docs/adr/).

## Setup and checks

pnpm only, never npm or yarn. Node 26 runs the TypeScript directly.

```bash
pnpm install
pnpm typecheck
pnpm test
```

Run `pnpm typecheck` and `pnpm test` before opening a PR. `pnpm test:integration` uses real tools and skips each file unless its `CARRIER_IT_*` / `CARRIER_TEST_*` variables are set (the header of each file lists them). All repo content (code, docs, tests, strings) is in English.

| Command | What it does |
|---------|--------------|
| `pnpm build` | Compile to `dist/` (what gets published) |
| `pnpm typecheck` | Type-check the project |
| `pnpm test` | Full unit suite — fakes and a temp SQLite, no network and no real agents |
| `pnpm test:integration` | Integration tests with real tools; they skip with a clear message unless their environment variables are set |
| `pnpm db:generate` | Generate a Drizzle migration after changing the schema |

## Tech stack

| Layer | Technology |
|-------|-----------|
| Runtime | Node.js 22+ for the package (compiled to `dist/`); 26 to work on it, where TypeScript runs via native type stripping. ESM |
| Language | TypeScript (strict) |
| State | SQLite via `better-sqlite3`, schema and migrations with Drizzle ORM + Drizzle Kit |
| Validation | Zod (config, caller result, GitHub responses) |
| Logging | `@ashulab/universal-logger` |
| GitHub access | `gh` CLI, authenticated per profile through Agent Forge (GitHub Apps) |
| Identities | [Agent Forge](https://github.com/AshuLab/agent-forge) bot profiles, or your own `gh` login |
| Agents | Claude Code, Codex and Antigravity (`agy`) CLIs, headless; their models from the cloud or from LM Studio / Ollama |
| Workflow | [Solve](https://github.com/AshuLab/skills) skills (`ship`, `code-review`, ...) |
| Terminal UI | `@clack/prompts` for `init` and `doctor`; plain ANSI escape sequences for the panel |
| Testing | Vitest (unit, and integration gated by environment variables) |
| Package manager | pnpm 12 |

## Repository structure

```text
carrier/
├── src/
│   ├── terminal/       # everything a terminal user sees; a web UI would be a sibling of this folder
│   │   ├── cli/        #   the command line: args, commands/ (run, start, stop/pause/resume/check, status, watch, init, doctor, schema), the control-socket client, config file, the wiring of the real engine, Ctrl+C
│   │   ├── prompts/    #   the terminal contract (`Ui`) and its clack implementation: prompts, spinners, check lines
│   │   ├── wizard/     #   `carrier init`: the flow, what it asks (questions/), what it needs from the machine (deps), the recap
│   │   └── dashboard/  #   the panel: renderers (dashboard, plain), keys and their state, agent-output tail, each epic's stage history
│   ├── status/         # what Carrier is doing right now, read from SQLite (the view any front-end draws)
│   ├── control/        # the control socket: snapshot, pause/resume, check, stop, sessions, events, epic, files, availableRepos (a page at a time), resumeEpic
│   ├── doctor/         # the checks of `carrier doctor` and the remedy for each failure
│   ├── config/         # config schema, the accounts' `providers.json`, defaults, loading/merging, per-repo resolution, JSON Schema, default path
│   ├── orchestration/  # engine: polling, scheduler, stages, retries, restart, final-PR rules, ports + fakes
│   ├── execution/      # AgentRunner/Workspaces ports, caller result parsing and idempotent import
│   ├── harnesses/      # Claude, Codex and Antigravity runners, credentials, local providers, orphan detection
│   ├── integrations/   # GitHub through Agent Forge (`gh` via execFile)
│   ├── prompts/        # author and reviewer prompts (what the agents are told, not terminal prompts)
│   ├── storage/        # SQLite schema, migrations, lock, executions, events, retention
│   ├── logging/        # universal-logger integration
│   └── format/         # duration formatting
├── macos/              # the native app: a client of the control socket (see its README)
└── docs/
    ├── specs/          # the specs the features were built from
    ├── adr/            # architecture decision records
    ├── research/       # spike findings
    └── glossary.md     # domain vocabulary
```

[`AGENTS.md`](AGENTS.md) has the detail of each folder.

## Developing against a throwaway folder

Everything the chat owns is in the Carrier folder, so a development run can use a scratch one and never touch your real `~/.carrier`. Keep the path short: a Unix socket path is limited to about 100 bytes and the host refuses a longer one.

```bash
export CARRIER_HOME=$(mktemp -d /tmp/carrier.XXXXXX)   # the scratch folder
node src/terminal/cli/main.ts chat-host                # the host in the foreground; Ctrl+C or `chat --stop` ends it
node src/terminal/cli/main.ts chat --list              # from another terminal with the same CARRIER_HOME: "No chat sessions."
node src/terminal/cli/main.ts chat --stop              # ends the host
```

The host creates `$CARRIER_HOME/chat/` (`state/`, `logs/`) on its own and uses the defaults of `chat.json`; to try other settings, write `$CARRIER_HOME/chat/chat.json` before starting it (a wrong file stops the host and names the key). To run the app against it, build it (see [`macos/README.md`](macos/README.md)) and start its binary from the same terminal, so it inherits `CARRIER_HOME`:

```bash
(cd macos && ./build-app.sh)
macos/Carrier.app/Contents/MacOS/Carrier               # opens the window; with `carrier` found, starts the host in $CARRIER_HOME/chat/ if none answers
```

The app finds `carrier` by itself (the Homebrew one, `/opt/homebrew/bin/carrier`) and says in the Sessions section when it does not. To test your clone's `carrier` instead, run `pnpm build` and put the path of `dist/terminal/cli/main.js` (or of `src/terminal/cli/main.ts`) with "Use another…" under Programs in Settings > Engine; a path ending in `.ts` or `.js` runs under `node`, which the app finds from your login shell. That setting is the app's preference, not part of the folder. The app replaces a running host only when the installed `carrier` has a newer version, and a build under development keeps the same one, so stop the host with `carrier chat --stop` after changing the code. When you are done, `carrier chat --stop`, press "Use the Homebrew one" in Settings > Engine and delete the folder.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, for example `feat(macos): ...`, `fix(engine): ...`, `docs: ...`. The types in use are `feat`, `fix`, `docs`, `test`, `chore` and `ci`; the scope is optional and names the area (`macos`, `chat`, `engine`, `cli`, `config`, ...).

## Changelog

Every user-visible change adds one line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the same PR, under Added, Changed, Deprecated, Removed, Fixed or Security ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)). Short, plain English, from the point of view of someone using Carrier. A change nobody can see (tests, refactors, CI) needs no line.

## Versions

[SemVer](https://semver.org/). While Carrier is 0.x, a breaking or large change bumps the minor version and a fix bumps the patch.

## Branches and PRs

`main` is the only long-lived branch; there is no `develop` branch. A PR into `main` needs one review and the `CI` check (typecheck and unit tests, run once the PR is not a draft); force-pushes are refused. Epic branches have no rules, so `ship` merges slices into them unattended.

- Work happens on an epic branch `feat/<feature>/epic`, cut from `main`, with slice branches `feat/<feature>/<NNN-slug>` as its siblings. Each slice gets a PR into the epic branch.
- PRs merge with merge commits. Never squash or rebase.
- The epic branch gets one reviewed PR to `main`.

The commands for the branches are in [docs/agents/solve.md](docs/agents/solve.md) and the flow is in [docs/agents/solve-flow.md](docs/agents/solve-flow.md).

## Releases

A release is a pushed tag `vX.Y.Z`, run by [`.github/workflows/release.yml`](.github/workflows/release.yml). The procedure by hand, for when Actions is unavailable, is the `release` skill in [`.claude/skills/release`](.claude/skills/release).
