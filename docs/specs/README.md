# Specs

Specs are history: each one records why something was decided at the time it was built.
For how Carrier works today, read the area docs under `docs/macos/` and [the configuration guide](../configuration.md).
A later spec can change what an earlier one decided, so the status of each says whether it was built and whether something replaced it.

Specs of one area that build on each other are listed oldest first.

## Engine and orchestrator

- [autonomous-orchestrator](autonomous-orchestrator.md): the engine that runs ready epics with an author and a reviewer. Implemented (v0.1.0).
- [review-observations-pass](review-observations-pass.md): the author answers what a review leaves before the epic is ready. Implemented (v0.1.0).
- [shared-identity](shared-identity.md): one GitHub identity for author and reviewer, and a persona per role. Implemented (v0.1.0), superseded in part by ADR 0021.
- [forge-token-renewal-in-agent-runs](forge-token-renewal-in-agent-runs.md): a Forge bot's token is renewed during a long run. Implemented (v0.1.0).
- [agent-failures-say-why](agent-failures-say-why.md): a failed execution records its failure kind. Implemented (v0.1.0).
- [github-unavailable-says-why](github-unavailable-says-why.md): GitHub being down is told apart from other failures. Implemented (v0.1.0).
- [repo-listing-paged](repo-listing-paged.md): the repo list is browsed a page at a time. Implemented (v0.1.0).
- [choose-the-agent-option-per-epic](choose-the-agent-option-per-epic.md): an agent option per role and failover when credits run out. Implemented (v0.1.0), superseded in part by ADR 0021.
- [engine-in-the-carrier-folder](engine-in-the-carrier-folder.md): the engine keeps its files in the Carrier folder. Implemented (v0.1.0).
- [engine-start-is-quick](engine-start-is-quick.md): the engine starts without waiting for GitHub. Implemented (v0.4.0).
- [settings-apply-without-restart](settings-apply-without-restart.md): the engine reloads its configuration on request. Implemented (v0.4.0).

## Command line, install and updates

- [carrier-terminal-experience](carrier-terminal-experience.md): the terminal panel and running in the background. Implemented (v0.1.0).
- [carrier-installs-with-homebrew](carrier-installs-with-homebrew.md): installing the command and the app with Homebrew. Implemented (v0.1.0).
- [carrier-updates-itself](carrier-updates-itself.md): the app updates itself and brings the engine up to date. Implemented (v0.2.0).

## Chat host

- [chat-host](chat-host.md): a process that holds chat sessions with any provider's agent. Implemented (v0.1.0).
- [session-worktrees](session-worktrees.md): a session can work in its own worktree. Implemented (v0.1.0).
- [workspace-sources](workspace-sources.md): a new session's folder, repository or new project. Implemented (v0.1.0), superseded in part by session-prepared-on-first-message.
- [chat-in-the-carrier-folder](chat-in-the-carrier-folder.md): the chat host lives in the Carrier folder and the app starts it. Implemented (v0.1.0).
- [session-lifecycle](session-lifecycle.md): sessions are archived and deleted by the clock. Implemented (v0.1.0).
- [session-prepared-on-first-message](session-prepared-on-first-message.md): a new session is a plan prepared when the first message is sent. Implemented (v0.1.0).
- [chat-mcp-engine](chat-mcp-engine.md): the chat host serves an MCP to the agents of its sessions. Implemented (unreleased).

## Usage

- [usage-and-limits](usage-and-limits.md): live quotas and the history of what was used, in the app and `carrier usage`. Implemented (unreleased).

## macOS app: window and sidebar

- [macos-app](macos-app.md): the first macOS app, a menu bar item and a window over the control socket. Implemented (v0.1.0), superseded in part by macos-app-redesign.
- [macos-app-redesign](macos-app-redesign.md): the redesigned window and the data behind it. Implemented (v0.1.0), superseded in part by sidebar-home-sessions-carrier.
- [sidebar-rows-title-first](sidebar-rows-title-first.md): a sidebar row names its epic by title. Implemented (v0.1.0).
- [sidebar-home-sessions-carrier](sidebar-home-sessions-carrier.md): the sidebar keeps Home, Sessions and Carrier apart. Implemented (v0.1.0), superseded in part by sidebar-flat-sections.
- [sidebar-flat-sections](sidebar-flat-sections.md): the sidebar's sections lose their cards and open flat. Implemented (v0.1.0).

## macOS app: epics

- [macos-app-github-links](macos-app-github-links.md): slices and review threads link to GitHub. Implemented (v0.1.0).
- [subagent-cards](subagent-cards.md): the Agent output tab tells each slice of a ship session apart. Implemented (v0.1.0), superseded in part by agent-output-quiet-log.
- [finished-epics-in-view](finished-epics-in-view.md): merged and cancelled epics stay in view. Implemented (v0.1.0).
- [earlier-sessions](earlier-sessions.md): open the sessions the Agent output tab folded away. Superseded, the tab now lists every session.
- [pipeline-strip-states](pipeline-strip-states.md): the pipeline strip shows where an epic is, with no times. Implemented (v0.1.0).
- [resume-a-stopped-epic](resume-a-stopped-epic.md): a stopped epic can be resumed from the app. Implemented (v0.1.0).
- [slices-tab-all-slices](slices-tab-all-slices.md): the Slices tab shows every slice, up to date. Implemented (v0.1.0).
- [agent-output-quiet-log](agent-output-quiet-log.md): the Agent output tab reads as one quiet, ordered log. Implemented (v0.1.0).
- [file-diff-in-files-changed](file-diff-in-files-changed.md): a changed file opens to the edited fragment. Implemented (v0.1.0).

## macOS app: sessions

- [sessions-in-the-app](sessions-in-the-app.md): holding a session with an agent from the app. Implemented (v0.1.0).

## macOS app: settings

- [health-check-in-the-app](health-check-in-the-app.md): the Health tab checks that Carrier has what it needs. Implemented (v0.1.0).
- [settings-app-group](settings-app-group.md): Settings gets groups, with an App group and a Legacy group. Implemented (v0.1.3).
- [providers-in-settings](providers-in-settings.md): the Providers page and `providers.json`. Implemented (v0.2.0).
- [repos-in-settings](repos-in-settings.md): the Repos page. Implemented (v0.2.0).
- [agents-in-settings](agents-in-settings.md): the Agents page for the three roles. Implemented (v0.2.0).
- [updates-in-settings](updates-in-settings.md): the Updates page and Check for Updates. Implemented (v0.3.0).
- [behavior-in-settings](behavior-in-settings.md): the Behavior page in the Carrier group. Implemented (v0.4.0).
- [engine-in-settings](engine-in-settings.md): the Engine page in the Carrier group. Implemented (unreleased).
- [sessions-in-settings](sessions-in-settings.md): the Sessions page in the Chat group. Implemented (unreleased).

## macOS app: dictation

- [dictation-in-the-app](dictation-in-the-app.md): dictating into the message box with local speech models. Implemented (v0.4.0).

## macOS app: terminal

- [embedded-terminal-core](embedded-terminal-core.md): native `GhosttyKit` terminal core with tabs, split panes, persistence, settings, and process close guards. Implemented (unreleased).
