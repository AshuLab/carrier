# src/chat

The chat host ([ADR 0013](../../docs/adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)), a process of its own that holds user sessions and shares no state with the engine.
It starts from the Carrier folder alone ([ADR 0016](../../docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) and reads no engine config, only `providers.json` at each request through `account.ts` ([ADR 0020](../../docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
It keeps its state in `<folder>/chat/`, settings in `<folder>/chat.json` (paths: `config/places.ts`).

Adding a request to `chat.sock`: follow the checklist in [`src/control/AGENTS.md`](../control/AGENTS.md#adding-a-request-to-a-socket).
Adding a `chat.json` field: [`src/config/AGENTS.md`](../config/AGENTS.md#adding-a-config-field).

## Files

- `config.ts`: that file's schema, its defaults and the paths of the folder.
- `host.ts`: its lifecycle (lock, `chat.db`, socket).
- `server.ts`: the socket (`chat.sock`, a strict request union and a hello like the engine's).
- `idle.ts`: the rule that ends the host.
- `sessions.ts`: what the requests do (open, send, events, close, the idle close of a session no request names, `openPlan`).
  An archive of a live idle session does not wait for its agent to end; a delete does: its worktree cannot go under a running agent.
  `openPlan`: a plan (a folder, a repository to clone or a new project, with a branch or a worktree) becomes a `preparing` session; its steps (`clone`, `fetch`, `worktree`, `checkout`, `action`) run in the background and are stored as `step` events (ADR 0018; `startFrom`, `worktreeStart` and the fetch before the cut: [spec](../../docs/specs/session-worktrees.md)).
  A project's actions (ADR 0039, `runActions`; rules and environment: [projects spec](../../docs/specs/projects.md)) are read from `projects.json` at each preparation: `afterClone` after the `clone` step, `newWorktree` after `worktree` or `checkout` and before the agent; `restore` (`folderOf`) runs the `newWorktree` ones when a cleaned folder comes back, one per session (`restoring`: cleanup, delete, archive refuse, `summary` says `running`).
  A stop or `cancelPreparation` aborts the running action; a restore keeps its folder and the next open goes on from that action, `retryPreparation` repeats a failed preparation from where it stopped, and `cancelPreparation` deletes the session and answers the plan.
  A child session (`parentSessionId`, from `startChild` of `delegate_start`, ADR 0033) is a session of its own agent in its parent's folder, with its options lowered to the parent's level.
  Its row is inserted first (no `await` before the insert), so it holds one of the parent's four slots and its `delegationRequestId` (never in a summary) while it opens, and goes if the open fails. The list leaves children out; a parent's summary has `children`.
  `refuseChild` refuses `send`, `resume`, `archive`, `delete`, `rename`, `regenerateTitle`, `setOption` and a switch on a child; `interrupt`, `close`, `answer`, `events` work as on any. It opens with `child: true` (Allow and Deny only) and its MCP token never gets `act`.
  `switchAgent` (ADR 0032) moves an idle session to another agent: the new conversation opens with the handoff as its `instructions`, the old one closes after that, so a refusal leaves the session as it was.
  The session is in `switching`, which every request and a second switch check; the old conversation is detached. The notice has `switched: { from, to }`, and later opens and resumes pass the handoff again.
  `regenerateTitle` ([ADR 0038](../../docs/adr/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)) rewrites one title with the text generator, `regenerateTitles` queues the first-line ones in the background, and `autoTitle` titles a session after its first ok reply.
- `text-generator.ts`, `title-prompt.ts`: the text-generator port (`realTextGenerator`, `FakeTextGenerator` in `fake.ts`) and the fixed title prompt.
- `session-data.ts` and `pull-requests.ts`: the `diff` and `pr` of a `list` row, read in a background sweep ([spec](../../docs/specs/chat-host.md)).
- `plan.ts`: the plan's request schema and step types.
- `shell.ts`: the port through which a project's actions run (`realShell`: its own process group, SIGKILL after 3 s); `FakeShell` in `fake.ts`, and no test runs a real command.
- `runner.ts`: the chat runner port, with `fake.ts` its test double; `claude.ts` and `codex.ts` are the Claude and Codex adapters.
  Codex's `usageLimitExceeded` (not retried) is an `error` with `reason: 'usage_limit'` before `turn_end`; `resetsAt` comes from `account/rateLimits/read`, else `resetText`.
- `folder.ts`: the check of a session's folder (never inside `<folder>/engine/`), `checkProjectsFolder` and `checkProjectFolder` (shared table: `macos/Tests/Fixtures/project-folder.json`).
- `projects.ts`: what the chat brings onto the Mac with the person's own `gh` login, under the projects folder (ADR 0015).
  `cloneRepo` (waiters share one clone, which stops when nobody waits; git's progress lines pass on, one a second), `createProject`, `githubRepos` and `repoBranches`.
  A preparation that cloned or made its workspace registers the folder in `projects.json` once it succeeded (`register` in `sessions.ts`; origin `created`, `cloned` or `added`); a failed or cancelled one, or a folder the person chose, writes nothing.
  The `projects` capability: `cloneProject` clones from Settings in the background into `<parent or the projects folder>/<owner>/<name>` and answers at once (registered when git ends); `newProject` makes `<parent or the projects folder>/local/<name>` with `git init -b main`, origin `created`, and refuses first a taken name, a parent inside Carrier's own folders or a `projects.json` that does not match (`cloneProject` too).
  `projectClones` lists clones running and failed (kept until `dismissClone`); a running clone holds the idle exit, a stop aborts it and removes what it made.
  `projectWorktrees` (in `sessions.ts`, it joins `chat.db`) answers a project's main clone and its `worktrees/` still on disk with branch, session, age, an `activity` (`sessionOpen`, `uncommitted` or null), an `integration` (`merged`, `inMain`, `notPushed`, `prOpen`, `prClosed`, `pushed`) and the session's saved `pullRequest` (refreshed first, in one request through `data.refresh`, for the open or draft ones of the listed worktrees' sessions, archived included; `cleanProjectWorktrees` too, `removeProjectWorktree` not), behind the `worktreeIntegration` capability ([spec](../../docs/specs/worktree-state-in-projects.md); `inMain` is the worktree's HEAD being an ancestor of `refs/remotes/origin/HEAD`, never guessed); the main clone keeps a `state`, `uncommitted`, `notPushed` or `clean`, `uncommitted`, `notPushed` or `clean`, which the app reads before the Trash.
  `removeProjectWorktree` takes only one of those folders (`clearWorktree`: the branch stays, `restoreWorktree` brings it back on resume), refused while its session is open or it has uncommitted changes; `cleanProjectWorktrees` lists, and with `run` removes, the finished ones (with a session, Merged or In main) nothing blocks.
- `disk.ts`: what a project takes on disk, behind the `projects` capability ([how](../../docs/specs/chat-host.md#refusals-and-config-requests-in-the-code)).
- `ChatRefused`, `project-edits.ts`, `providers-requests.ts`, `engine-reload.ts`: [refusals and config requests](../../docs/specs/chat-host.md#refusals-and-config-requests-in-the-code).
- `providers.ts`: the `providers` request (accounts with their state, `unadded`, local servers, `textGenerator` or `problem`; built from `doctor/detect.ts`).
- `mcp.ts`: the chat MCP (ADR 0024), a loopback HTTP server the host starts before `chat.sock`; toolkits under `mcp/`.
  `McpSessionRegistry`: a hashed bearer token per live conversation, revoked by `invocationId` when it ends.
  `defineTool`: every tool declares its access level and is listed and callable only for a token with the capability it needs (`delegate_start`, `mcp/delegate.ts`, needs `act`); a `delegation` tool also needs `sessions.delegationRefusal` (`levels.ts`) to find none, checked again on the call.
  Every tool is handed to the adapters by name (`tools` of `ChatRunner.open`) and runs unasked (Claude: `allowedTools`, and `canUseTool` in `plan`). `delegate_wait` uses `waitChildren`; `history` also reads `related` sessions.
- `handoff.ts`: `buildHandoff`, a switched session's handoff, 16,000 bytes at most, passed as `ChatRunner.open`'s `instructions`.
- `levels.ts`: the permission scale of four levels as pure data (`levelOf`, `childOptions`; ADR 0036).
- `health.ts`: the `health` request (`git`, `gh` and each agent's CLI, only the verdicts; [spec](../../docs/specs/chat-host.md)).
- `git.ts`: the port to the machine's git (`realGit` in production, `FakeGit` in `fake.ts`).
- `workspace.ts`: what a folder is as a repository, and its fetch.
- `names.ts` and `words.ts`: the worktree name, where a worktree lives (`worktreeDirectory`, `worktreePath`) and `checkWorktreeClash` (shared table: `macos/Tests/Fixtures/worktree-clash.json`).
- `worktree.ts`: the creation, the delete preview and the removal of a session's worktree under `<folder>/chat/worktrees` ([ADR 0014](../../docs/adr/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)).
- `transcript.ts`: the redact-then-cut limits.
- `schema.ts`, `db.ts`, `migrations/`: its own database (`pnpm db:generate` generates both).

## Its client and usage

`terminal/cli/commands/chat.ts` is its client and starts it detached (`detached.ts`, shared with `start`).
Its hello lists `accountIdentity` (`providers.json` may carry `label`, `icon`, `color` on an account) and `accountPalette` (the later icons and colors, `accountIcons`, `accountColors` in `src/config/providers.ts`); the app writes those keys only while the hello lists them, as an older host's strict schema refuses them ([how](../../docs/macos/settings-app.md)).
Its hello lists `textGenerators` when `providers.json` may carry `textGenerators` and `textGenerator`; the app writes those keys only while it is there.
It also answers `usage` and `usageOverride` through [`src/usage`](../usage/AGENTS.md).
`terminal/cli/commands/usage.ts` is `carrier usage`, which checks the hello lists `usage` and waits 45 s for it.
