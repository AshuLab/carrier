# Carrier glossary

**Carrier** - Application that discovers ready epics and coordinates implementation, review and fix agents until the final PR is ready for test or it reports that human intervention is needed. Agent Forge manages the identities and their authentication; Solve provides the skills. The name is inspired by the StarCraft ship that deploys multiple interceptors.

**Ready for test** - The final PR has a conclusive review with no blockers and repo checks confirmed by the agents on the same commit. In a repo without CI, the review and the test evidence reported by the skills are enough, and that absence is recorded. Diego still has to test it and decide the merge.
_Avoid_: approved for merge, delivered, epic finished.

**Execution retry** - A new execution after a technical failure of the process or infrastructure, once its effects have been checked. It is not a code fix or a new review. The agent timeout has its own human-intervention outcome and is not retried automatically.
_Avoid_: retry without specifying what failed.

**Test/CI fix** - Internal work by the author and its skills to resolve failed checks before reporting the state of its execution. The orchestrator does not count these attempts or add a loop to manage them.
_Avoid_: execution retry, orchestrator fix counter.

**Caller agent** - Agent that invokes the skills, interprets their current reports and applies the repo's rules to work as author or reviewer. It hands the orchestrator one structured conclusion per execution.
_Avoid_: skill, orchestrator when referring to the agent that interprets the reports.

**Harness** - The agent CLI that runs the loop and the tools of an execution (Claude Code, Codex, Antigravity). Carrier launches it as a child process, as the user's normal CLI. It is the `harness` of an agent in the config.
_Avoid_: provider, agent (the author and the reviewer are agents; the harness is what runs them), runner.

**Model provider** - Who serves the model the harness uses: the harness's own cloud (Anthropic for Claude Code, OpenAI for Codex) or a local server (LM Studio, Ollama). It is the optional `provider` of an agent; without it, the harness's own cloud.
_Avoid_: harness, local model (a local model is a model whose provider is a local server).

**GitHub profile** - User-configured reference to an available GitHub identity and its authentication mechanism. It is assigned to the orchestrator, author or reviewer; it is independent of the AI harness/model and of an agent's working session.
_Avoid_: model, agent session, AI identity for a GitHub account.

**Epic** - `solve:epic` issue with a spec and prepared tickets; the unit that Carrier queues, executes and delivers. It is identified by repo and issue, because different repos reuse numbers.
_Avoid_: feature, task, job.

**Stage** - Segment of an epic in charge of one role: implementation with `ship`, review or fix. The orchestrator combines the stage with the caller result to decide the next turn.
_Avoid_: step, phase, epic state.

**Review round** - Each review of the final PR by the reviewer, numbered; the limit of five counts these reviews. A technical execution failure does not consume a round.
_Avoid_: retry, iteration.

**Execution** - One invocation of an agent (author or reviewer) with its session, time limit and result. It is the unit of the technical retry and of the timeout; it does not represent the duration of the epic.
_Avoid_: process (technical termination is something else), epic.

**Caller result** - Structured conclusion of an execution, in JSON: `completed`, `changes_requested` or `needs_human`. It is independent of whether the process ended well or badly.
_Avoid_: process success/failure, CLI state.

**Human intervention** - State of an epic that is stopped (`solve:epic:needs-human`) by `needs_human`, timeout, exhausted limit, inconclusive review or authentication error. Diego resolves it outside Carrier; Carrier takes it back only when he puts `solve:epic:ready` on the issue again.
_Avoid_: error, failure, pause.

**Author** - Agent that invokes `ship` and handles the findings; it keeps its identity throughout the epic.
_Avoid_: implementer, developer.

**Reviewer** - Agent that reviews the final PR in a separate checkout, publishes findings and verifies the fixes. Its GitHub profile differs from the author's, unless the user chose a shared identity.
_Avoid_: external reviewer, review bot.

**Shared root** - Folder (by default `~/.solve/`) where Solve and Carrier keep `repos/`, `worktrees/` and `orchestrator/`. It is independent of where the app's code lives or from where it is started.
_Avoid_: workspace (it is an epic's checkout, inside `worktrees/`).

**Control socket** - Local channel (a Unix socket in `orchestrator/`) a running Carrier opens so another process can watch it and drive it: the snapshot and the agent's output come out, and pause, check now and stop go in. The macOS app is a client of it. See [0005](adr/0005-engine-independent-of-the-macos-app.md).
_Avoid_: API, daemon, IPC.

**Slice progress** - How many of an epic's slices (its sub-issues) are closed out of the total, read from GitHub on every poll, when the agent runs a command that changes the slices, and once a minute for live epics. The list behind the count is kept in SQLite as a cache of GitHub, never as authority ([0008](adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); the agent running `ship` works the slices inside its own session.
_Avoid_: ticket progress, issue status.

**Review thread** - A conversation on a line of a pull request's diff, with who opened it, the file and line, whether it is resolved and a link to it on GitHub. The app lists the final pull request's threads in the Review tab, from a cache of GitHub like the slices ([0008](adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); a reviewer agent's blocker is a thread too.
_Avoid_: comment (a thread holds several), blocker (what the reviewer agent reports in its result).

**Session** - The conversation an agent holds in its harness, identified by an id the harness can resume (`claude --resume`, `codex resume`, `agy --conversation`). Each execution has one; the app shows an execution's work as one session block and Continue in Terminal resumes it ([0007](adr/0007-continue-in-terminal-through-a-validated-descriptor.md)).
_Avoid_: execution (the invocation with its time limit and result), thread, chat.

**Chat host** - The process that holds user sessions: it starts when a person opens the first chat and ends when no session is running and no client is attached. It has its own lock and control socket, shares code with the engine but not its state, and the engine's stop does not touch it ([0013](adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)).
_Avoid_: chat server, session manager, engine (the engine runs epics).

**Chat runner** - The port through which the chat host drives one provider's agent: open or resume a conversation in a folder, send a message, answer an approval, interrupt, set an option, close. One adapter per provider implements it (Claude, Codex) and a fake stands in for tests. It is not the `AgentRunner`, which runs one unattended execution to a result.
_Avoid_: provider client, driver.

**Chat event** - What a chat runner reports about a conversation in Carrier's own shape, whatever the provider speaks: a message from the person or the agent, a tool call and its outcome, an approval asked, an option changed, the usage of a turn, the end of a turn. The host stores them as the transcript of a user session, bounded and redacted.
_Avoid_: agent event (the epic executions' events), message, log line.

**Lane** - One of the up to three parallel worktrees inside a `ship` execution (`<epic worktree>--lane-N`). A lane is a place, not a worker: it is reused, so lane 1 builds one slice and then another, and the subagent that builds a slice runs in a lane. Solve decides the lanes; the engine does not know them, and a lane has no session of its own, so it cannot be resumed apart from the ship session.
_Avoid_: slot (that counts epics), thread, worker, subagent (a lane holds one at a time).

**Subagent** - A Claude agent launched from inside an execution, with an exact `agentId` in the stream and no session of its own. A builder subagent builds one slice, in a lane. A reviewer subagent runs one pass of a review (Spec, Standards, Risk, Experience) and has no slice and no lane. The slice and the lane of a builder are inferred from the model's wording and the worktree path; the subagent, its times and its end status are exact ([research](research/claude-subagent-attribution.md)).
_Avoid_: lane (that is where a builder runs), worker, child agent.

**Call group** - A run of two or more successful tool calls with nothing between them but other calls of the same kind of work (commands, reads, searches), shown in the Agent output tab as one row such as "Ran 4 commands · read 2 files" that unfolds to the calls. A failed call, a message, a skill, an edit or a slice ends the run; a lone call is not a group.
_Avoid_: batch (that is slices started together), step, turn.

**Slice row** - The row of the Agent output tab that stands for one subagent building one slice: its state, its slice and title, its counts and pull request, placed in the log where the slice was taken and opening in place on the subagent's own calls. One row per subagent; a resumed one is still one row.
_Avoid_: lane (the place it runs in), lane card, task.

**Slot** - One of the places the engine has for running epics at once (`maxConcurrentEpics`). It is a counter with no identity, so the app shows how many are in use and which epics occupy them, never "slot 2".
_Avoid_: lane (that is inside one epic), thread, concurrency.

**Blocker** - A finding of a review that stops its approval. It has a title and, when the reviewer provides them, a stable id and a mark when a later round resolves it; the app shows each round's blockers and which carry over.
_Avoid_: issue, comment, error.

**Observation** - A finding of a review that does not stop its approval: a nitpick or a suggestion. The reviewer lists observations in a `completed` result, with a title and a stable id like a blocker; when there are any, the author answers them in one resolve pass before the epic is ready for test ([0009](adr/0009-observations-trigger-one-resolve-pass-before-ready-for-test.md)).
_Avoid_: nitpick (one kind of observation), comment, blocker (the one that stops approval).

**Your turn** - The Carrier home's list of what needs the person: epics in human intervention, finished epics waiting to be tested, and engine problems, each with its action. It is not a status list; the sidebar already says which epics exist.
_Avoid_: inbox, notifications, to-do.

**Running epic card** - The Carrier home's card for an epic that is running: its progress and one row for each agent working on it. A dashed card after the running ones stands for free room and names the next queued epic.
_Avoid_: slot tile, agent list.

**Sidebar group** - A section of the Carrier section's list in the app's sidebar that collects epics by state (Needs you, Running, Up next, Ready for test, Done, Cancelled) or, when asked, by repository. Every group collapses; Done and Cancelled start collapsed.
_Avoid_: category, folder.

**Home** - The app's first page: a welcome with no status. The app opens on it and the sidebar's Home row selects it. Status lives elsewhere: the engine's on the Carrier card, a user session's on its own row.
_Avoid_: overview, dashboard, start page.

**Carrier home** - The page of the Carrier world, opened by selecting the Carrier section: what the Overview was (Your turn, the running epic cards, up next, the watched repositories) and the engine's controls (Check now, Pause, Stop). The Sessions world has its own, the Sessions home.
_Avoid_: Overview (its old name), dashboard.

**Sessions home** - The page of the Sessions world, opened by selecting the Sessions row. An empty state ("No sessions yet") until user sessions exist. The Carrier world has its own, the Carrier home.

**Archive page** - The page opened by the sidebar's Archive row, which stands on its own outside Sessions and shows the count of archived user sessions. An empty state until user sessions can be archived.

**Carrier section** - The sidebar section for the automation, drawn like every other: an icon, the title Carrier, the engine's state (Running, Paused, Stopped or Problem, or Connecting in grey while it has not answered yet), the search and group-by actions, and its slots as bars at full width, grey while nothing runs. It shows no counters: the groups under it carry their own counts. Selected, it unfolds into the sidebar groups and the Carrier home shows in the centre. Only one of the Sessions, Carrier and Archive sections is open at a time.
_Avoid_: Carrier card (its old name, when it was a filled card with counters), status bar, footer, pill (the pill is the engine's state inside the section).

**Sidebar section** - A destination of the sidebar that is drawn as an icon, a title and its actions, with no fill at rest and a light grey fill, never the system blue, only on that row when it is selected. Home, Sessions, Carrier, Archive and Settings are sidebar sections; Sessions, Carrier and Archive unfold a list under the row that has no fill of its own, a search field under the row, and an empty state when there is nothing to list or nothing matches.
_Avoid_: card, tab, panel.

**User session** - A conversation the person starts inside the app with the agent of their choice, in a workspace. It belongs to no epic ([0012](adr/0012-sessions-and-epics-are-two-separate-worlds.md)), is disposable once its job is done, and can be archived. It is a Session in the sense above, when that conversation is not an epic's execution.
_Avoid_: chat, thread.

**Workspace** - The folder a user session works in: a plain folder, a GitHub clone, or a repository already in Carrier's list. The sidebar groups sessions by workspace. It is never the shared clone an epic runs in nor an epic's worktree.
_Avoid_: project, epic checkout.

**Base folder** - The workspace's own folder, as opposed to a worktree made from it. A session that works in the base folder edits the person's own checkout, with whatever branch and uncommitted changes it has.
_Avoid_: main folder, original, source.

**Session worktree** - A git worktree that Carrier creates for a user session, on a new branch named `carrier/<adjective>-<unit>-<place>` and cut from a branch the person picks, so the base folder stays untouched. It lives under Carrier's home, its name is generated (the person may type another after the `carrier/` prefix) and it is removed with the session ([0014](adr/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)). It is not an epic's worktree and not a lane.
_Avoid_: workspace copy, sandbox, checkout, epic worktree.

**Done** - The group of epics whose final PR was merged, shown for the finished window after the merge. Not Ready for test: nothing is waiting for a person any more. In the terminal panel it is a section of the same name.
_Avoid_: finished (the window and the snapshot field use it, the group does not), closed, completed.

**Cancelled** - The group of epics that ended without a merge (the final PR or the epic issue was closed), with the reason Carrier stored, shown for the finished window. Apart from Done so a fallen epic is never read as a delivered one.
_Avoid_: failed, aborted.

**Finished window** - How many days after an epic ends it stays listed under Done or Cancelled (`finishedWindowDays`, 15 by default, at most 30 because the retention purge deletes logs and sessions at 30). Counted from when the epic left `running`. After it the epic is only reachable by its issue and PR on GitHub; its row stays in SQLite.

**Detached run** - Carrier started with `carrier start`: its own session, no terminal, its output in a log under `orchestrator/logs/`, reached through its control socket (`carrier status`, `watch`, `stop`, or the macOS app). Nothing starts it but a person; it is not a login service and nothing restarts it if it dies.
_Avoid_: daemon, service (a launchd service is the alternative that was not chosen), background process.

**Attention colours** - The two colours the macOS app uses for an epic that cannot go on alone: orange when a person's input is needed (the review limit was reached, the agent asks for help), red when something failed (retries exhausted, a timeout, failed authentication, a workspace problem, an invalid pull request). A kind the app does not know is orange, because a person has to act either way. Cancelled is neither: nothing is asked and nothing failed, so it is grey. Both colours still sit under the same "Needs you" group; only the colour tells which of the two it is.
_Avoid_: warning colour, error orange, problem state.

**Resume (an epic)** - Putting an epic that stopped in needs-human back in the queue once a person has dealt with the cause. It does what the person did by hand before: `solve:epic:ready` goes back on the issue, the `needs-human` mirror comes off, and the epic starts again from ship, reusing its worktree and its pull request, with the review rounds starting over. Nothing checks that the cause is really fixed: if it is not, the epic stops again with the new error. The macOS app asks the engine to do it, with a confirmation first; in a terminal it is `carrier restart`, which can also change the option of each role.
_Avoid_: retry (an execution retry is the automatic one after a technical failure), continue (continue in terminal is about a session).

**Separate identities** - Setup where the author and the reviewer use different GitHub profiles: two Agent Forge bots, or one bot and the user's `gh` login. It is the default, and what makes the reviewer's comments not the author's own.
_Avoid_: dual identity, bot mode.

**Shared identity** - Setup where the author and the reviewer use the same GitHub profile, normally the user's own `gh` login, so everything the agents publish goes out under that account. It exists for the user who cannot install a GitHub App on the repos they work in. Each role signs what it publishes, and the agents act with everything that login can do.
_Avoid_: single login, same-account mode, bot-less mode.

**Persona** - What a role (author or reviewer) is given besides its harness and model: a name the user chooses and an optional prompt that says who the agent is and how it behaves. Carrier adds it to the agent's prompt in either identity setup. It is not a GitHub profile: the profile says which account posts, the persona says who is speaking.
_Avoid_: identity (it is ambiguous with the GitHub profile), system prompt, bot name.

**Signature** - The closing line a role puts on everything it publishes under a shared identity: `🤖 <Role> [NAME] via Carrier`, with the persona's name in the brackets. It is mandatory, the user cannot turn it off, and it is what tells the agent's words from the user's own when both come from one account.
_Avoid_: watermark, marker, footer.

**GitHub unavailable** - GitHub answered with a failure that clears by itself, so Carrier keeps its state and tries again on the next poll. It has a kind, which only diagnoses: `rate_limited` (HTTP 429, or 403 with a rate limit), `server_error` (5xx), `timeout` and `network`. The kind and its detail are in the error's message, so the log and the last check of a repo say why. An authentication error and any other HTTP failure are not GitHub unavailable.
_Avoid_: GitHub down, GitHub refused (that is the panel's section for the repos whose last check failed), the control socket's `github unavailable` reply (a different, fixed string).

**Failure kind** - Why an agent execution ended badly, one value from a closed list kept on the execution beside its status: `usage_limit`, `api_error`, `killed` (a signal from outside Carrier ended the process), `crashed` (a nonzero exit), `spawn_error`, `auth`, `session_lost`, `timeout`, `invalid_result` and `unknown`. It mostly diagnoses: only `usage_limit` changes anything, because it stops the epic at once in needs-human, naming the option that ran out, and spends no retry (like `timeout`, it does not count in the failure streak). It stays on the execution, so the history says why long after the epic's last error was cleared. An execution that ended `ok`, or that Carrier itself stopped, has none.
_Avoid_: error type, exit reason, technical failure kind (a technical failure is what an execution retry answers; the kind says which one it was), GitHub unavailable's kind (a different list, for GitHub calls).

**Agent option** - A named way to run an agent, declared once in the config: a harness, the harness's config folder (`CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex) when it has one, and a model. An epic runs each of its two roles, author and reviewer, on one option, so two Claude logins, Codex and Antigravity are four interchangeable options. The harness's login lives in its config folder, so the folder is what picks the account.
_Avoid_: account (an option is more than the login), provider (that is the model provider), profile (that is the GitHub profile), agent (the author and the reviewer are agents; an option is what one of them runs on).

**Failover** - Carrier moving a role of a running epic from the agent option that ran out of credits to the next one in the config's `failover.order`, with no person involved. It is off until the config turns it on, it only ever moves to an option listed in `order`, and it is remembered for that epic only. Each switch is an epic event that says from which option to which, and why.
_Avoid_: fallback, automatic retry (an execution retry repeats the same option; a failover changes it).
