# Architecture decision records

Each record is one hard-to-reverse decision, with its context and the alternatives it beat.
Numbers are never reused or renumbered, so 0014 and 0023 each hold two records.
A status that names a later record means that record changed part or all of this one.

| Number | Decision | Status |
| --- | --- | --- |
| 0001 | [Separate coordination from repo evaluation](0001-separate-coordination-from-repo-evaluation.md) | accepted |
| 0002 | [SQLite is the authority for state, labels are its mirror](0002-sqlite-authority-labels-mirror.md) | accepted |
| 0003 | [Agents run isolated in containers](0003-agents-in-containers.md) | superseded by [0004](0004-agents-run-on-host-with-terminal-preferences.md) |
| 0004 | [Agents run on the host with the terminal's preferences](0004-agents-run-on-host-with-terminal-preferences.md) | accepted |
| 0005 | [The engine runs on its own and the macOS app is a client of its control socket](0005-engine-independent-of-the-macos-app.md) | accepted |
| 0006 | [The engine records what the agents do as events in SQLite, with bounded and redacted output](0006-agent-events-stored-in-sqlite-with-bounded-output.md) | accepted |
| 0007 | [Continue in Terminal: the engine sends a descriptor, the app builds and launches the command](0007-continue-in-terminal-through-a-validated-descriptor.md) | accepted |
| 0008 | [Slices are kept in SQLite as a cache of GitHub, not as authority](0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md) | accepted |
| 0009 | [A review that leaves observations triggers one resolve pass by the author before the epic is ready for test](0009-observations-trigger-one-resolve-pass-before-ready-for-test.md) | accepted |
| 0010 | [Carrier runs in the background as a detached process started on demand, not as a login service](0010-carrier-runs-in-the-background-as-a-detached-process.md) | accepted |
| 0011 | [Author and reviewer may share one GitHub identity, signed visibly](0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md) | accepted; the `identities` key is replaced by a derived rule in [0021](0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) |
| 0012 | [Sessions and epics are two separate worlds in the app](0012-sessions-and-epics-are-two-separate-worlds.md) | accepted |
| 0013 | [The chat host is its own process, with transcripts in SQLite and one adapter per provider](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) | accepted |
| 0014 | [A session worktree lives in Carrier's home and dies with its session](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md) | accepted |
| 0014 | [An epic chooses its agent option per role, and failover is opt-in](0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md) | accepted; the choice at the start of an epic and the shape of failover are superseded by [0021](0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) |
| 0015 | [The chat brings projects onto the Mac with the person's own GitHub login](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) | accepted |
| 0016 | [Carrier keeps everything in one folder, with a subfolder per process and three levels of configuration](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) | accepted |
| 0017 | [Carrier is installed with a Homebrew tap, and the app is not signed with a Developer ID](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) | accepted |
| 0018 | [A new session is a plan, and the host prepares it when the first message is sent](0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) | accepted |
| 0019 | [Sessions age by the clock, and an automatic delete never removes unsaved work](0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md) | accepted |
| 0020 | [Accounts live in a file both processes read](0020-accounts-live-in-a-file-both-processes-read.md) | accepted; its `enabled` key is superseded by [0021](0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) |
| 0021 | [An epic starts on its three roles, and a role's failover chain names a provider and a model](0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) | accepted |
| 0022 | [The app updates itself with Sparkle, and the app brings the engine up to date through Homebrew](0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md) | accepted |
| 0023 | [Dictation runs on recognizers with a fixed list of downloadable speech models](0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) | accepted |
| 0023 | [The engine reloads its configuration on request, and running work keeps what it started with](0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md) | accepted |
| 0024 | [The chat MCP lives in the chat host and is injected per session](0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) | accepted |
| 0025 | [Usage collection and serving run inside the chat host](0025-usage-runs-inside-the-chat-host.md) | accepted |
| 0027 | [The embedded terminal runs in-process with GhosttyKit and restores layout across launches](0027-embedded-terminal-runs-in-process-with-ghosttykit.md) | accepted |
