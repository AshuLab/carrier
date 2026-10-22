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

**Reviewer** - Agent with an identity different from the author's that reviews the final PR in a separate checkout, publishes findings and verifies the fixes.
_Avoid_: external reviewer, review bot.

**Shared root** - Folder (by default `~/.solve/`) where Solve and Carrier keep `repos/`, `worktrees/` and `orchestrator/`. It is independent of where the app's code lives or from where it is started.
_Avoid_: workspace (it is an epic's checkout, inside `worktrees/`).

**Control socket** - Local channel (a Unix socket in `orchestrator/`) a running Carrier opens so another process can watch it and drive it: the snapshot and the agent's output come out, and pause, check now and stop go in. The macOS app is a client of it. See [0005](adr/0005-engine-independent-of-the-macos-app.md).
_Avoid_: API, daemon, IPC.

**Slice progress** - How many of an epic's slices (its sub-issues) are closed out of the total, read from GitHub on every poll. The list behind the count is kept in SQLite as a cache of GitHub, never as authority ([0008](adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); the agent running `ship` works the slices inside its own session.
_Avoid_: ticket progress, issue status.

**Review thread** - A conversation on a line of a pull request's diff, with who opened it, the file and line, whether it is resolved and a link to it on GitHub. The app lists the final pull request's threads in the Review tab, from a cache of GitHub like the slices ([0008](adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); a reviewer agent's blocker is a thread too.
_Avoid_: comment (a thread holds several), blocker (what the reviewer agent reports in its result).

**Session** - The conversation an agent holds in its harness, identified by an id the harness can resume (`claude --resume`, `codex resume`, `agy --conversation`). Each execution has one; the app shows an execution's work as one session block and Continue in Terminal resumes it ([0007](adr/0007-continue-in-terminal-through-a-validated-descriptor.md)).
_Avoid_: execution (the invocation with its time limit and result), thread, chat.

**Lane** - One of the up to three parallel workers inside a `ship` execution, each a Claude subagent building one slice in its own worktree. Solve decides the lanes; the engine does not know them, and a lane has no session of its own, so it cannot be resumed apart from the ship session.
_Avoid_: slot (that counts epics), thread, worker.

**Slot** - One of the places the engine has for running epics at once (`maxConcurrentEpics`). It is a counter with no identity, so the app shows how many are in use and which epics occupy them, never "slot 2".
_Avoid_: lane (that is inside one epic), thread, concurrency.

**Blocker** - A finding of a review that stops its approval. It has a title and, when the reviewer provides them, a stable id and a mark when a later round resolves it; the app shows each round's blockers and which carry over.
_Avoid_: issue, comment, error.

**Your turn** - The Overview's list of what needs the person: epics in human intervention, finished epics waiting to be tested, and engine problems, each with its action. It is not a status list; the sidebar already says which epics exist.
_Avoid_: inbox, notifications, to-do.

**Running epic card** - The Overview's card for an epic that is running: its progress and one row for each agent working on it. A dashed card after the running ones stands for free room and names the next queued epic.
_Avoid_: slot tile, agent list.

**Sidebar group** - A section of the app's sidebar that collects epics by state (Needs you, Running, Up next, Ready for test) or, when asked, by repository.
_Avoid_: category, folder.
