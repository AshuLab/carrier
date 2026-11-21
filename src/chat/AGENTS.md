# src/chat

The chat host ([ADR 0013](../../docs/adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), a process of its own that holds user sessions and shares no state with the engine.
It starts from the Carrier folder alone ([ADR 0016](../../docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) and reads no engine config.
It reads only `providers.json`, the accounts that a chat agent names with its `account`, at each request through `account.ts`: the adapters get the account's login, binary, compaction and launch arguments from it ([ADR 0020](../../docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
It keeps `state/`, `logs/`, `projects/`, `worktrees/`, `sessions/` and `pending/` in `<folder>/chat/`, settings in `<folder>/chat.json` (paths: `config/places.ts`).

Adding a request to `chat.sock`: follow the checklist in [`src/control/AGENTS.md`](../control/AGENTS.md#adding-a-request-to-a-socket).
Adding a `chat.json` field: [`src/config/AGENTS.md`](../config/AGENTS.md#adding-a-config-field).

## Files

- `config.ts`: that file's schema, its defaults and the paths of the folder (a wrong file stops the host with the key named).
- `host.ts`: its lifecycle (lock, `chat.db`, socket).
- `server.ts`: the socket (`chat.sock`, a strict request union and a hello like the engine's).
- `idle.ts`: the rule that ends it.
- `sessions.ts`: what the requests do (open, send, events, close, the idle close of a session no request names, and `openPlan`).
  An archive of a live idle session does not wait for its agent to end: the session stops being live and is marked at once, the agent ends in the background and the host's stop waits for it. A delete does wait, as its worktree cannot be removed under a running agent.
  `openPlan`: a plan for a folder, a repository to clone or a new project, with the branch to check out (`checkout` in `workspace.ts`, refused on a folder with uncommitted changes) or a worktree from it, becomes a `preparing` session.
  Its steps (`clone`, `fetch` via `projects.cloneRepo`; the `events` reply carries its latest git progress line as `progress`) run in the background and are stored as `step` events.
  A plan's `startFrom`, `worktreeStart` and the fetch before the cut: [spec](../../docs/specs/session-worktrees.md).
  `retryPreparation` repeats a failed one from where it stopped (the worktree recorded on the session and a checkout done are reused).
  `cancelPreparation` aborts the running step, deletes the session like a delete does and answers the plan ([ADR 0018](../../docs/adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
  A child session (`parentSessionId`, from `startChild` of the MCP's `delegate_start`, [ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)) is a session of its own agent in its parent's folder, recorded as a plain folder, with its agent's options lowered to the parent's level.
  Its row is inserted first, so it holds one of the parent's four slots and its `delegationRequestId` while its conversation opens, and goes if the open fails (no `await` between the check and the insert).
  The list leaves children out, a parent's summary lists them as `children`, and `delegationRequestId` is never in a summary.
  A child belongs to its parent: `send`, `resume`, `archive`, `delete`, `rename` and `setOption` (and a switch of agent) are refused through `refuseChild`, while `interrupt`, `close`, `answer` and `events` work as on any session.
  It opens with `child: true`, so its adapter's approvals offer Allow and Deny and none of the suggestions that would raise it, and its MCP token never gets `act`.
  `switchAgent` ([ADR 0032](../../docs/adr/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md)) moves an idle session to another configured agent: a new conversation opens with the handoff as its `instructions`, and the old one is closed only after the new one opened with the chat MCP, so any refusal (busy, archived or child session, an unusable agent or model, a conversation that does not open or has no MCP) leaves the session as it was.
  The session is in `switching`, a marker of its own and not the delete's, that every request on the session and a second switch check; the old conversation is detached (its events are no longer recorded) and stays the session's recorded process until it ends.
  The notice it stores has `switched: { from, to }`, and every later open or resume of that conversation passes the handoff again, built from the events before that notice (none for a session with no message).
  `regenerateTitle` ([ADR 0038](../../docs/adr/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)) writes a title with the text generator over any title, one call at a time; `sessions.title_source` says where a title came from (`titleSourceOf` reads a row with none).
  After any `ok` turn of a non-child session with a reply and a `first_line` title, `autoTitle` writes one in the background and logs failures so the next turn retries.
- `text-generator.ts`: the text-generator port, `realTextGenerator` (the server's `/v1/chat/completions`), and `FakeTextGenerator` in `fake.ts`; `title-prompt.ts`: the fixed system message and the text it gets.
- `session-data.ts` and `pull-requests.ts`: the `diff` and `pr` of a `list` row, read in a background sweep, never in the request ([spec](../../docs/specs/chat-host.md)).
- `plan.ts`: the plan's request schema and the step types.
- `runner.ts`: the chat runner port, with `fake.ts` its test double; `claude.ts` and `codex.ts` are the Claude and Codex adapters.
  Codex's usage limit (`usageLimitExceeded`, not retried) is an `error` with `reason: 'usage_limit'`: its `resetsAt` is read from `account/rateLimits/read` and `resetText` is the error's own `try again at ...` when that gives none; the error is emitted before the turn's `turn_end`.
- `folder.ts`: the check of a session's folder, never inside `<folder>/engine/` (and `checkProjectsFolder`, the same rule for the projects folder).
- `projects.ts`: what the chat brings onto the Mac with the person's own `gh` login, under the projects folder ([ADR 0015](../../docs/adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)).
  `cloneRepo` (waiters share one clone, which stops when nobody waits; only git's progress lines pass on, one a second), `createProject`, the `githubRepos` listing and `repoBranches`.
- `providers.ts`: the `providers` request (the accounts with their state, `unadded` for a harness found with no account, the local servers, the `textGenerator` in use, with its name, kind and model, when `providers.json` names one, or `problem` when it does not match; built from `doctor/detect.ts`).
- `mcp.ts`: the chat MCP ([ADR 0024](../../docs/adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)), a loopback HTTP server the host starts before `chat.sock`.
  `McpSessionRegistry`: a bearer token per live conversation, kept hashed in memory, revoked by `invocationId` when `sessions.ts` closes, loses or fails that conversation.
  `defineTool`: every tool declares its access level.
  A tool is listed and callable only for a token with the capability its access level needs: `delegate_start` (`mcp/delegate.ts`) needs `act`, which a session with no parent gets.
  A tool marked `delegation` is also listed only while `sessions.delegationRefusal` (`levels.ts`: options on the scale in any mode, Codex app-server 0.122.0 or later) finds none, and that check runs again on the call; `agents` says the same words as `notOffered`.
  Every tool of the chat MCP is handed to the adapters by name (`tools` of `ChatRunner.open`) and runs unasked: Claude names each in `allowedTools`, and its `canUseTool` allows them in `plan`, where the harness asks whatever `allowedTools` says.
  `delegate_wait` (`readsAsSession`) waits for the caller's children through `waitChildren`, and `history` also reads a child or the parent (`related`).
  The toolkits are under `mcp/`; the adapters take the `mcp` argument of `ChatRunner.open`.
- `handoff.ts`: `buildHandoff`, the pure builder of a switched session's handoff from its stored events, 16,000 bytes at most (ADR 0032, linked above); it travels as `ChatRunner.open`'s `instructions` (Claude appends it to its system prompt, Codex sends `developerInstructions`).
- `levels.ts`: the permission scale of four levels as pure data (`levelOf`, `childOptions`): a child gets the options of its agent at or under its parent's level (ADR 0033, linked above, and [ADR 0036](../../docs/adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)).
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
Its hello lists `textGenerators` when `providers.json` may carry `textGenerators` and `textGenerator` (an older host refuses them): the app writes those keys only while it is there.
It lists `accountPalette` when the schema also takes the later icons and colors (`accountIcons`, `accountColors` in `src/config/providers.ts`; the earlier ones come first): the app offers the later ones only while it is there, since an `accountIdentity` host refuses a file with one.
It also answers `usage` (live quotas and the history, filtered by days, provider, source, search and account) and `usageOverride` (a model's price, kept in the `usage_price_overrides` table of `chat.db`) through [`src/usage`](../usage/AGENTS.md).
`terminal/cli/commands/usage.ts` is `carrier usage`, which checks the hello lists `usage` and waits 45 s for it.
