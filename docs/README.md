# Docs

Every document under `docs/`, by area, one line each.
The areas of the macOS app are the ones of `macos/Sources` ([0052](adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md)); `macos/AGENTS.md` is where each lives in the code.
Specs and research are history (each says whether it was built); the area docs say how Carrier works today.

## Using Carrier

- [install](install.md): installing the command and the app, and upgrading or removing them.
- [cli](cli.md): every command and what the engine does.
- [configuration](configuration.md): `engine.json`, `providers.json`, `projects.json`, `chat.json`: who writes each file and every key.
- [preparing-a-repo](preparing-a-repo.md): what a repository needs before Carrier works on it.
- [troubleshooting](troubleshooting.md): what to check when something does not work.
- [releasing](releasing.md): how a release is cut and reaches an installed Carrier.
- [glossary](glossary.md): the terms Carrier uses.

## The macOS app, by area

- [app-shell](macos/app-shell.md): the app shell: Dock, menu bar item, window, sidebar and file icons, and Updates: the update pill (the About page is in settings).
- [lifecycle](macos/lifecycle.md): Lifecycle: how the app starts and replaces the engine and the chat host.
- [sessions](macos/sessions.md): Sessions: the home, the archive and how the app reads the chat host.
- [new-session](macos/new-session.md): Sessions: a new session as a plan, its workspace, worktree and preparation.
- [chat](macos/chat.md): Chat: the conversation, changing the agent, and the context and limits beside the microphone.
- [epics](macos/epics.md): Epics: the resume card, the pipeline, slices and findings, and the Agent output.
- [projects](macos/projects.md): Projects: the Projects page, a new project, Add as project and a project's defaults.
- [terminal](macos/terminal.md): Terminal: the embedded Ghostty terminal.
- [dictation](macos/dictation.md): Dictation: recognizers, the microphone, the global shortcut and the Dictation page.
- [usage](macos/usage.md): Usage: the quotas and the history of what was used.
- [keep-awake](macos/keep-awake.md): KeepAwake: keeping the Mac from sleeping.
- [settings](macos/settings.md): Settings: the window, its sidebar, its search and Sessions, Chat and About.
- [settings-app](macos/settings-app.md): Settings: General, Providers, Appearance, Notifications, Keybindings and Terminal.
- [settings-carrier](macos/settings-carrier.md): Settings: Watching, Roles, Identities, Behavior and Engine.
- [settings-health](macos/settings-health.md): Health: the Health page.
- [ui](ui.md): how every area looks: the rules of the look, the catalog of the pieces and what only macOS does.

## Working on Carrier

- [solve](agents/solve.md): the tracker, branching and worktree commands of the solve skills.
- [solve-flow](agents/solve-flow.md): how work moves from an idea to a merged epic.

Images used by the README: [assets](assets/) (`carrier-logo.png`, `app-overview.png`).

## Specs

### Engine and orchestrator

- [autonomous-orchestrator](specs/autonomous-orchestrator.md): the engine that runs ready epics with an author and a reviewer. Implemented (v0.1.0).
- [review-observations-pass](specs/review-observations-pass.md): the author answers what a review leaves before the epic is ready. Implemented (v0.1.0).
- [shared-identity](specs/shared-identity.md): one GitHub identity for author and reviewer, and a persona per role. Implemented (v0.1.0), superseded in part by ADR 0021.
- [forge-token-renewal-in-agent-runs](specs/forge-token-renewal-in-agent-runs.md): a Forge bot's token is renewed during a long run. Implemented (v0.1.0).
- [agent-failures-say-why](specs/agent-failures-say-why.md): a failed execution records its failure kind. Implemented (v0.1.0).
- [github-unavailable-says-why](specs/github-unavailable-says-why.md): GitHub being down is told apart from other failures. Implemented (v0.1.0).
- [repo-listing-paged](specs/repo-listing-paged.md): the repo list is browsed a page at a time. Implemented (v0.1.0).
- [choose-the-agent-option-per-epic](specs/choose-the-agent-option-per-epic.md): an agent option per role and failover when credits run out. Implemented (v0.1.0), superseded in part by ADR 0021.
- [engine-in-the-carrier-folder](specs/engine-in-the-carrier-folder.md): the engine keeps its files in the Carrier folder. Implemented (v0.1.0).
- [engine-start-is-quick](specs/engine-start-is-quick.md): the engine starts without waiting for GitHub. Implemented (v0.4.0).
- [settings-apply-without-restart](specs/settings-apply-without-restart.md): the engine reloads its configuration on request. Implemented (v0.4.0).
- [engine-never-stuck](specs/engine-never-stuck.md): the engine never leaves an epic stuck.
- [several-reviewers-and-a-lead](specs/several-reviewers-and-a-lead.md): several reviewers and a lead.
- [labels-and-skills-the-person-names](specs/labels-and-skills-the-person-names.md): labels and skills the person names.
- [review-to-trust-and-intake](specs/review-to-trust-and-intake.md): a review to trust, and an intake in order.
- [orchestrator-profile-in-init](specs/orchestrator-profile-in-init.md): the orchestrator's profile in init and in the failure that needs it.

### Command line, install and updates

- [carrier-terminal-experience](specs/carrier-terminal-experience.md): the terminal panel and running in the background. Implemented (v0.1.0).
- [carrier-installs-with-homebrew](specs/carrier-installs-with-homebrew.md): installing the command and the app with Homebrew. Implemented (v0.1.0).
- [carrier-updates-itself](specs/carrier-updates-itself.md): the app updates itself and brings the engine up to date. Implemented (v0.2.0).

### Chat host

- [chat-host](specs/chat-host.md): a process that holds chat sessions with any provider's agent. Implemented (v0.1.0).
- [session-worktrees](specs/session-worktrees.md): a session can work in its own worktree. Implemented (v0.1.0).
- [workspace-sources](specs/workspace-sources.md): a new session's folder, repository or new project. Implemented (v0.1.0), superseded in part by session-prepared-on-first-message.
- [chat-in-the-carrier-folder](specs/chat-in-the-carrier-folder.md): the chat host lives in the Carrier folder and the app starts it. Implemented (v0.1.0).
- [session-lifecycle](specs/session-lifecycle.md): sessions are archived and deleted by the clock. Implemented (v0.1.0).
- [session-prepared-on-first-message](specs/session-prepared-on-first-message.md): a new session is a plan prepared when the first message is sent. Implemented (v0.1.0).
- [chat-mcp-engine](specs/chat-mcp-engine.md): the chat host serves an MCP to the agents of its sessions. Implemented (unreleased); its exclusion of a tool that sees another session is lifted in part by switch-and-delegate-between-agents, for a parent and its children's `history`.
- [switch-and-delegate-between-agents](specs/switch-and-delegate-between-agents.md): a session changes agent and hands work to other agents. Spec, epic #1024.
- [delegate-from-any-mode](specs/delegate-from-any-mode.md): a session delegates in any mode, with no approval, and a child runs at its parent's permission level. Spec, epic #1129.
- [session-titles-from-a-text-generator](specs/session-titles-from-a-text-generator.md): a local model writes the session titles, chosen in Providers. Spec, epic #1196.
- [subagents-in-the-chat](specs/subagents-in-the-chat.md): the chat shows what the agent waits on and what its subagents do.
- [worktrees-start-from-remote](specs/worktrees-start-from-remote.md): a new worktree starts from the remote branch.

### Usage

- [usage-and-limits](specs/usage-and-limits.md): live quotas and the history of what was used, in the app and `carrier usage`. Implemented (unreleased).

### macOS app: window and sidebar

- [macos-app](specs/macos-app.md): the first macOS app, a menu bar item and a window over the control socket. Implemented (v0.1.0), superseded in part by macos-app-redesign.
- [macos-app-redesign](specs/macos-app-redesign.md): the redesigned window and the data behind it. Implemented (v0.1.0), superseded in part by sidebar-home-sessions-carrier.
- [sidebar-rows-title-first](specs/sidebar-rows-title-first.md): a sidebar row names its epic by title. Implemented (v0.1.0).
- [sidebar-home-sessions-carrier](specs/sidebar-home-sessions-carrier.md): the sidebar keeps Home, Sessions and Carrier apart. Implemented (v0.1.0), superseded in part by sidebar-flat-sections.
- [sidebar-flat-sections](specs/sidebar-flat-sections.md): the sidebar's sections lose their cards and open flat. Implemented (v0.1.0).

### macOS app: epics

- [macos-app-github-links](specs/macos-app-github-links.md): slices and review threads link to GitHub. Implemented (v0.1.0).
- [subagent-cards](specs/subagent-cards.md): the Agent output tab tells each slice of a ship session apart. Implemented (v0.1.0), superseded in part by agent-output-quiet-log.
- [finished-epics-in-view](specs/finished-epics-in-view.md): merged and cancelled epics stay in view. Implemented (v0.1.0).
- [earlier-sessions](specs/earlier-sessions.md): open the sessions the Agent output tab folded away. Superseded, the tab now lists every session.
- [pipeline-strip-states](specs/pipeline-strip-states.md): the pipeline strip shows where an epic is, with no times. Implemented (v0.1.0).
- [resume-a-stopped-epic](specs/resume-a-stopped-epic.md): a stopped epic can be resumed from the app. Implemented (v0.1.0).
- [slices-tab-all-slices](specs/slices-tab-all-slices.md): the Slices tab shows every slice, up to date. Implemented (v0.1.0).
- [agent-output-quiet-log](specs/agent-output-quiet-log.md): the Agent output tab reads as one quiet, ordered log. Implemented (v0.1.0).
- [file-diff-in-files-changed](specs/file-diff-in-files-changed.md): a changed file opens to the edited fragment. Implemented (v0.1.0).

### macOS app: sessions

- [sessions-in-the-app](specs/sessions-in-the-app.md): holding a session with an agent from the app. Implemented (v0.1.0).

### macOS app: settings

- [health-check-in-the-app](specs/health-check-in-the-app.md): the Health tab checks that Carrier has what it needs. Implemented (v0.1.0).
- [settings-app-group](specs/settings-app-group.md): Settings gets groups, with an App group and a Legacy group. Implemented (v0.1.3).
- [providers-in-settings](specs/providers-in-settings.md): the Providers page and `providers.json`. Implemented (v0.2.0).
- [repos-in-settings](specs/repos-in-settings.md): the Repos page. Implemented (v0.2.0).
- [projects](specs/projects.md): the Projects page, a project as an entry of `projects.json`, its worktrees and disk, its actions. Spec.
- [agents-in-settings](specs/agents-in-settings.md): the Agents page for the three roles. Implemented (v0.2.0).
- [updates-in-settings](specs/updates-in-settings.md): the Updates page and Check for Updates. Implemented (v0.3.0).
- [behavior-in-settings](specs/behavior-in-settings.md): the Behavior page in the Carrier group. Implemented (v0.4.0).
- [engine-in-settings](specs/engine-in-settings.md): the Engine page in the Carrier group. Implemented (unreleased).
- [sessions-in-settings](specs/sessions-in-settings.md): the Sessions page in the Chat group. Implemented (unreleased).
- [roles-and-identities-in-settings](specs/roles-and-identities-in-settings.md): Agents becomes Roles with every reviewer and the lead, and Identities a page of its own. Implemented (unreleased).

### macOS app: dictation

- [dictation-in-the-app](specs/dictation-in-the-app.md): dictating into the message box with local speech models. Implemented (v0.4.0).
- [dictation-live-and-fast](specs/dictation-live-and-fast.md): the model ready before the press, firm and tentative text, Parakeet over whole sentences. Spec.
- [global-dictation](specs/global-dictation.md): global dictation.

### macOS app: keep awake

- [keep-awake](specs/keep-awake.md): keeping the Mac from sleeping by hand or while agents work. Implemented (unreleased).

### macOS app: terminal

- [embedded-terminal-core](specs/embedded-terminal-core.md): native `GhosttyKit` terminal core with tabs, split panes, persistence, settings, and process close guards. Implemented (core only; UI unwired, unreleased).

### macOS app: structure

- [macos-app-as-the-base-for-a-web-front-end](specs/macos-app-as-the-base-for-a-web-front-end.md): the macOS app is reorganized as the base a web front-end is built on.

[specs/README.md](specs/README.md) says what each spec became.

## Decisions

### Engine and orchestration

- [0001 Separate coordination from repo evaluation](adr/orchestration/0001-separate-coordination-from-repo-evaluation.md)
- [0002 SQLite is the authority for state, labels are its mirror](adr/orchestration/0002-sqlite-authority-labels-mirror.md)
- [0003 Agents run isolated in containers](adr/agents/0003-agents-in-containers.md)
- [0004 Agents run on the host with the terminal's preferences](adr/agents/0004-agents-run-on-host-with-terminal-preferences.md)
- [0006 The engine records what the agents do as events in SQLite, with bounded and redacted output](adr/orchestration/0006-agent-events-stored-in-sqlite-with-bounded-output.md)
- [0008 Slices are kept in SQLite as a cache of GitHub, not as authority](adr/orchestration/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)
- [0009 A review that leaves observations triggers one resolve pass by the author before the epic is ready for test](adr/review/0009-observations-trigger-one-resolve-pass-before-ready-for-test.md)
- [0010 Carrier runs in the background as a detached process started on demand, not as a login service](adr/orchestration/0010-carrier-runs-in-the-background-as-a-detached-process.md)
- [0011 Author and reviewer may share one GitHub identity, signed visibly](adr/agents/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md)
- [0014 An epic chooses its agent option per role, and failover is opt-in](adr/agents/0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md)
- [0021 An epic starts on its three roles, and a role's failover chain names a provider and a model](adr/agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)
- [0023 The engine reloads its configuration on request, and running work keeps what it started with](adr/orchestration/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)
- [0043 Labels are named by who writes them, and every one is configurable](adr/orchestration/0043-labels-are-named-by-who-writes-them-and-every-one-is-configurable.md)
- [0044 Recover continues an epic from its real state, and no command sets one](adr/orchestration/0044-recover-continues-an-epic-from-its-real-state-and-no-command-sets-one.md)
- [0045 Each stage runs a skill the config names, and Carrier keeps the contract](adr/orchestration/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md)
- [0046 An unexpected error stops the epic it happened on, and the poll recovers an epic that lost its agent](adr/orchestration/0046-an-unexpected-error-stops-the-epic-it-happened-on-and-the-poll-recovers-an-epic-that-lost-its-agent.md)
- [0047 A review is tied to the head it was given, and a moved head is reviewed again](adr/review/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md)
- [0048 A review round has several reviewers in parallel, and a lead reviewer closes it](adr/review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md)
- [0049 A quota stop wakes up by itself when the provider says the window is back](adr/orchestration/0049-a-quota-stop-wakes-up-by-itself-when-the-provider-says-the-window-is-back.md)
- [0050 One authentication signal is a technical failure of its epic, and a profile stops when it repeats](adr/agents/0050-one-authentication-signal-is-a-technical-failure-of-its-epic-and-a-profile-stops-when-it-repeats.md)

### Chat host and sessions

- [0012 Sessions and epics are two separate worlds in the app](adr/sessions/0012-sessions-and-epics-are-two-separate-worlds.md)
- [0013 The chat host is its own process, with transcripts in SQLite and one adapter per provider](adr/sessions/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)
- [0014 A session worktree lives in Carrier's home and dies with its session](adr/projects/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)
- [0015 The chat brings projects onto the Mac with the person's own GitHub login](adr/projects/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)
- [0018 A new session is a plan, and the host prepares it when the first message is sent](adr/sessions/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)
- [0019 Sessions age by the clock, and an automatic delete never removes unsaved work](adr/sessions/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md)
- [0024 The chat MCP lives in the chat host and is injected per session](adr/sessions/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)
- [0032 A session changes agent by starting a new conversation, and the new agent reads the old one through the chat MCP](adr/sessions/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md)
- [0033 An agent delegates to another agent through child sessions, and every delegation asks the person](adr/sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)
- [0035 A worktree's folder goes when its work is done, and its branch stays](adr/projects/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md)
- [0036 A session delegates in every mode, and a child runs at its parent's permission level](adr/sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)
- [0037 A new worktree is cut from the remote branch by default, and choosing a project fetches it](adr/projects/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md)
- [0038 A text generator is declared in `providers.json`, and the chat host writes session titles with it](adr/agents/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)
- [0042 A session's worktree folder is cleaned by default](adr/projects/0042-a-session-worktree-folder-is-cleaned-by-default.md)

### Projects

- [0039 A project's actions are kept in Carrier and never read from the repository](adr/projects/0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)
- [0040 Deleting a project from disk is only for what Carrier made, goes to the Trash and stops at unsaved work](adr/projects/0040-deleting-a-project-from-disk-is-only-for-what-carrier-made-and-goes-to-the-trash.md)
- [0041 A project is an entry of `projects.json`, identified by its folder](adr/projects/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)

### Dictation

- [0023 Dictation runs on recognizers with a fixed list of downloadable speech models](adr/dictation/0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md)
- [0029 Global dictation is a widget that pastes once at the end and falls back to the clipboard](adr/dictation/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md)
- [0030 Dictation cleanup runs on local model servers through their API, not on agent CLIs](adr/dictation/0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md)
- [0031 Dictation keeps a history, and its statistics live apart from it](adr/dictation/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md)

### Usage

- [0025 Usage collection and serving run inside the chat host](adr/usage/0025-usage-runs-inside-the-chat-host.md)
- [0026 Claude's usage reads the login from the macOS Keychain, and never refreshes it](adr/usage/0026-claude-usage-reads-the-login-from-the-keychain-and-never-refreshes-it.md)

### The macOS app, install and updates

- [0005 The engine runs on its own and the macOS app is a client of its control socket](adr/app/0005-engine-independent-of-the-macos-app.md)
- [0007 Continue in Terminal: the engine sends a descriptor, the app builds and launches the command](adr/app/0007-continue-in-terminal-through-a-validated-descriptor.md)
- [0017 Carrier is installed with a Homebrew tap, and the app is not signed with a Developer ID](adr/release/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)
- [0022 The app updates itself with Sparkle, and the app brings the engine up to date through Homebrew](adr/release/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md)
- [0027 The embedded terminal runs in-process with GhosttyKit and restores layout across launches](adr/app/0027-embedded-terminal-runs-in-process-with-ghosttykit.md)
- [0028 Epic Continue in Terminal runs inside an ephemeral embedded Ghostty drawer](adr/app/0028-epic-continue-in-terminal-runs-in-embedded-ghostty-drawer.md)
- [0051 The app also ships as an Intel build, with its own zip and feed](adr/release/0051-the-app-also-ships-as-an-intel-build-with-its-own-zip-and-feed.md)
- [0052 The macOS app is split into three targets by layer, and each target by area](adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md)
- [0053 A config file of the Carrier folder is written only by Carrier's Node code, through its owner process or `carrier config`](adr/config/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)
- [0054 The look, the words and the app's preferences have one neutral source, generated for each front-end](adr/design/0054-the-look-the-words-and-the-apps-preferences-have-one-neutral-source-generated-for-each-front-end.md)
- [0055 A refusal, and every text Node sends a person, carries a code and its parameters, and its English words are the fallback](adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)
- [0058 Settings splits roles from identities, and a role holds everything it runs with](adr/app/0058-settings-splits-roles-from-identities-and-a-role-holds-everything-it-runs-with.md)

### The Carrier folder and its files

- [0016 Carrier keeps everything in one folder, with a subfolder per process and three levels of configuration](adr/config/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)
- [0020 Accounts live in a file both processes read](adr/agents/0020-accounts-live-in-a-file-both-processes-read.md)
- [0034 The Carrier folder keeps the edited files at the top and splits each process's folder by lifecycle](adr/config/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)

[adr/README.md](adr/README.md) has each one's status.

## Research

### Engine and agents

- [autonomous-ship-review](research/autonomous-ship-review.md): autonomous ship with iterative review (2026-10-14).
- [working-document](research/working-document.md): the first working document of the autonomous epic orchestrator (2026-10-15).
- [agent-containers](research/agent-containers.md): Claude and Codex inside containers on macOS (2026-10-15).
- [agent-forge](research/agent-forge.md): Agent Forge as an identity provider (2026-10-15).
- [headless-agents](research/headless-agents.md): Claude and Codex in headless mode (2026-10-15).
- [logging-panel](research/logging-panel.md): logging without breaking the terminal panel (2026-10-15).
- [shared-root](research/shared-root.md): a root folder shared with Solve (2026-10-15).
- [antigravity](research/antigravity.md): Antigravity (`agy`) as a third harness (2026-10-17).
- [antigravity-stream](research/antigravity-stream.md): Antigravity's `stream-json` event shapes (2026-10-21).
- [codex-exec-stream](research/codex-exec-stream.md): Codex's `exec --json` event shapes (2026-10-21).
- [interactive-resume](research/interactive-resume.md): resuming interactively a session the engine started headless (2026-10-21).
- [claude-subagent-attribution](research/claude-subagent-attribution.md): tying a Claude subagent message to a lane and a slice (2026-10-19).
- [agent-usage-limit-signals](research/agent-usage-limit-signals.md): usage-limit signals of Codex and Antigravity, and an `agy` login check (2026-10-27).
- [skill-discovery-per-harness](research/skill-discovery-per-harness.md): where each harness finds a skill, and what it does with a missing one.
- [engine-review-2026-11](research/engine-review-2026-11.md): review of the engine's flow, November 2026.

### The macOS app

- [macos-app](research/macos-app.md): slice progress, finding Node, notifications, stop and the control socket for the first macOS app (2026-10-19).
- [macos-app-command-script](research/macos-app-command-script.md): a generated `.command` script in Terminal, iTerm2, Ghostty and Warp (2026-10-21).
- [macos-app-data-engine](research/macos-app-data-engine.md): what the macOS app design needs from the engine (2026-10-21).
- [macos-app-data-github](research/macos-app-data-github.md): the GitHub and git data behind the macOS app design (2026-10-21).
- [macos-app-files-overlap-cost](research/macos-app-files-overlap-cost.md): the cost of the "also in lane" warning on a large repository (2026-10-21).
- [macos-app-github-graphql](research/macos-app-github-graphql.md): GitHub GraphQL queries with the Forge bot token (2026-10-21).
- [macos-app-login-item](research/macos-app-login-item.md): starting the ad hoc signed app at login (2026-10-21).
- [macos-app-swiftui](research/macos-app-swiftui.md): building the macOS app design in SwiftUI (2026-10-21).
- [macos-app-structure-map](research/macos-app-structure-map.md): the macOS app today, and where each file goes.
- [macos-performance-baseline](research/macos-performance-baseline.md): CPU, memory, launch and `usage` of the macOS app on 0.13.1, measured with the signposts of #1115 (2026-11-19).
- [sidebar-structure-spike](research/sidebar-structure-spike.md): whether the new sidebar fits the native `List(.sidebar)` (2026-10-27).

### Chat and sessions

- [chat-spike](research/chat-spike.md): the Claude and Codex chat paths against the real tools (2026-10-27).
- [in-app-sessions](research/in-app-sessions.md): talking to the agent of your choice inside the app (2026-10-27).
- [chat-subagents](research/chat-subagents.md): a real chat session with subagents, what the SDK sends and the two questions the epic left open (2026-11-17).
- [chat-agents-latest-versions-and-mcp-permissions](research/chat-agents-latest-versions-and-mcp-permissions.md): the latest Claude and Codex, and how the chat MCP's tools are approved and timed (2026-11-16).
- [switch-and-delegate-spike](research/switch-and-delegate-spike.md): what the spike found about handoffs, one tool asking for approval, permission levels and usage limits (2026-11-16).
- [t3-code-provider-switching](research/t3-code-provider-switching.md): how T3 Code switches provider in a thread and delegates to other agents (2026-11-16).
- [session-titles-model-and-prompt](research/session-titles-model-and-prompt.md): which local model and system message write session titles, measured on LM Studio (2026-11-21).

### Dictation

- [dictation-chunked-partials](research/dictation-chunked-partials.md): partial text from a fast model that does not stream (2026-11-12).
- [global-dictation-input](research/global-dictation-input.md): the global shortcut, the focus of another app and the paste with the clipboard kept (2026-11-16).

### Usage and updates

- [codexbar-usage-fetching](research/codexbar-usage-fetching.md): how CodexBar, T3 Code and Paradev fetch usage and scan history (2026-11-12).
- [sparkle-auto-update](research/sparkle-auto-update.md): Sparkle auto-update for an ad hoc signed, Homebrew-installed app (2026-11-11).

### Spikes and mockups

- [macos-app-design](research/macos-app-design/README.md): the HTML mockups of the macOS app.
- [macos-app-design/theme-reach](research/macos-app-design/theme-reach.md): how far the window's tint reaches.
- [spike-macos-app](research/spike-macos-app/README.md): the disposable menu bar app of the first research.
- [spike-switch-and-delegate](research/spike-switch-and-delegate/README.md): the spike behind the handoff and delegation research.
- [spike-switch-and-delegate results with Claude](research/spike-switch-and-delegate/results-claude.md).
- [spike-switch-and-delegate results with Claude 0.3.326](research/spike-switch-and-delegate/results-claude-0.3.326.md).
- [spike-switch-and-delegate results with Codex](research/spike-switch-and-delegate/results-codex.md).
- [spike-switch-and-delegate results of the handoff](research/spike-switch-and-delegate/results-handoff.md).
- [spike-switch-and-delegate results of the usage limits](research/spike-switch-and-delegate/results-limits.md).
- Code and fixtures of the other spikes, linked from the research that uses them: [chat-spike](research/chat-spike/), [session-titles-spike](research/session-titles-spike/), [spike-agent-containers](research/spike-agent-containers/), [spike-logging-panel](research/spike-logging-panel/), [spike-sidebar](research/spike-sidebar/), [spike-theme-reach](research/spike-theme-reach/).

[research/README.md](research/README.md) is the dated list.
