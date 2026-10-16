# Carrier — Autonomous epic orchestrator

The application is called **Carrier**, inspired by the StarCraft ship that deploys multiple interceptors. Carrier coordinates agents in parallel; Agent Forge provides their identities and Solve provides the skills flow.

Status: requirements draft. It records decisions from the conversation and pending proposals; it does not describe an implemented system.

The `solve:sharpen` brief is at [docs/specs/autonomous-orchestrator.md](specs/autonomous-orchestrator.md). This document keeps the detail of the conversation; the brief synthesizes the problem, direction, scope and pending validations.

## Goal

Diego prepares ideas with `sharpen`, generates specs and tickets, and enables epics for execution. A local process picks up those epics, runs `ship`, and coordinates review and fixes of the final PR until it is ready for test or asks for intervention.

The process lets him keep preparing new features while the agents work. Diego tests and merges the final PR.

## Agreed decisions

- Build our own orchestrator and runner in TypeScript on Node.js.
- Initial runtime: Node.js 26, with ESM modules. Use pnpm as the package manager. Adopt TypeScript, pnpm and every runtime/development dependency at the latest stable version available at the time of implementing or updating; exclude prereleases.
- It is a standalone app, with its own repository separate from SecondBrain. The first interface is a command with a terminal panel; execution storage stays under the configurable shared root `~/.solve/`.
- Initial supported and validated platform: macOS. TypeScript/Node.js keeps the core portable; Linux/Windows support is left for later, after validating dependencies, processes, credentials and paths on those platforms.
- Run the process from any folder. Explicitly configure the GitHub repos where it looks for epics; the current directory does not determine which repos it queries.
- On restart, do not resume work from repos that are no longer in the configuration. Keep their epics, sessions, workspaces and history and show the reason; do not delete information or consume retries because of that exclusion.
- Use a storage root shared between Solve and the orchestrator for clones and worktrees, with a configurable location. The orchestrator adds its database, sessions and logs there. Solve manages the worktrees and implementation branches; both reuse the same code paths to resume.
- Default shared root: `~/.solve/`, configurable. Agreed layout: `repos/` for clones, `worktrees/` for Solve workspaces and `orchestrator/` for SQLite, sessions and logs.
- Start with a terminal command and a panel that shows progress in that same terminal.
- The initial panel is simple and informational, with no controls to pause, retry or manage executions. Validate the flow first; improve the interface in later versions.
- Use SQLite for state and separate files for logs.
- Use Drizzle ORM with `better-sqlite3` for the schema and SQLite access, and Drizzle Kit to generate migrations. Pick the latest stable versions compatible with Node 26.
- Use the `@ashulab/universal-logger` package as a runtime dependency of the app for logging information, warnings and errors. Import and configure its API; do not copy its implementation or create a custom logger or format in its place.
- Use `solve:epic:ready` as the queue entry label.
- Solve adds that label automatically when it finishes all the preparation stages. The change is made in the Solve skills, outside this orchestrator.
- `solve:epic:ready` is a sufficient signal to pick up an epic: the orchestrator registers it directly in the queue, with no additional query to Solve to enable it.
- When an epic's execution starts, remove `solve:epic:ready` and add `solve:epic:running` on GitHub. Keep the execution in SQLite so it can be resumed without depending on the issue still being ready.
- When it is ready for test, replace `solve:epic:running` with `solve:epic:ready-for-test`. If it requires intervention, replace it with `solve:epic:needs-human`. Also record the result in SQLite.
- Agents do not run with the host system's permissions: each execution runs in a container with broad permissions inside and only the epic's workspace mounted. The token's minimum scopes and the repos' branch protection are the second boundary. See [ADR 0003](adr/0003-agents-in-containers.md).
- Run independent epics in parallel, with a configurable maximum concurrency as a positive integer. Initial value: three epics; it can be one, two, four, eight or another value depending on the configuration.
- Take ready epics in queue arrival order (FIFO), preserving the order of entry on restart.
- Dependencies between epics are out of scope for the first version and will be resolved in Solve separately. The rule discussed for a future evolution is to wait for the prerequisites to be merged; the MVP does not implement a graph, a waiting-on-dependencies state or unblocking on merge.
- Review the epic's final integration PR, as `ship` produces it.
- If it is detected that an epic's final integration PR was merged while there is still active work, stop its agents and new turns, keep sessions/logs and record the reason. This does not apply to the slice merges that `ship` performs as part of the implementation.
- Alternate author and reviewer with distinct GitHub identities, using Agent Forge to prepare identities and credentials.
- Agent Forge is an installed external dependency. The runner uses it to prepare the GitHub identity and credentials of each execution; it does not bundle a copy of Forge inside the project.
- Support a catalog of `n` GitHub identities, including Diego's, instead of limiting it to two fixed bots. Identities and sessions are distinct: the same identity can take part in several epics with isolated sessions.
- The user configures the available GitHub profiles and explicitly chooses which one the orchestrator itself uses to query issues and update labels. It may reuse an agent profile or assign another; it is not automatically assumed to be the author.
- Explicitly assign the author and reviewer identities through configuration; do not select them automatically from a pool.
- Allow choosing provider and model per role. Separate GitHub identity from provider/model.
- Define global values for identity, provider and model per role, with per-repo overrides. Each repo inherits the global values and replaces only those it explicitly configures.
- When an epic starts, save its effective agent configuration. Changing defaults or overrides affects new epics; those already in progress keep their identities and models, including when resuming sessions.
- The configuration file uses JSON for repos, identities, models, overrides and limits. Validate on startup and show clear errors for missing fields or invalid values.
- Use `zod` as a runtime dependency for the schemas and validation of configuration and caller results. Infer the TypeScript types from the schemas to keep both contracts aligned.
- Use Vitest as a development dependency for the app's tests. Test queue, transitions, persistence and recovery with simulated agents; tests with real Claude/Codex remain separate integration tests.
- Ship a default configuration with the app and allow a user JSON file that overrides it. Objects merge field by field; the user's simple values replace the defaults; lists are replaced whole, never concatenated. Validate the resulting configuration.
- Initial providers: Claude and Codex.
- Maximum of five reviews per epic, configurable; stop the loop earlier when no blockers remain and the checks are met.
- In repos without CI, a conclusive review with no blockers and test evidence reported by the skills is enough to become ready for test. Record that evidence and the absence of CI. If there are required checks, they must be green on the reviewed commit.
- Three retries for execution failures, configurable, separate from review rounds.
- Fixing and re-running tests/CI is internal work of the agents and skills. The orchestrator receives their final result and does not count those attempts nor add a specific loop to fix tests.
- Initial maximum time per agent execution: four hours, configurable. Support an explicit no-limit option (`unlimited`); zero is not interpreted as infinite. The limit does not include the time an epic spends in the queue nor does it represent a maximum duration for the whole loop.
- When the time limit expires, stop the execution, keep the session and workspace, and mark the epic as requiring intervention. The timeout does not trigger an automatic retry.
- If the reviewer cannot conclude for lack of context, the epic requires intervention. Record the reason; the absence of blockers detected in an incomplete review does not enable the PR.
- Epics that require intervention are resolved manually by Diego. The first version records and shows the reason, with no command or controls to reactivate them. This is distinct from automatically resuming executions interrupted by `Ctrl+C`.
- Skills keep their current outputs. The caller agent interprets them the way a person invoking the skill would.
- The orchestrator coordinates without interpreting the repo's domain. Author and reviewer apply the repo/Solve rules, choose and evaluate tests/checks and determine blockers. The orchestrator validates the JSON contract and its technical coherence, persists results and manages stages, limits and labels. See [ADR 0001](adr/0001-separate-coordination-from-repo-evaluation.md).
- The caller writes its conclusion per execution to a structured JSON file. The orchestrator validates its schema and stores the information in SQLite, associated with the epic, stage and execution, keeping the history.
- The caller's JSON has three results: `completed`, `changes_requested` and `needs_human`. The engine combines the result with the stage to coordinate the next turn.
- Keep agent sessions per epic and role to resume from the context of an interrupted stage, in addition to continuing the pending stages. Record provider, identifier and location of the session where applicable, and keep the workspace.
- If a saved session cannot be recovered, start a new one with the persisted context and the current state of the workspace/GitHub. The agent verifies what was done before continuing; it keeps the identity and records the recovery in the history.
- `Ctrl+C` stops the orchestrator and the executions active at that moment, without waiting for their stages to finish. Keep sessions, workspaces and persisted state to resume on restart.
- Diego will adapt the skills so that authorized stages can run without waiting for approval.
- SQLite is the authority for the state of each execution; the `solve:epic:*` labels are its mirror and are reconciled. See [ADR 0002](adr/0002-sqlite-authority-labels-mirror.md).
- A web UI or OS app is left for a later evolution.

## Walkthrough of an epic

### Working repos and startup

The process runs from any folder and stays active. The configuration includes an explicit list of GitHub repos in which to look for issues; each entry identifies the repo by organization/user and name. The process queries the repos in that list and looks for the `solve:epic:ready` label.

Only one active instance is allowed per orchestrator data folder. Before starting queries or agents, the process acquires an exclusive lock on that folder. If another instance holds it, it shows that the orchestrator is already running and exits without starting work. An unexpected shutdown must not prevent the next startup: the mechanism must distinguish an active lock from a stale one and prevent two simultaneous startups from acquiring the same folder.

Each epic's code runs in its own workspace, separate from the directory where the process was started. Solve and the orchestrator share a configurable root for clones and worktrees. The orchestrator also stores its sessions, database and logs there. The caller invokes `ship` with per-epic isolation; Solve creates or reuses its worktree, manages its branches and records the final PR. The repo's shared clone is not a directory where several authors implement in parallel.

The integration uses the same location and worktree convention as Solve, through its configuration/invocation mechanism. The orchestrator records the real path and reuses it on resume; it does not create a second parallel structure of implementation worktrees nor delete the ones Solve manages. The reviewer's separate checkout is kept under the shared root.

The default shared root is `~/.solve/`, configurable. The agreed layout is `repos/` for clones, `worktrees/` for Solve workspaces and `orchestrator/` for SQLite, sessions and logs. Repo directories must distinguish organization/user and name to avoid collisions. Pending: how to communicate this configuration to Solve and check its compatibility; it is the agreed design, not a claim that all these directories already exist in Solve.

### 1. Prepare and enable

Diego prepares the idea, spec and tickets with Solve. When all the preparation stages are completed, Solve adds `solve:epic:ready` automatically. The epic must contain what `ship` needs to work; an idea still without a spec or tickets is not ready. Adding the label is implemented in the Solve skills, outside this project.

The label means an agent can pick up the epic directly. For a new epic, the orchestrator checks that the issue is still open and ready when reserving it and that there is no registered execution that must be resumed or respected. Existing executions are recovered from SQLite and do not require adding ready again. Managing dependencies between epics is a separate change in Solve.

### 2. Discover and enqueue

The process queries all the configured repos and discovers open issues with the entry label. It must go through all the results, even if there are many epics, and recognize those already registered. An epic's identity includes repo and issue, since different repos can have the same issue number.

Periodic GitHub queries use a fixed interval of 5 minutes by default, configurable in JSON. The first query also waits for that interval from startup. Webhooks, a public URL and adaptive intervals are not used. This interval does not add waits between author and reviewer turns: the loop advances on receiving each agent's result.

If GitHub is unavailable or rate-limits queries, keep the queue and persisted state, show the error and query again at the next configured interval. If GitHub indicates a longer wait, respect it. These query failures do not consume execution retries of the agents nor turn a failed query into an empty list of epics. Authentication errors are handled through the Forge integration as defined for profiles.

New ready epics are saved directly in SQLite as queued. The label is the availability contract for this version; no other skill is queried nor are dependencies between epics resolved before enqueuing them. The orchestrator manages reservations and concurrency over that queue.

The selection order is FIFO among ready epics, according to their entry into the persisted queue. Epics that require intervention stay stopped without preventing others from advancing. The representation and resolution of future dependencies belong to Solve.

### 3. Reserve and run ship

When a slot is available, the scheduler reserves an epic through an atomic operation in SQLite. An epic cannot have two active executions.

When its execution starts, remove `solve:epic:ready` and add `solve:epic:running` on GitHub so it is visible that the epic has already been taken. Persist the start and reconcile the GitHub state on resume; the label change does not replace the execution record in SQLite.

It prepares an isolated workspace and launches the author with the identity, provider, model, skill and context of that epic. `ship` keeps control of its slices, branches and final PR; the orchestrator coordinates the execution and records the result.

The caller reads `ship`'s current report, identifies the final PR and communicates the result to the orchestrator. Before advancing, the orchestrator checks that it exists and corresponds to the epic. If `ship` needs a decision or cannot complete the work, the reason is recorded and intervention is requested.

### 4. The agent verifies the code

The author applies the repo and Solve rules to determine which tests and checks apply to the PR. It runs or queries those verifications, interprets their results and waits for pending checks when appropriate. It resolves failures as part of its work with the skills and, when it finishes, reports what it completed and in what state it was left. If it cannot finish, it reports the reason and the need for intervention. The reviewer then verifies the evidence. The orchestrator consumes the conclusions of each execution, without defining which checks are mandatory, reinterpreting their results or managing the agent's internal attempts.

If the repo has no CI, the caller collects the test evidence reported by the skills and records that the verification did not include CI. That evidence, together with the conclusive review with no blockers, is enough to become ready for test; it is not required to add GitHub Actions or an external check to use the orchestrator.

The orchestrator has no counter or limit of its own for test/CI fixes. The three configurable retries remain for technical execution failures; the five reviews limit the author/reviewer exchange. Selecting, evaluating and fixing checks belongs to the agents and skills. This section describes agent work within its turn, not an additional CI control stage run by the engine.

### 5. Review and publish

Launches the reviewer with a different identity and a checkout separate from the author's. It receives spec, tickets, PR, SHA and context from previous rounds.

The reviewer invokes the review and publishing skills, interprets their current reports and communicates whether the review was conclusive with no blockers, had blockers or was left inconclusive.

The orchestrator records the reviewed SHA, findings, links to the comments and round number. A process that ends successfully is not enough to declare the code ready.

### 6. Fix or respond

If there are blockers and rounds remain, the process activates the author with the comments and evidence. The author evaluates each finding: fixes it or responds with verifiable reasons.

Responding or marking a thread as resolved is not the same as removing the blocker. The reviewer verifies the fix or accepts the response in the next pass. The author's identity is kept throughout the epic; its session can be resumed or rebuilt if it is not available.

The author verifies the new commit according to the repo rules and the reviewer reviews again, verifying evidence, pending findings and possible regressions. The orchestrator manages the change of turn and the limits.

### 7. End the loop

An epic becomes [ready for test](glossary.md) when the reviewer issued a conclusive result with no blockers and the agents confirmed the verifications required by the repo on the same commit. In a repo without CI, that review and the test evidence reported by the skills are enough, recording the absence of CI. The orchestrator consumes that conclusion, checks its technical coherence with the execution/PR/SHA and records the transition; it does not decide by itself whether the code or CI are correct. A later code change invalidates that result and requires new verification by the agents.

Agreed maximum: five reviews, configurable. If the fifth still has blockers, intervention is requested. No further fix is applied only to then declare ready a commit that was not reviewed. Execution errors do not consume a review round. If the reviewer cannot conclude for lack of context, the epic requires intervention and the reason is recorded; an incomplete review with no blockers detected does not enable the PR.

Three retries for execution failures, configurable. They are interpreted as up to three retries after the initial attempt. Before relaunching a stage, check its effects to avoid duplicating publications or work. A code finding or a disagreement is not an infrastructure failure that is resolved by repeating the same execution.

Disagreements about findings are worked out between author and reviewer within the review limit. Epics that require intervention stay stopped with the reason recorded so Diego can resolve them as a human, with no reactivation command in this version. Other epics can keep advancing. Restarting the process does not automatically reactivate these epics; it is different from resuming an execution interrupted by `Ctrl+C`.

The outcome is also visible on the GitHub issue: replace `solve:epic:running` with `solve:epic:ready-for-test` when the conditions for delivery to testing are met, or with `solve:epic:needs-human` when intervention is required. SQLite keeps the result, evidence and history; when recovering from a failure during the label update, reconcile both records.

### 8. Test and merge

Diego tests the PR and decides the merge. The orchestrator keeps looking for new ready issues in the configured repos; the first version does not include unblocking epics on merge.

While the epic has active work, check whether its final PR has already been merged. If that merge is detected, stop its executions and do not launch other turns for that epic; keep sessions, workspace and history and record that it was stopped by the final PR's merge. The other epics continue. Merges of slice PRs do not trigger this rule. Checking the PR's state is technical coordination, not code or CI evaluation.

If the epic's issue or its final PR is closed manually without merge, record the epic as cancelled, stop its agents and do not start new turns. Keep the work done and show the reason in the terminal; the other epics continue. Cancellation ends the orchestrator's work and starts the 30-day retention period for its logs and sessions. The rule does not apply to closures of slice tickets or PRs performed by `ship`.

For an evolution with dependencies, it was discussed that if A creates an API and B consumes it, B should wait for A's merge. That behavior will be designed separately in Solve.

## Communication and results

Agents do not need to stay alive waiting for messages between stages. The orchestrator receives a stage's result and launches the next one with persisted context. GitHub keeps code, PRs, reviews and responses; SQLite keeps the coordination state.

Skills keep their current reports. The caller receives the task, invokes the skill, reads the report and acts on it like a person: identifies the PR, understands blockers and responses, or detects that it needs help. Adapting them for invocation without approval remains Diego's responsibility.

The caller returns a brief conclusion with what it finished, PR/SHA where applicable, evidence, blockers or reason for intervention. The orchestrator validates the contract and stores the result in SQLite, associated with the epic, stage and execution; it keeps previous conclusions as history. The panel consumes those conclusions and the skill's full report stays in the logs. It may check references and SHA currency on GitHub to avoid coordinating over another commit; evaluating code, tests, CI and blockers is the author's/reviewer's job.

Agreed transport: the caller writes a structured JSON result file and the orchestrator validates its schema before importing it into SQLite. The database is the persistent record. Check required fields according to the stage, types, allowed values and correspondence with the expected epic/execution. Save the result and the state transition in one transaction to avoid advancing without persisted information; importing the same result must be idempotent. An invalid result does not allow advancing the stage. The exact fields are defined when designing the schema, keeping the skills' current outputs.

The result field (`outcome`) supports:

| Result | Meaning and transition |
| --- | --- |
| `completed` | The agent finished its turn successfully. If it was `ship` or an author fix, it enables a review; if it was a review, it means it concluded with no blockers and confirmed the repo's verifications, and it enables ready for test. |
| `changes_requested` | The reviewer concluded there are blockers and asks for fixes. If rounds remain, it enables the author; when the limit is exhausted, it requires intervention. Valid only for a review turn. |
| `needs_human` | The agent cannot continue and explains the reason. Stop new turns of the epic and record the intervention needed. |

The runner reports the process's technical termination separately. A CLI failure or a missing/invalid JSON is not turned into `completed`: what was done is reconciled and the technical retry policy is applied. The three outcomes are caller conclusions, not a catalog of infrastructure errors.

Provider adapters translate the task to the corresponding CLI, prepare credentials for that execution and capture output, logs and errors. One agent's credentials must not be mixed with those of another parallel execution. Their renewal during long jobs must be resolved.

Agent Forge is used as an installed external dependency, through a runner adapter. The orchestrator keeps the queue and the loop; the runner keeps launching tasks and sessions with Claude/Codex; Forge prepares GitHub identity and credentials. What remains is validating the concrete integration mechanism and pinning a compatible version.

The catalog supports multiple identities, including Diego's personal one. The configuration explicitly assigns one identity to the author and another to the reviewer. For the same PR, they must be different. Agent Forge is responsible for profile authentication; the app references those profiles and consumes the integration's errors. What remains is validating concrete support for personal profiles and bots.

The configuration also selects a GitHub profile for the orchestrator's operations: issue discovery, reference queries and label updates. The user declares the profiles they have available and references them from the configuration; they may choose the same one for different responsibilities when appropriate, except for the author/reviewer separation on the same PR. Configuring profiles does not imply adding a UI or wizard in this version: the JSON file contains the references and Agent Forge resolves authentication.

If Forge reports an authentication error, the epics that need the affected profile are stopped and the reason is shown in the terminal. The others can continue. If the affected profile is the orchestrator's, the GitHub operations that depend on it are suspended. The app does not implement its own authentication system nor switch profiles automatically.

## Persisted state

Save per epic: repo and issue, queue entry date, workspace, final PR, stage, round, identities, chosen configuration, reviewed SHA, pending blockers, executions, errors and event history. Do not store tokens in the state or in the logs.

Logs and sessions linked to an epic are deleted automatically 30 days after the epic ends. While it remains pending, including interrupted cases or those that require intervention, they are kept to allow resuming it. This cleanup does not delete the epic's record in SQLite nor its workspaces.

On restart, the process reconciles incomplete stages with the existing processes and with GitHub before retrying. It does not assume a stage failed just because it did not manage to record its result; it might have created a PR, comment or commit.

Before resuming, check that the repo is still in the current configuration. If it was removed, keep the execution, its queue order and effective configuration, but leave it stopped with the reason repo not configured. Keep sessions, workspace and history; do not consume retries nor run new actions on that repo. If it is configured again, its pending executions become eligible for recovery again, respecting those that already required intervention. This rule is evaluated at startup; it does not imply implementing hot configuration reload.

Continuity includes the author's and reviewer's session, the caller's context and the workspace with its Git state, including work not yet committed. The Claude and Codex adapters must allow resuming the kept sessions. Restarting the orchestrator does not mean launching `ship` again from scratch. On resume, the agent verifies which operations finished and continues from the real state; a recovered session is not the same as resuming a system command at exactly the instruction where it was interrupted.

If a session cannot be recovered, the process records the reason and opens a new one with the same identity, the persisted context, previous conclusions and reports, and the current state of the workspace/GitHub. The agent verifies which operations were completed and continues what is pending. The recovery is kept in the history to distinguish a resumed session from a rebuilt context.

`Ctrl+C` stops taking work and stops the active executions, including the agents' child processes, without waiting for the stages to finish. State and session identifiers are recorded during execution, not only when it ends. Session files, workspaces and logs are kept. On restart, interrupted stages are reconciled before continuing; agents that were left alive and external actions already performed are not duplicated.

## Terminal panel

The command runs in whatever terminal Diego uses: macOS Terminal, iTerm, Ghostty or an integrated terminal. The panel is drawn in that same window; the program does not require a terminal of its own. Agents run as child processes and their output is captured for logs and activity. Proposal: plain output if there is no interactive terminal.

Show occupied slots, queued epics and each execution's stage. For each epic: round, blockers, time in stage, last activity and links to the issue/PR. Detailed logs stay in files.

The current stage and the last activity are distinct data: absence of output does not mean the agent is making progress. The panel must also show errors and intervention reasons.

The first panel only informs: epics, stages, rounds, blockers, activity, errors and references to logs. It does not include pause or retry controls. `Ctrl+C` stops the process; configuration and startup are done from the command. Testing the full flow is prioritized before expanding the interface.

## Proposed configuration

Agreed format: JSON. The app ships a default configuration and supports a user configuration that only needs to declare the values it wants to change. The user's simple values replace the defaults; objects are combined field by field, keeping omitted fields; lists are replaced whole, without concatenation. A value of an incompatible type must not be silently converted to complete the merge.

On startup, the application combines defaults and user configuration and validates the result, including required fields, types, references to identities and allowed limits. Errors must identify the field and the problem so the configuration can be fixed. Then the per-repo overrides are resolved over the global agent values; an epic's effective configuration is persisted when it starts. The default configuration belongs to the app package; user-specific data is kept outside the code.

Validation is implemented with Zod, sharing the schemas with the inferred TypeScript types. `config/` keeps the configuration schema and `execution/` the caller result schema; each module retains ownership of its contract. Structure validation is distinct from the reference-coherence checks and from the repo evaluation that agents perform. [Zod documentation](https://zod.dev/).

List of GitHub repos to look for epics in and location of code/workspaces; catalog of GitHub profiles and the profile selected for the orchestrator; identity, provider and model per agent role; provider-specific options; concurrency; review limit; query frequency; execution retry and time limits. The configuration must be usable independently of the directory from which the process is started. The repo's validation rules are queried from the agents and skills.

Author/reviewer identity, provider and model have global values and per-repo overrides. A repo inherits each global field it does not explicitly replace. The author and reviewer identity for the same PR remains different after resolving those overrides. The scope of the agreed overrides does not include an individual per-epic configuration.

Agreed values: Claude and Codex as initial providers, five reviews, three execution retries, three simultaneous epics and four hours per agent execution as initial values, with all limits configurable. The duration allows an explicit no-limit option. `ship`'s internal concurrency must also be considered to control the real load.

Save the effective agent configuration when an epic starts, after resolving defaults and per-repo overrides. Configuration changes apply to new epics; those in progress keep their identities, providers and models, also when resuming a session or rebuilding its context. The persisted configuration does not include secret credentials. A provider change or fallback during an execution is not automatically derived from modifying the defaults.

### What a time limit means

A timeout is a limit for an execution or call that does not finish; it is not the polling frequency nor a promised duration of an epic. Differentiate brief GitHub calls from a `ship` that can work for hours. The absence of logs does not by itself prove that an agent is stuck.

The maximum per agent execution is four hours by default, configurable, with an explicit no-limit option. Proposed JSON representation: `"maxExecutionHours": 4` or `"maxExecutionHours": "unlimited"`; if the setting is omitted, apply the default four hours. Zero does not mean infinite. It is the limit of one invocation of `ship`, review or fix, not that of the whole epic nor its wait in the queue.

When the limit expires, stop the execution, keep sessions and workspaces and record the reason. The epic is left as requiring intervention so Diego decides how to continue; it is not retried automatically on timeout. Before continuing, stop or reconcile the previous processes; never launch another author while the previous one is still acting on the same workspace. Pending: set timeouts for brief external operations.

## First version limits

A local process for macOS, SQLite, logs and terminal panel. No web server or OS app. The TypeScript/Node.js core stays portable; Linux and Windows are outside the initial validation and support. Merging the final PR and resolving cases that require intervention are human. No command or UI is added to reactivate those cases. Dependencies between epics will be resolved separately in Solve; the MVP takes ready issues directly. The system runs the skills; it does not reproduce their implementation and review logic inside the orchestrator.

The prior research is in [autonomous-ship-review.md](research/autonomous-ship-review.md). Its maximum of four reviews was replaced by the five configurable ones in this document.

## Project and storage

The orchestrator is a standalone app with its own repo, [AshuLab/carrier](https://github.com/AshuLab/carrier); it is not implemented inside SecondBrain nor inside the repos where it looks for epics. This document lives in that repo's `docs/` as a working draft. Code and tests live in the app's repo; configuration and execution data are placed under the shared root, independently of the code's location or the folder from which the command is run.

## Technologies and versions

Agreed stack: TypeScript, Node.js 26 and ESM, with pnpm as the package manager. Runtime dependencies already chosen: `zod`, `@ashulab/universal-logger`, `drizzle-orm` and `better-sqlite3`. Drizzle Kit and Vitest are added as development tooling for migrations and tests, along with any additional types the driver requires. Agent Forge remains an installed external dependency.

When adding or updating each package, check the latest published stable version and verify compatibility with Node 26. This also applies to development tooling; exclude alpha, beta, RC, nightly or other prerelease versions. Record the selected versions and version `pnpm-lock.yaml`; pin the pnpm version in `packageManager`. Reproducible installs use that lockfile, and upgrades are verified with build, type checking and tests. Selecting recent versions does not imply resolving different new versions on each app startup.

Reference consulted on 2026-10-15: [Node 26.12.0](https://nodejs.org/en/download), [pnpm 12.11.2](https://registry.npmjs.org/pnpm/latest) and [TypeScript 7.0.2](https://registry.npmjs.org/typescript/latest). These are observed versions; they do not replace checking the stable ones again when creating the project. The inspected code version of universal-logger should likewise not be automatically taken as the latest published.

## Code structure under definition

A single Node/TypeScript package, grouped by responsibility. Create the concrete files when implementing each responsibility.

```text
src/
  cli/              # startup, Ctrl+C and panel
  config/           # reading, validation and overrides
  orchestration/    # epic selection, stages, turns and limits
  execution/        # processes, sessions and result contract
  storage/          # Drizzle schema, SQLite and execution artifacts
  logging/          # universal-logger configuration and integration
  integrations/     # GitHub and Forge
  providers/        # Claude and Codex
  prompts/          # author and reviewer instructions
  shared/           # helpers reusable across modules
test/
```

`shared/` gathers genuinely shared general utilities, for example duration formatters for panel/logs or path helpers. It may contain files such as `formatters.ts` and `paths.ts` when needed. Normalizations specific to a configuration, a provider result or a GitHub response belong to `config/`, `providers/` or `integrations/`, respectively. Shared helpers do not depend on the workflow or on concrete adapters. Avoid concentrating unrelated functions in a single `utils.ts`.

## SQLite access

Use `drizzle-orm` to define the schema in TypeScript and access SQLite, and `drizzle-kit` as a development dependency to generate migrations. Keep schema, connection and queries in `storage/`. The generated migrations are versioned with the code and are part of the artifacts needed to run the app.

The agreed driver is `better-sqlite3`, consumed by Drizzle's SQLite adapter. The [official documentation](https://orm.drizzle.team/docs/sqlite/get-started-sqlite) describes that combination. The current examples show RC releases: when implementing, check the published stable versions and their compatible APIs, respecting the agreed policy of excluding prereleases. Do not assume an API available in the RC documentation already exists in the stable one. Validate installation, migrations and transactions with Node 26 on macOS before testing the agent flow.

## Logging and errors

Agreed runtime dependency: `@ashulab/universal-logger`, the package from the [AshuLab/universal-logger](https://github.com/AshuLab/universal-logger) repo. The [reviewed package.json](https://github.com/AshuLab/universal-logger/blob/16eabc1e3d78bf145f6619f60f5419e1565075b7/package.json) declares that name and ESM exports. The inspected version is 0.1.1; pin a compatible version when implementing the app. The decision is to consume the installed package, not to reproduce its format nor copy its code.

Configure the library once at startup and use its levels API and `createScopedLogger` in the modules. Proposed initial level: INFO, configurable; the library uses WARN outside development when no level is configured. For errors, pass the original error object to `logError` or to the scoped logger's `error` method to preserve its information and stack. Attach repo, epic, execution, role and stage context as appropriate, without credentials or tokens. [API and implementation](https://github.com/AshuLab/universal-logger/blob/16eabc1e3d78bf145f6619f60f5419e1565075b7/src/index.ts).

`logging/` only integrates and configures that dependency for the app and its output. Operational logs are saved under `~/.solve/orchestrator/logs/`, following the configurable root. Proposed files: `orchestrator.log` for the process and `executions/<executionId>/stdout.log` and `stderr.log` to keep each agent's full outputs. SQLite keeps coordination conclusions and history; the files keep the detailed logs and reports.

The reviewed implementation emits to the console: debug/info use stdout and warn/error use stderr. It does not expose a general file transport; `setErrorReporter` only reports errors and does not replace that output. Validate the integration of both streams with the files and the terminal panel, keeping the package as the logging implementation. The panel uses the orchestrator's state and the agents' detailed output is captured separately so it is not mixed with its visual representation.

## App test strategy

Use Vitest at its latest stable version compatible with the stack. Test coordination behavior: configuration merge/validation, FIFO and concurrency, transitions by outcome, review/retry limits, idempotent result import, persistence and recovery after interruptions. Use a real temporary SQLite when verifying migrations and transactions, and simulated agents to control responses, timings and process failures. The test or CI policy of the implemented repo remains the agents' responsibility, not the engine's nor its tests'.

Real tests with Claude, Codex, Forge and Solve are separate integration tests, with a test repo and explicit configuration; they must not run automatically in the usual suite. They must validate the runner contract, sessions, credentials, workspaces and delivery of the caller's results. [Vitest documentation](https://vitest.dev/guide/).

## Pending technical details

1. How to communicate the agreed shared root and conventions to Solve; `~/.solve/` configurable, the subdirectories and starting from any folder are already agreed.
2. Check that the external change in Solve publishes `solve:epic:ready` as a direct pick-up signal; the MVP needs no other availability query.
3. Fields and schema of the caller's JSON; the file transport, validation, SQLite storage and history are already agreed.
4. Integration of personal identities and bots with Forge and credential renewal during long executions. Resolving cases that require intervention stays in Diego's hands, with no reactivation command in this version.
5. Strategy for resuming interrupted work and flow tests; the initial panel is already defined as informational and simple.
6. Integration of `@ashulab/universal-logger`'s output with files and the terminal panel, including flush when stopping the process; the package is already chosen as a runtime dependency.
