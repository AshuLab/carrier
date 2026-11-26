# Architecture decision records

Each record is one hard-to-reverse decision, with its context and the alternatives it beat.
Records are filed by topic, the same topics as [the glossary](../glossary.md).
Numbers are global, never reused or renumbered, so 0014 and 0023 each hold two records.
A status that names a later record means that record changed part or all of this one.

## orchestration

- [0001](orchestration/0001-separate-coordination-from-repo-evaluation.md) - Separate coordination from repo evaluation (accepted)
- [0002](orchestration/0002-sqlite-authority-labels-mirror.md) - SQLite is the authority for state, labels are its mirror (accepted)
- [0006](orchestration/0006-agent-events-stored-in-sqlite-with-bounded-output.md) - The engine records what the agents do as events in SQLite, with bounded and redacted output (accepted; amended by [0042](projects/0042-a-session-worktree-folder-is-cleaned-by-default.md) (the raw log is capped))
- [0008](orchestration/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md) - Slices are kept in SQLite as a cache of GitHub, not as authority (accepted)
- [0010](orchestration/0010-carrier-runs-in-the-background-as-a-detached-process.md) - Carrier runs in the background as a detached process started on demand, not as a login service (accepted)
- [0023](orchestration/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md) - The engine reloads its configuration on request, and running work keeps what it started with (accepted)
- [0043](orchestration/0043-labels-are-named-by-who-writes-them-and-every-one-is-configurable.md) - Labels are named by who writes them, and every one is configurable (accepted)
- [0044](orchestration/0044-recover-continues-an-epic-from-its-real-state-and-no-command-sets-one.md) - Recover continues an epic from its real state, and no command sets one (accepted)
- [0045](orchestration/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md) - Each stage runs a skill the config names, and Carrier keeps the contract (accepted)
- [0046](orchestration/0046-an-unexpected-error-stops-the-epic-it-happened-on-and-the-poll-recovers-an-epic-that-lost-its-agent.md) - An unexpected error stops the epic it happened on, and the poll recovers an epic that lost its agent (accepted)
- [0049](orchestration/0049-a-quota-stop-wakes-up-by-itself-when-the-provider-says-the-window-is-back.md) - A quota stop wakes up by itself when the provider says the window is back (accepted)

## review

- [0009](review/0009-observations-trigger-one-resolve-pass-before-ready-for-test.md) - A review that leaves observations triggers one resolve pass by the author before the epic is ready for test (accepted)
- [0047](review/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md) - A review is tied to the head it was given, and a moved head is reviewed again (accepted)
- [0048](review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md) - A review round has several reviewers in parallel, and a lead reviewer closes it (accepted)

## agents

- [0003](agents/0003-agents-in-containers.md) - Agents run isolated in containers (superseded by [0004](agents/0004-agents-run-on-host-with-terminal-preferences.md))
- [0004](agents/0004-agents-run-on-host-with-terminal-preferences.md) - Agents run on the host with the terminal's preferences (accepted)
- [0011](agents/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md) - Author and reviewer may share one GitHub identity, signed visibly (accepted; the `identities` key is replaced by a derived rule in [0021](agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md))
- [0014](agents/0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md) - An epic chooses its agent option per role, and failover is opt-in (accepted; the choice at the start of an epic and the shape of failover are superseded by [0021](agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md))
- [0020](agents/0020-accounts-live-in-a-file-both-processes-read.md) - Accounts live in a file both processes read (accepted; its `enabled` key is superseded by [0021](agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md))
- [0021](agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) - An epic starts on its three roles, and a role's failover chain names a provider and a model (accepted)
- [0038](agents/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md) - A text generator is declared in `providers.json`, and the chat host writes session titles with it (proposed)
- [0050](agents/0050-one-authentication-signal-is-a-technical-failure-of-its-epic-and-a-profile-stops-when-it-repeats.md) - One authentication signal is a technical failure of its epic, and a profile stops when it repeats (accepted)

## config

- [0016](config/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) - Carrier keeps everything in one folder, with a subfolder per process and three levels of configuration (accepted; the folder's layout is superseded by [0034](config/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md))
- [0034](config/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md) - The Carrier folder keeps the edited files at the top and splits each process's folder by lifecycle (accepted)
- [0053](config/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md) - A config file of the Carrier folder is written only by Carrier's Node code, through its owner process or `carrier config` (proposed; amends [0020](agents/0020-accounts-live-in-a-file-both-processes-read.md) and [0041](projects/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md))

## sessions

- [0012](sessions/0012-sessions-and-epics-are-two-separate-worlds.md) - Sessions and epics are two separate worlds in the app (accepted)
- [0013](sessions/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) - The chat host is its own process, with transcripts in SQLite and one adapter per provider (accepted; a session may change its agent under [0032](sessions/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md); a child session never has more privilege than its parent under [0033](sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md))
- [0018](sessions/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) - A new session is a plan, and the host prepares it when the first message is sent (accepted; amended by [0041](projects/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md))
- [0019](sessions/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md) - Sessions age by the clock, and an automatic delete never removes unsaved work (accepted)
- [0024](sessions/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) - The chat MCP lives in the chat host and is injected per session (accepted; its pre-approval of every tool is narrowed by [0033](sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) for the tool that starts a delegation and widened again by [0036](sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md))
- [0032](sessions/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md) - A session changes agent by starting a new conversation, and the new agent reads the old one through the chat MCP (accepted)
- [0033](sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md) - An agent delegates to another agent through child sessions, and every delegation asks the person (accepted; amended by [0036](sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md))
- [0036](sessions/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md) - A session delegates in every mode, and a child runs at its parent's permission level (accepted)

## projects

- [0014](projects/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md) - A session worktree lives in Carrier's home and dies with its session (accepted; amended by [0035](projects/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md), whose opt-in cleanup is on by default since [0042](projects/0042-a-session-worktree-folder-is-cleaned-by-default.md))
- [0015](projects/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) - The chat brings projects onto the Mac with the person's own GitHub login (accepted; its list and projects folder are amended by [0041](projects/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md), its "never deletes" by [0040](projects/0040-deleting-a-project-from-disk-is-only-for-what-carrier-made-and-goes-to-the-trash.md))
- [0035](projects/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) - A worktree's folder goes when its work is done, and its branch stays (accepted; amended by [0042](projects/0042-a-session-worktree-folder-is-cleaned-by-default.md) (the defaults of `worktreeCleanup`); its per-repo setup is [0039](projects/0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md))
- [0037](projects/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md) - A new worktree is cut from the remote branch by default, and choosing a project fetches it (accepted)
- [0039](projects/0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md) - A project's actions are kept in Carrier and never read from the repository (accepted)
- [0040](projects/0040-deleting-a-project-from-disk-is-only-for-what-carrier-made-and-goes-to-the-trash.md) - Deleting a project from disk is only for what Carrier made, goes to the Trash and stops at unsaved work (accepted)
- [0041](projects/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md) - A project is an entry of `projects.json`, identified by its folder (accepted)
- [0042](projects/0042-a-session-worktree-folder-is-cleaned-by-default.md) - A session's worktree folder is cleaned by default (accepted; amends [0035](projects/0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) and [0006](orchestration/0006-agent-events-stored-in-sqlite-with-bounded-output.md))

## dictation

- [0023](dictation/0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) - Dictation runs on recognizers with a fixed list of downloadable speech models (accepted)
- [0029](dictation/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md) - Global dictation is a widget that pastes once at the end and falls back to the clipboard (proposed)
- [0030](dictation/0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md) - Dictation cleanup runs on local model servers through their API, not on agent CLIs (proposed)
- [0031](dictation/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md) - Dictation keeps a history, and its statistics live apart from it (proposed)

## usage

- [0025](usage/0025-usage-runs-inside-the-chat-host.md) - Usage collection and serving run inside the chat host (accepted; its file-only Claude login is extended to the Keychain by [0026](usage/0026-claude-usage-reads-the-login-from-the-keychain-and-never-refreshes-it.md))
- [0026](usage/0026-claude-usage-reads-the-login-from-the-keychain-and-never-refreshes-it.md) - Claude's usage reads the login from the macOS Keychain, and never refreshes it (accepted)

## release

- [0017](release/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) - Carrier is installed with a Homebrew tap, and the app is not signed with a Developer ID (accepted)
- [0022](release/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md) - The app updates itself with Sparkle, and the app brings the engine up to date through Homebrew (accepted)
- [0051](release/0051-the-app-also-ships-as-an-intel-build-with-its-own-zip-and-feed.md) - The app also ships as an Intel build, with its own zip and feed (proposed)

## app

- [0005](app/0005-engine-independent-of-the-macos-app.md) - The engine runs on its own and the macOS app is a client of its control socket (accepted)
- [0007](app/0007-continue-in-terminal-through-a-validated-descriptor.md) - Continue in Terminal: the engine sends a descriptor, the app builds and launches the command (accepted; epic execution is superseded by [0028](app/0028-epic-continue-in-terminal-runs-in-embedded-ghostty-drawer.md))
- [0027](app/0027-embedded-terminal-runs-in-process-with-ghosttykit.md) - The embedded terminal runs in-process with GhosttyKit and restores layout across launches (accepted; owner types and epic integration updated in [0028](app/0028-epic-continue-in-terminal-runs-in-embedded-ghostty-drawer.md))
- [0028](app/0028-epic-continue-in-terminal-runs-in-embedded-ghostty-drawer.md) - Epic Continue in Terminal runs inside an ephemeral embedded Ghostty drawer (accepted)
- [0056](app/0056-settings-splits-roles-from-identities-and-a-role-holds-everything-it-runs-with.md) - Settings splits roles from identities, and a role holds everything it runs with (proposed)

## design

- [0052](design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md) - The macOS app is split into three targets by layer, and each target by area (proposed)
- [0054](design/0054-the-look-the-words-and-the-apps-preferences-have-one-neutral-source-generated-for-each-front-end.md) - The look, the words and the app's preferences have one neutral source, generated for each front-end (proposed)
- [0055](design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md) - A refusal, and every text Node sends a person, carries a code and its parameters, and its English words are the fallback (proposed)
