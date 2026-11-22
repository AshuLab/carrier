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
- `sessions.ts`: what the requests do (open, send, events, close, idle close, `openPlan`).
  Archiving a live idle session marks it at once and stops its agent in the background (host stop waits); deleting waits so its worktree can be removed safely.
  `openPlan`: prepares a folder, cloned repo or new project (`checkout` in `workspace.ts`, refused on uncommitted changes; `startFrom`, `worktreeStart`, fetch: [spec](../../docs/specs/session-worktrees.md)) in the background as `step` events (`events` carries git's latest progress line as `progress`).
  `retryPreparation` resumes from where it failed; `cancelPreparation` aborts, deletes the session and returns the plan ([ADR 0018](../../docs/adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)).
  A child session (`parentSessionId`, from `startChild` of `delegate_start`, [ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)) runs in its parent's folder with options lowered to the parent's level; its row is inserted before `await` (holding one of the parent's four slots and `delegationRequestId`) and deleted if opening fails.
  `list` omits children (`children` sits on the parent summary; `delegationRequestId` is never exposed); `send`, `resume`, `archive`, `delete`, `rename`, `regenerateTitle`, `setOption` and `switchAgent` refuse children via `refuseChild`, while `interrupt`, `close`, `answer` and `events` work.
  Children open with `child: true` (Allow/Deny only, no `act` on their MCP token).
  `switchAgent` ([ADR 0032](../../docs/adr/0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md)) moves an idle session to another agent: opens the new conversation with the handoff as `instructions`, closes the old only after MCP succeeds, guards with `switching`, detaches the old conversation and stores a `switched` notice (rebuilding handoff from events before it).
  `regenerateTitle` ([ADR 0038](../../docs/adr/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)) rewrites one title with the text generator, and `regenerateTitles` queues non-child active and archived first-line sessions in the background (`title_source`, `titleSourceOf`).
  After any `ok` turn of a non-child session with a reply and a `first_line` title, `autoTitle` writes one in the background and logs failures so the next turn retries.
- `text-generator.ts`: text-generator port, `realTextGenerator` (`/v1/chat/completions`), `FakeTextGenerator` in `fake.ts`; `title-prompt.ts`: fixed system message and prompt text.
- `session-data.ts`, `pull-requests.ts`: `diff` and `pr` of `list`, read in background sweep ([spec](../../docs/specs/chat-host.md)).
- `plan.ts`: plan schema and step types.
- `runner.ts`: chat runner port, `fake.ts` double, `claude.ts` and `codex.ts` adapters.
  Codex `usageLimitExceeded` emits `error` with `reason: 'usage_limit'` (`resetsAt` from `account/rateLimits/read`, fallback `resetText`) before `turn_end`.
- `folder.ts`: rejects folders inside `<folder>/engine/` (`checkProjectsFolder` for projects).
- `projects.ts`: `gh` projects under the projects folder ([ADR 0015](../../docs/adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)): `cloneRepo`, `createProject`, `githubRepos`, `repoBranches`.
- `providers.ts`: `providers` request (accounts, `unadded`, local servers, `textGenerator` or `problem`, via `doctor/detect.ts`).
- `mcp.ts`: loopback chat MCP ([ADR 0024](../../docs/adr/0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md)) started before `chat.sock`; `McpSessionRegistry` hashes bearer tokens per live conversation and revokes by `invocationId`.
  `defineTool` enforces token capabilities (`delegate_start` needs `act`), `delegation` tools check `sessions.delegationRefusal` (`levels.ts`: options on the scale in any mode, Codex app-server 0.122.0+), all tools go to `ChatRunner.open` (`allowedTools` / `canUseTool`), `delegate_wait` uses `waitChildren`, and `history` reads `related` sessions.
- `handoff.ts`: `buildHandoff`, up to 16,000 bytes, passed via `ChatRunner.open`'s `instructions` (Claude system prompt, Codex `developerInstructions`).
- `levels.ts`: four-level permission scale (`levelOf`, `childOptions`: at or under parent's level, or parent's when agent sets none; ADR 0033 and [ADR 0036](../../docs/adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)).
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
