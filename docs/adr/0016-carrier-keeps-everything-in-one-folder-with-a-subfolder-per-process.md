# 0016 - Carrier keeps everything in one folder, with a subfolder per process and three levels of configuration

- Status: accepted
- Date: 2026-10-29

## Context

Carrier's files live in two folders that were never designed together. `~/.solve/`, the config's `root`, holds the engine's `repos/`, `worktrees/`, `reviews/` and `orchestrator/`, and also the chat host's database, socket and projects. `~/.carrier/` holds `config.json` and the chat's session worktrees. The chat is split across both, and the first name belongs to Solve, the skill set, which in fact receives no root at all: the only thing the two share is the `Worktrees` line of each repo's `docs/agents/solve.md`, from which the engine derives an epic's worktree and which it verifies with `git worktree list`.

The chat host cannot start without the engine's config. `carrier chat-host` demands `--config`, loads the whole engine schema and reads `root` and the GitHub timeout from it, yet the macOS app has to start the host before any engine exists, and a person who only wants to chat should not have to configure an engine. The app, for its part, asks the person for `node`, `carrier`, the `PATH` and the config path, because nothing tells it where Carrier lives.

Nobody but the author has data under the old folders, so nothing has to be migrated or kept compatible.

## Decision

We keep everything Carrier owns in one folder, `~/.carrier/`, changed with `CARRIER_HOME`. Each process owns one subfolder and holds its own lock there: `engine/` (`state/` with the database, control socket and lock, `logs/`, `repos/`, `worktrees/` and `reviews/`) and `chat/` (`state/` with the database, socket and lock, `logs/`, `projects/` and `worktrees/`). The engine's `config.json` stays at the top, and the chat's `chat.json` lives in `chat/`. The config key `root` and `~/.solve/` go away.

A setting lives in one of three levels, by who reads it: the engine's `config.json`, the chat's `chat/chat.json`, and the app's preferences in user defaults. No process reads another's level, and the only thing they share is where the Carrier folder is. The chat host starts with only the folder: every key of `chat.json` has a default and the file may be missing. The engine needs its `config.json` to start, and the app tells the person when it is missing and offers to create it. The app edits the two files and its own preferences, and the processes read the files; the preferences are read by nobody else.

The coexistence with Solve's worktrees is left for later. Until then the engine keeps deriving an epic's worktree from the `Worktrees` line of each repo's `solve.md` and verifying it, and the documentation recommends `~/.carrier/engine/worktrees/<repo>/<feature>/` as that line.

Nothing is migrated and nothing old is read: a config that still has `root` is rejected like any other unknown key.

## Alternatives considered

Keeping `~/.solve/` as the root and moving only the chat. It leaves a skill set's name on the folder of an application that is not the skill set, and it keeps `root` as a key that means "where Solve and Carrier meet" when in fact they do not meet there.

`~/Library/Application Support/Carrier/`, the macOS convention for an app. It is longer and has a space in it, which a Unix socket path and every shell command must live with, and the people who run Carrier are the ones who already read `~/.claude`, `~/.codex` and `~/.t3`.

Splitting configuration, state and logs across `~/.config`, `~/.local/state` and `~/.cache`. It scatters one product across three folders on a platform that does not use them.

One flat folder where the engine's and the chat's state sit side by side. It is what the two folders amount to today, and it loses the rule that one process owns one place and one lock.

One `config.json` with a section for the chat. It is simpler to find, but it keeps the chat host tied to the engine's schema and its validation, which is the coupling this decision exists to remove.

## Consequences

The chat host, the engine and the app agree on one place and one variable, and a development build can run against a throwaway folder with `CARRIER_HOME`. The chat can be used with no engine configured.

The code that reads `root`, the `--config` of `chat-host`, the engine-folders check of the chat's folder rule, the specs, the ADRs [0005](0005-engine-independent-of-the-macos-app.md), [0010](0010-carrier-runs-in-the-background-as-a-detached-process.md), [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md), [0014](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md) and [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md), the README and the configuration guide all say `~/.solve/` or `root` and change with it.

Solve's own worktrees and Carrier's engine worktrees can end up in different places until the two are reconciled, and a repo prepared for Solve alone keeps its old `Worktrees` line until someone changes it.

A Unix socket path has a length limit, and a long `CARRIER_HOME` can exceed it; the host and the engine have to say so instead of failing to listen.
