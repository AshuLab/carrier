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

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, for example `feat(macos): ...`, `fix(engine): ...`, `docs: ...`. The types in use are `feat`, `fix`, `docs`, `test`, `chore` and `ci`; the scope is optional and names the area (`macos`, `chat`, `engine`, `cli`, `config`, ...).

## Changelog

Every user-visible change adds one line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the same PR, under Added, Changed, Deprecated, Removed, Fixed or Security ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)). Short, plain English, from the point of view of someone using Carrier. A change nobody can see (tests, refactors, CI) needs no line.

## Versions

[SemVer](https://semver.org/). While Carrier is 0.x, a breaking or large change bumps the minor version and a fix bumps the patch.

## Branches and PRs

`main` is the only long-lived branch. There is no `develop` branch, and no branch protection or required checks on purpose: reviews and checks are done by hand until the volume grows.

- Work happens on an epic branch `feat/<feature>/epic`, cut from `main`, with slice branches `feat/<feature>/<NNN-slug>` as its siblings. Each slice gets a PR into the epic branch.
- PRs merge with merge commits. Never squash or rebase.
- The epic branch gets one reviewed PR to `main`.

The commands for the branches are in [docs/agents/solve.md](docs/agents/solve.md) and the flow is in [docs/agents/solve-flow.md](docs/agents/solve-flow.md).

## Releases

A release is a pushed tag `vX.Y.Z`, run by [`.github/workflows/release.yml`](.github/workflows/release.yml). The procedure by hand, for when Actions is unavailable, is the `release` skill in [`.claude/skills/release`](.claude/skills/release).
