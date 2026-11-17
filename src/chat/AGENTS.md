# src/chat

The chat host ([ADR 0013](../../docs/adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), a process of its own that holds user sessions and shares no state with the engine.
It starts from the Carrier folder alone (`~/.carrier`, or `CARRIER_HOME`, [ADR 0016](../../docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) and reads no engine config.
It reads only `providers.json`, the accounts that a chat agent names with its `account`, at each request through `account.ts`: the adapters get the account's login, binary, compaction and launch arguments from it ([ADR 0020](../../docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
It keeps everything in `<folder>/chat/`: `state/` (`chat.db`, `chat.sock`, `carrier.lock`), `logs/`, `projects/`, `worktrees/` and its optional `chat.json`.

Adding a request to `chat.sock`: follow the checklist in [`src/control/AGENTS.md`](../control/AGENTS.md#adding-a-request-to-a-socket).
Adding a `chat.json` field: [`src/config/AGENTS.md`](../config/AGENTS.md#adding-a-config-field).

## Files

- `config.ts`: that file's schema, its defaults and the paths of the folder (a wrong file stops the host with the key named).
- `host.ts`: its lifecycle (lock, `chat.db`, socket).
- `server.ts`: the socket (`chat.sock`, a strict request union and a hello like the engine's).
- `idle.ts`: the rule that ends it.
- `sessions.ts`: what the requests do (open, send, events, close, the one-minute idle close, and `openPlan`).
  An archive of a live idle session does not wait for its agent to end (SIGTERM, then SIGKILL after three seconds): the session stops being live and is marked at once, the agent ends in the background and the host's stop waits for it. A delete does wait, as its worktree cannot be removed under a running agent.
  `openPlan`: a plan for a folder, a repository to clone or a new project, with the branch to check out (`checkout` in `workspace.ts`, refused on a folder with uncommitted changes) or a worktree from it, becomes a `preparing` session.
  Its steps (`clone` or `fetch` through `projects.cloneRepo`, whose latest git progress line the `events` reply carries as `progress`, never stored) run in the background and are stored as `step` events.
  `retryPreparation` repeats a failed one from where it stopped (the worktree recorded on the session and a checkout done are reused).
  `cancelPreparation` aborts the running step, deletes the session like a delete does and answers the plan ([ADR 0018](../../docs/adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
  The agent can begin a turn nobody asked for (the SDK wakes it when a task it ran in the background ends): the first word of one, with no turn running and the session idle and live, starts a turn of the host's own, so the session is working until the adapter's `turn_end`, which is then recorded like any other.
  A `background` event (the Claude adapter's reading of the SDK's `background_tasks_changed`) sets `live.background`, which `list` shows as the row's `background`: a session with some is not closed for being idle, is refused an archive or a delete, and an `interrupt` with no turn running stops those tasks (`stopBackground`), while `stopTask` stops just one of them by its id.
- `session-data.ts` and `pull-requests.ts`: what a row of `list` says besides the conversation, `diff` and `pr`.
  The lines a session changed come from `git diff --numstat` (read-only, with the repository's own diff and text filters off), counted from where its worktree was cut or where its folder left the default branch.
  Its pull request is looked for once, by the branch, with the person's own `gh` login (ADR 0015) and stored on the session (`prRepo`, `prNumber`, `prUrl`, `prState`, `prChecks`, `prCheckedAt`): after that only its state is asked again, by number and one GraphQL request for all the open ones, every minute while a list is asked for.
  A merged or closed one is final, and gives way only to a newer open one on the same branch.
  A `list` never waits for either: it answers with what is known and starts a sweep (at most every 15 seconds) that fills in the next; a turn ending reads that session's at once.
  Without `gh`, a network or an origin on GitHub a row simply has no pull request.
- `plan.ts`: the plan's request schema and the step types.
- `runner.ts`: the chat runner port, with `fake.ts` its test double; `claude.ts` and `codex.ts` are the Claude and Codex adapters.
- `folder.ts`: the check of a session's folder, never inside `<folder>/engine/` (and `checkProjectsFolder`, the same rule for the projects folder).
- `projects.ts`: what the chat brings onto the Mac with the person's own `gh` login, under the projects folder ([ADR 0015](../../docs/adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)).
  `cloneRepo` (waiters share one clone, which stops when nobody waits; only git's progress lines pass on, one a second), `createProject`, the `githubRepos` listing and `repoBranches`.
- `providers.ts`: the `providers` request (the accounts with their state, `unadded` for a harness found with no account, the local servers, or `problem` when `providers.json` does not match; built from `doctor/detect.ts`).
- `mcp.ts`: the chat MCP ([ADR 0024](../../docs/adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)), a loopback HTTP server the host starts before `chat.sock`.
  `McpSessionRegistry`: a bearer token per live conversation, kept hashed in memory, revoked by `invocationId` when `sessions.ts` closes, loses or fails that conversation.
  `defineTool`: every tool declares its access level.
  The toolkits are under `mcp/` (`capabilities` is the first); the adapters take the `mcp` argument of `ChatRunner.open`.
- `health.ts`: the `health` request (whether `git`, `gh` and each agent's CLI work and are signed in, as `ready`, `missing`, `signedOut` or `unknown`, only the verdicts; [spec](../../docs/specs/chat-host.md)).
- `git.ts`: the port to the machine's git (`realGit` in production, `FakeGit` in `fake.ts`).
- `workspace.ts`: what a folder is as a repository, and its fetch.
- `names.ts` and `words.ts`: the worktree name and its word lists.
- `worktree.ts`: the creation, the delete preview and the removal of a session's worktree under `<folder>/chat/worktrees` ([ADR 0014](../../docs/adr/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)).
- `transcript.ts`: the redact-then-cut limits.
- `schema.ts`, `db.ts`, `migrations/`: its own database (`pnpm db:generate` generates both).

## Its client and usage

`terminal/cli/commands/chat.ts` is its client and starts it detached (`detached.ts`, shared with `start`).
Its hello lists `accountIdentity` when `providers.json` may carry `label`, `icon` and `color` on an account (the strict schema of an older host refuses them): the app writes those keys only while it is there, and `agents` carries each agent's `account` so the app finds them.
It also answers `usage` (live quotas and the history, filtered by days, provider, source, search and account) and `usageOverride` (a model's price, kept in the `usage_price_overrides` table of `chat.db`) through [`src/usage`](../usage/AGENTS.md).
`terminal/cli/commands/usage.ts` is `carrier usage`, which checks the hello lists `usage` and waits 45 s for it.
