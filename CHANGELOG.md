# Changelog

All notable changes to Carrier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The place pill in a session's toolbar ("In the folder", "Worktree") has room on its right, so it lines up with the window's corner.
- A project's icon in the sidebar shows up to three letters (the first letters of its first three words), so projects that share their first two words are easier to tell apart.
- A session's row in the sidebar opens a card when the pointer rests on it, like an epic's: the whole title, what the agent last wrote, where it works, the agent and model, the turns and when it last moved.
- A session that is working shows how long its turn has run ("42s", "12m 05s", "2h 03m") in place of the time of its last activity, in the sidebar's row.
- The icon of a project whose agent is working has a violet arc that goes round its edge (the one on a run's card in the chat) in place of the blue pulse, and the stopwatch next to it is violet too.
- The models, reasoning and access each provider offers are read when the app opens and kept (in memory and in the app's cache folder), so a new session's provider menu lists them at once instead of reading them each time; they are read again in the background, and dropped when the accounts change.
- The sidebar's foot is tidier: Archive shows only while Sessions (or Archive itself) is open, and Carrier is a row under it at the foot until you open it, when it moves up under Sessions with its epics. Opening Archive leaves the sessions above it in place, and its row has a chevron to open and fold its list, which slides, and a menu to group it by workspace or by age. The buttons of the Sessions, Archive and Carrier rows fade in while the pointer is over the row.

### Fixed

- Opening an archived session no longer lays the window out taller than the screen, which pushed the sidebar's Home and Settings and the notice at the bottom of the conversation out of view.

## [0.2.0] - 2026-11-11

Carrier's Mac app now updates itself, and Settings grows pages for Providers, Agents and Repos.

### Added

- The macOS app updates itself: it checks for updates with Sparkle, asks before it installs (or installs by itself if you choose), and relaunches. After an update it upgrades `carrier` with Homebrew and replaces the chat host and the engine when they are free to replace. See [releasing](docs/releasing.md).
- Settings in the macOS app has three new pages under Carrier. Providers: the tools found on this Mac with their state, version and path, and each tool's accounts (add, edit, remove, sign in, update). Agents: the three roles of every epic (Author, Reviewer, Lead reviewer) with their identity, provider, model, effort, persona and what to do when tokens run out. Repos: each repo's status, four checks (Carrier can read it, the Author and the Reviewer can sign in, Solve is set up) and who works there.
- The effort of an agent can be chosen, a role can fail over from one account to the next in steps, and `carrier init` asks for the effort.
- The release signs the app's zip with an update key and attaches an `appcast.xml` to the GitHub Release, which is published last so the feed never points at a version the tap does not have yet.

### Changed

- The accounts of the agent CLIs moved out of `config.json` into `providers.json` in the Carrier folder, which the engine and the chat host read and the app writes ([ADR 0020](docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
- An epic starts at once on its three roles, with no wait at the start ([ADR 0021](docs/adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)).
- The chat in the macOS app looks better: even spacing in the model pill, a copy button that stays usable, and a run's steps that fold and open smoothly.
- The Homebrew cask declares `auto_updates true`, and `brew uninstall --zap` also removes the app's cache folder.
- An app that is older than the installed `carrier` tells you to update it instead of only refusing to talk to it.

## [0.1.4] - 2026-11-11

The chat in the Mac app got friendlier: the agent can now ask you things and you can answer.

### Added

- Chat in the macOS app: a card for the agent's questions (`AskUserQuestion`) so you can answer them instead of only allowing or denying, one card for each run of reasoning and tool calls, a notice card, and markdown tables.

### Changed

- About in the macOS app is the system's About window, with the real app icon.

## [0.1.3] - 2026-11-10

Settings and the chat in the Mac app got a big polish, and the app builds again with the macOS 26 SDK.

### Added

- Settings in the macOS app has an App group (General, Notifications, Appearance, Sidebar, Chat, Keybindings) next to the existing pages, with themes, previews and quiet hours.
- Session list, session header and chat polish in the macOS app, and dropping files into a chat.

### Fixed

- The macOS app builds again with the macOS 26 SDK (the session menu used an API that only the macOS 27 SDK has).

## [0.1.2] - 2026-11-08

A quick fix so the Mac app opens and stays open.

### Fixed

- The macOS app no longer quits at launch when it draws its first provider or file icon (it could not find its resource bundle in the app built by the release workflow).

## [0.1.1] - 2026-11-06

Housekeeping after the first release: Homebrew 7 syntax and npm publishing without a token.

### Fixed

- The Homebrew cask uses Homebrew 7's syntax for the macOS minimum and the quarantine step.

### Changed

- npm publishes through trusted publishing, with no token.
- The docs say the app is installed with the cask.

## [0.1.0] - 2026-11-05

First release. Carrier picks up your ready epics, builds them with one agent, reviews them with another, and never merges the last pull request for you.

### Added

- The engine: it polls the GitHub repos you list for `solve:epic:ready` epics, runs an author agent and a reviewer agent with another identity, and leaves each epic `ready-for-test` or `needs-human`. It never merges the final pull request.
- Agent runners for Claude Code, Codex and Antigravity, with a choice of agent option per role and switching when one runs out of credits.
- A command line: `init`, `doctor`, `schema`, `start`, `status`, `watch`, `stop`, `pause`, `resume`, `check` and `restart`, with a terminal panel.
- A chat host and `carrier chat` to talk to an agent, with sessions that can work in their own worktree.
- The macOS app: epics with their stages, slices and agent output, a stopped epic can be resumed, Settings, and sessions with an agent.
- Everything lives in one Carrier folder (`~/.carrier`, or `CARRIER_HOME`).
- Installation with Homebrew (`brew install ashulab/tap/carrier` for the command, `brew install --cask ashulab/tap/carrier` for the app) and from npm as `@ashulab/carrier`.

[Unreleased]: https://github.com/AshuLab/carrier/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/AshuLab/carrier/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/AshuLab/carrier/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/AshuLab/carrier/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/AshuLab/carrier/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/AshuLab/carrier/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AshuLab/carrier/releases/tag/v0.1.0
