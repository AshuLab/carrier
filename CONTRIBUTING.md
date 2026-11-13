# Contributing

Read [README.md](README.md) first, then [AGENTS.md](AGENTS.md) for the layout and conventions. Docs: [configuration](docs/configuration.md), [preparing a repo](docs/preparing-a-repo.md), [troubleshooting](docs/troubleshooting.md), [glossary](docs/glossary.md) and the [ADRs](docs/adr/).

## Getting started on the team

1. Install Node 26, pnpm 12, `gh` and a recent Claude Code.
   Claude Code reads `AGENTS.md` by itself, and the folders under `src/` have their own `AGENTS.md` that load when an agent works there (Claude Code 2.1.290 or later).
   There is no `CLAUDE.md` on purpose: it would shadow `AGENTS.md`.
2. Check the clone: `pnpm install && pnpm typecheck && pnpm test`.
   No tokens and no agents are needed.
3. Install the Solve skills the flow depends on, as in [preparing a repo](docs/preparing-a-repo.md#the-repo-uses-solve).
   How work moves is in [docs/agents/solve-flow.md](docs/agents/solve-flow.md).
4. Pick a ticket: an open `solve:refined` issue with no assignee and no open blocker (the query is under "find the next startable slice" in [docs/agents/solve.md](docs/agents/solve.md)).
   Claim it with `gh issue edit <n> --add-assignee @me`.
5. Branch and open the PR as in [Branches and PRs](#branches-and-prs).

[Agent Forge](https://github.com/AshuLab/agent-forge) gives Carrier separate GitHub bot identities for the author and the reviewer.
You do not need it to develop or to run the unit tests, only to run real epics (your own `gh` login also works there).

Any teammate reviews a PR into `main`.
Only the maintainer (Diego) cuts releases: see [releasing](docs/releasing.md).

## Setup and checks

pnpm only, never npm or yarn.

**Working on the repo needs Node 26**: it runs the TypeScript directly, with no build step.
The published package runs on Node 22+ (it is compiled to `dist/`), which is what the README states.

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
│   ├── control/        # the control socket: snapshot, pause/resume, check, stop, sessions, events, epic, files, fileDiff, availableRepos (a page at a time), resumeEpic, reload
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

Everyone edits `## [Unreleased]`, so two branches often conflict there: keep both lines.

## Writing docs

New or edited prose has one sentence per line.
Markdown renders it the same, and a diff then shows the sentence that changed instead of the whole paragraph.
Files are not reformatted in bulk: they get it as they are edited.

## Versions

[SemVer](https://semver.org/). While Carrier is 0.x, a breaking or large change bumps the minor version and a fix bumps the patch.

## Branches and PRs

`main` is the only long-lived branch; there is no `develop` branch.
Every change reaches `main` through a PR, and PRs merge with merge commits, never squash or rebase.
A PR into `main` that is not a draft runs CI (typecheck and unit tests) and needs one teammate's review.

There are two lanes.
If the change needs a decision written down (a spec, an ADR) or more than one PR, it is an epic; otherwise it goes direct.

### Epic lane

The solve flow, and what Carrier itself runs.

- The epic branch `feat/<feature>/epic` is cut from `main`, with slice branches `feat/<feature>/<NNN-slug>` as its siblings.
- Each slice gets a PR into the epic branch, and `ship` merges it.
  Slice PRs need no human review and run no CI.
- The epic branch gets one PR into `main`, which `ship` opens as a draft.
- The order to `main`: the reviewer marks the PR ready when starting the review, CI runs, and `land` merges only once CI is green.
  `land`'s own `gh pr ready` is then a no-op.

### Direct lane

Small changes that need no spec or slicing: docs, dependency updates, a contained bug fix, CI tweaks.

- Branch `<type>/<slug>` from `main`, where `<type>` is `fix`, `docs`, `chore`, `ci` or `test`.
  Never `feat/<slug>`: git forbids a branch `feat/x` next to `feat/x/epic`, so a later epic with the same slug could not start.
  Features go through the epic lane.
- One PR into `main`; CI runs, a teammate reviews, it merges with a merge commit.
- A user-visible fix still adds its CHANGELOG line.

The commands for the branches are in [docs/agents/solve.md](docs/agents/solve.md) and the flow is in [docs/agents/solve-flow.md](docs/agents/solve-flow.md).

### Numbered files

Drizzle migrations (`src/storage/migrations/`, `src/chat/migrations/`: the `NNNN_*.sql` file plus its `meta/` snapshot and journal) and ADRs (`docs/adr/NNNN-*.md`) are numbered in sequence, so two branches can take the same number.
The branch that merges second fixes its number.
Before merging into `main`, merge `origin/main` into your branch (merge, never rebase); if your number is taken:

- Migration: delete your generated migration and its `meta/` snapshot, restore `meta/_journal.json` from `main` and run `pnpm db:generate` again.
  Never edit the journal by hand.
- ADR: rename it to the next free number and update every link to it (grep the old file name).

An epic branch lives longer, so it is usually the second: the rule applies to its PR into `main`, not to every slice.
The two ADRs already numbered `0014` and the two numbered `0023` stay as they are.
Specs and the glossary are named by slug and need no rule.

## Releases

A release is a pushed tag `vX.Y.Z`, run by [`.github/workflows/release.yml`](.github/workflows/release.yml). The procedure by hand, for when Actions is unavailable, is the `release` skill in [`.claude/skills/release`](.claude/skills/release).
