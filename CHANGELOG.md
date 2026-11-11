# Changelog

All notable changes to Carrier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/AshuLab/carrier/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/AshuLab/carrier/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/AshuLab/carrier/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/AshuLab/carrier/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/AshuLab/carrier/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AshuLab/carrier/releases/tag/v0.1.0
