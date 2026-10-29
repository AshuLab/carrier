# The engine in the Carrier folder

Status: spec

## Problem

The engine keeps its files in `~/.solve/`, the folder the config calls `root`, which is named after the skill set and which the engine does not share with it: Solve receives no root and the engine only asks git where an epic's worktree is. The folder is a key of the engine's config, so every client that wants to reach the engine has to read and parse that file first: the CLI does it for each command, and the macOS app parses it just to know where the control socket is. That is also why the app cannot say anything useful when there is no engine config: it does not know where to look until it has one.

The rest of what Carrier owns now lives in `~/.carrier/` (the chat, since the epic before this one), so a person who wants to know where Carrier keeps things, back it up or remove it, has two folders and a config key to understand, and one of the folders has a name that belongs to something else.

We know it is solved when the engine's clones, review checkouts, database, control socket, lock and logs are all under `<folder>/engine/`, with the folder being only `CARRIER_HOME` or `~/.carrier`; when the config has no `root`; and when the app finds the engine's socket, and knows that an engine is not configured, by looking at the folder, not by parsing a file.

## Solution

The engine moves into the Carrier folder, as ADR 0016 defines: `<folder>/engine/` with `state/` (the database, the control socket and the lock), `logs/` (the orchestrator's log, each execution's output, and the start log of the app), `repos/` (its clones) and `reviews/` (its review checkouts), and `worktrees/` as the place where Carrier runs an epic's worktree. All of `engine/` is Carrier's own and only Carrier writes inside it. The engine does not create epic worktrees itself today: `ship` makes them where the repo's `docs/agents/solve.md` says, and the engine finds them with `git worktree list` of its own clone. Making `ship` open them in `engine/worktrees/` is part of how Carrier and Solve live together, which is another epic. `root` leaves the config's schema and everything that read it, including the stub repository the forge falls back to before a first clone, which moves to `<folder>/engine/state/forge-cwd/<owner>/<name>`. The engine's folder is `<folder>/engine/` and nothing else decides it.

`--config` only chooses the config file, which by default is `<folder>/config.json` (the CLI already defaults to it when it exists). The folder never follows the file, so a second config is a second `CARRIER_HOME`, and the one-instance lock stays the guard against two engines on one folder. The places the engine uses are computed from the folder in one function, and the entry point passes the folder in (`CARRIER_HOME` or `~/.carrier`) instead of every module reading it from the environment, so a test passes a temporary one.

Two features read a folder only if it lies inside the root today, and they change in different ways. Continue in Terminal resumes a session whose folder is where the session started, which is the engine's clone or a review checkout, so its rule keeps being "an existing folder inside the engine's folder" and follows the new place. The Files changed tab reads an epic's worktree only when it sits under the shared root, so it would lose every epic whose worktree `ship` put elsewhere, and a repo whose Worktrees line still says `~/.solve/worktrees/` is exactly that. Its rule becomes trust git: the epic's workspace is read when `git worktree list` of the clone the engine owns for that repo lists it, compared by real path (symlinks followed), wherever it is, and checked at each read. A folder the database names that git does not list, or a repo with no clone yet, is not read and answers `none` as an outside one does today; the worktree's own lanes come from git as they do now.

The app learns the engine's socket from the folder, as it learns the chat's, and no longer asks for a config path in Settings: the config is `<folder>/config.json`, found through `CARRIER_HOME` in the app's own environment or `~/.carrier`. The Settings tabs that edit the config keep working on that file. When it does not exist the app says on the Carrier home page and in the Carrier section that the engine is not configured and offers nothing to do about it, since the way to create it is the native setup wizard of its own epic; the Start Carrier button is off and says why, and the choice to start Carrier when the app opens does nothing until the config exists. The command that starts the engine needs `node` and `carrier` and no config path, and passes `CARRIER_HOME`; its log is `<folder>/engine/logs/app-start.log`. The `node`, `carrier` and `PATH` fields stay until the Homebrew epic gives `carrier` a known place.

The chat's rule that a session never works inside the engine's folder was written against `<folder>/engine/` in the chat's epic; here it starts to protect something real, and it stays that: a folder outside `engine/` is the person's, whatever it holds. The worktrees a chat session creates stay in `<folder>/chat/worktrees/`, outside `engine/`, and a worktree anywhere else, asked for by the person or opened by a skill, is read by Files changed through git and may be opened by a chat session like any other folder.

This epic starts once the chat's epic (#565) is merged: it builds on the Carrier folder's helpers and on the chat's guard, and both touch the same configuration, README and `AGENTS.md`. It lands with Carrier stopped, because an engine running from the old folder would be orphaned by it, and the old `~/.solve/` is left where it is for the person to delete. A config that still has `root` is rejected like any unknown key; the author's own has none.

The documentation that describes the engine is rewritten to the new model in this epic, with no mention of how it used to be: the README, the configuration guide (which loses the `root` row and gets the folder's description), `AGENTS.md`, `macos/README.md`, the troubleshooting guide, the guide to preparing a repo (its section on paths matching the shared root is replaced by saying that `~/.carrier/engine/worktrees/<repo>/<feature>/` is where Carrier keeps an epic's worktree by default, and that any other place works because Carrier finds a worktree with git), the orchestrator and app specs, ADRs 0005, 0007 and 0010, and the sentence of ADR 0016 that says the engine derives a worktree's path from the repo's Worktrees line, which is not what the code does: it finds it with git.

## Scope

1. With `CARRIER_HOME` pointing at a scratch folder, `carrier` run with a valid config keeps its database, control socket, lock, orchestrator log and executions' output under `<folder>/engine/state/` and `<folder>/engine/logs/`, its clones in `<folder>/engine/repos/` and its review checkouts in `<folder>/engine/reviews/`, and creates nothing outside the folder.
2. A config with `root` is rejected like any unknown key, the schema and `carrier schema` have no `root`, and the config's default place is `<folder>/config.json`.
3. `--config <path>` chooses the config file and nothing else: the engine's folder is the same with any config.
4. `carrier start`, `status`, `watch`, `stop`, `pause`, `resume`, `check` and `restart` find the running engine from the folder.
5. `carrier doctor` checks the engine's socket and its folder in the new places.
6. The forge's stub repository for a repo with no clone yet is under `<folder>/engine/state/forge-cwd/`.
7. The Files changed tab shows an epic whose worktree is anywhere git lists it for the engine's clone of that repo, and shows nothing for a folder git does not list.
8. Continue in Terminal accepts a session whose folder is inside `<folder>/engine/` and rejects one outside it.
9. The app finds the engine's control socket from the folder, with no config file read, and its Settings no longer have a config path.
10. The Settings tabs that edit the config read and save `<folder>/config.json`.
11. With no `<folder>/config.json`, the app says the engine is not configured on the Carrier home page and in the Carrier section, the Start Carrier button is off and says why, and starting when the app opens does nothing.
12. With the config present, the app's Start Carrier starts the engine with `node`, `carrier` and `CARRIER_HOME`, without a config path, and its log is under `<folder>/engine/logs/`.
13. The fixture server and the app's tests follow the new places.
14. The engine's documentation describes the new model, and a search of it for `~/.solve`, `root` and `orchestrator/` finds nothing.

## Decisions

The model and the layout are in ADR 0016; this epic is its engine half and does not restate it. Nothing from the old folders is read.

The engine's places come from one pure function of the folder (its `state/`, `logs/`, `repos/`, `reviews/` and `worktrees/`), shared by the composition, the control commands, the doctor, the workspaces, the retention and the log helpers, and the entry points call `carrierHome()` once and pass the folder down; today they pass `config.root`, which is the call that goes away. The app computes the same places from the folder in `CarrierCore` (the control socket, the start log, the clone of a repo for the Repos tab), and its `SharedRoot` helpers that parse the config's `root` are deleted.

Files changed asks git at each request, as it does today for everything else (`git worktree list --porcelain` in the engine's clone of the epic's repo); nothing is cached, in line with the existing choice for that module.

The control socket keeps its length check, which already refuses a path that does not fit and says so; `<folder>/engine/state/control.sock` fits for any ordinary folder and for the temporary folders of the tests.

Testing seams, per story:

- 1, 4, 5, 6: the engine's composition test (`compose.test.ts` of the CLI and of the control server) with a temporary folder asserts where the database, socket and lock appear; the control-command tests (`status.test.ts`, `restart.test.ts`) drive the commands against that folder; `doctor.test.ts` for the doctor; `forge-cwd.test.ts` for the stub. The clone and review paths are asserted at `GitWorkspaces`'s own seam; its real-git test is an integration test gated by its variables, and the paths are checked at the unit level.
- 2, 3: `load.test.ts` for `root` rejected and the default path, `main.test.ts` for `--config` choosing the file only.
- 7: `files.test.ts`, with real temporary git repositories: a worktree outside the engine folder that git lists is read, a database folder git does not list answers `none`, and a symlinked path is compared by its real path.
- 8: `ContinueInTerminalTests` for the allowlist with the engine folder.
- 9, 10, 12: the pure functions of `CarrierCore` (`SharedRootTests` becomes the folder's paths, `StartCarrierTests` for the engine's command, `EngineTabTests` and `EngineConfigTests` for the config's place, `SetupDetectionTests` for the settings without a config path).
- 11: the notice and the button's state are pure values in `CarrierCore` with their own test; the views have no automated test, like the rest of the shell.
- 13: `FixtureServerTests` and the existing fixture-driven tests.
- 14: no tests, it is documentation; the review greps the documents for the old places.

## Out of scope

The Homebrew epic: where `carrier` lives, and the `node`, `carrier` and `PATH` fields of Settings that go with it.

The native setup wizard, what the app shows of the machine's tools and logins, and the coexistence with Solve's worktrees: their own epics.

Migration of any kind, and reading `~/.solve/` or `root`.

A change in how the engine finds an epic's worktree, which keeps being `git worktree list`, making `ship` open an epic's worktree in `engine/worktrees/`, and any other part of the coexistence with Solve's worktrees.
