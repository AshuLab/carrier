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
  An archive of a live idle session does not wait for its agent to end; a delete does, as its worktree cannot be removed under a running agent.
  `openPlan`: a plan (a folder, a repository to clone or a new project, with a branch to check out or a worktree from it) becomes a `preparing` session; its steps (`clone`, `fetch`, `worktree`, `checkout`, `action`) run in the background and are stored as `step` events (ADR 0018; `startFrom`, `worktreeStart` and the fetch before the cut: [spec](../../docs/specs/session-worktrees.md)).
  A project's actions (ADR 0039, `runActions`; rules and environment: [projects spec](../../docs/specs/projects.md)) are read from `projects.json` at each preparation: `afterClone` after the `clone` step, `newWorktree` after `worktree` or `checkout` and before the agent; `runRestoreActions` runs the `newWorktree` ones when a cleaned worktree folder is made again (`folderOf`: resume, a child, a switch).
  A stop or `cancelPreparation` aborts the running action and cleans the folder, so the next open runs every action again; `retryPreparation` repeats a failed preparation from where it stopped; `cancelPreparation` deletes the session like a delete and answers the plan.
  A child session (`parentSessionId`, from `startChild` of `delegate_start`, ADR 0033) is a session of its own agent in its parent's folder, with its options lowered to the parent's level.
  Its row is inserted first (no `await` between the check and the insert), so it holds one of the parent's four slots and its `delegationRequestId` (never in a summary) while it opens, and goes if the open fails. The list leaves children out; a parent's summary lists them as `children`.
  `refuseChild` refuses `send`, `resume`, `archive`, `delete`, `rename`, `setOption` and a switch on a child; `interrupt`, `close`, `answer` and `events` work as on any session. It opens with `child: true` (approvals offer Allow and Deny only) and its MCP token never gets `act`.
  `switchAgent` (ADR 0032) moves an idle session to another agent: a new conversation opens with the handoff as its `instructions`, and the old one is closed only after the new one opened with the chat MCP, so any refusal leaves the session as it was.
  The session is in `switching`, a marker of its own that every request and a second switch check; the old conversation is detached. The notice has `switched: { from, to }`, and every later open or resume passes the handoff again, built from the events before it.
- `session-data.ts` and `pull-requests.ts`: the `diff` and `pr` of a `list` row, read in a background sweep, never in the request ([spec](../../docs/specs/chat-host.md)).
- `plan.ts`: the plan's request schema and step types.
- `shell.ts`: the port through which a project's actions run (`realShell`, its own process group so an abort stops what the command started); `FakeShell` in `fake.ts`, and no test runs a real command.
- `runner.ts`: the chat runner port, with `fake.ts` its test double; `claude.ts` and `codex.ts` are the Claude and Codex adapters.
  Codex's usage limit (`usageLimitExceeded`, not retried) is an `error` with `reason: 'usage_limit'`, emitted before the turn's `turn_end`; `resetsAt` comes from `account/rateLimits/read`, else `resetText`.
- `folder.ts`: the check of a session's folder (never inside `<folder>/engine/`), `checkProjectsFolder` and `checkProjectFolder` (shared table: `macos/Tests/Fixtures/project-folder.json`).
- `projects.ts`: what the chat brings onto the Mac with the person's own `gh` login, under the projects folder (ADR 0015).
  `cloneRepo` (waiters share one clone, which stops when nobody waits; only git's progress lines pass on, one a second), `createProject`, `githubRepos` and `repoBranches`.
  A preparation that cloned or made its workspace registers the folder in `projects.json` once it has succeeded (`register` in `sessions.ts`): origin `created`, `cloned` or `added` (only fetched); a failed or cancelled one writes nothing, and a folder the person chose is never registered.
  The `projects` capability: `cloneProject` clones from Settings in the background into `<parent or the projects folder>/<owner>/<name>` and answers at once (registered when git ends, never in the engine's repos); `newProject` makes `<parent or the projects folder>/local/<name>` with `git init -b main`, origin `created`, and refuses before making anything a taken name, a parent inside Carrier's own folders or a `projects.json` that does not match.
  `projectClones` lists clones running and failed (kept until `dismissClone`); a running clone holds the host's idle exit and a stop aborts it and removes what it made.
  `projectWorktrees` (in `sessions.ts`, since it joins `chat.db`) answers a project's main clone and its `worktrees/` still on disk with branch, session, age and a state (session open, uncommitted, PR merged, commits no other branch holds, else clean, in that order); the main clone says `uncommitted`, `notPushed` or `clean`, which the app reads before it moves a project to the Trash.
  `removeProjectWorktree` takes only the folder of one of those worktrees (`clearWorktree`: the branch stays, the next resume brings it back through `restoreWorktree`), refused while its session is open or switching or it has uncommitted changes; `cleanProjectWorktrees` lists, and with `run` removes, those whose `prState` is `merged` and nothing blocks.
- `disk.ts`: what a project takes on disk, behind the `projects` capability.
  `projectDisk` answers at once what `project_sizes` of `chat.db` holds (a project's main clone and its `worktrees/` together; nulls if never measured) and `measuring`. `refresh: 'stale'` queues those never measured or a day old, `now` all; the measure (`du -sk`, `measureWithDu`, faked in tests) runs in the background, a failure is logged and leaves the last figure.
- `providers.ts`: the `providers` request (accounts with their state, `unadded`, local servers, or `problem`; built from `doctor/detect.ts`).
- `mcp.ts`: the chat MCP (ADR 0024), a loopback HTTP server the host starts before `chat.sock`; toolkits under `mcp/`.
  `McpSessionRegistry`: a hashed bearer token per live conversation, revoked by `invocationId` when `sessions.ts` closes, loses or fails it.
  `defineTool`: every tool declares its access level and is listed and callable only for a token with the capability that level needs (`delegate_start`, `mcp/delegate.ts`, needs `act`); a `delegation` tool is also listed only while `sessions.delegationRefusal` (`levels.ts`) finds none, checked again on the call.
  Every tool is handed to the adapters by name (`tools` of `ChatRunner.open`) and runs unasked (Claude: `allowedTools`, and `canUseTool` allows them in `plan`). `delegate_wait` waits through `waitChildren`; `history` also reads a child or the parent (`related`).
- `handoff.ts`: `buildHandoff`, the pure builder of a switched session's handoff, 16,000 bytes at most; it travels as `ChatRunner.open`'s `instructions`.
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
It also answers `usage` and `usageOverride` through [`src/usage`](../usage/AGENTS.md).
`terminal/cli/commands/usage.ts` is `carrier usage`, which checks the hello lists `usage` and waits 45 s for it.
