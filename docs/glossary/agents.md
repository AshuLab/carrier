# Agents

**Caller agent** - Agent that invokes the skills, interprets their current reports and applies the repo's rules to work as author or reviewer. It hands the orchestrator one structured conclusion per execution.
_Avoid_: skill, orchestrator when referring to the agent that interprets the reports.

**Harness** - The agent CLI that runs the loop and the tools of an execution (Claude Code, Codex, Antigravity). Carrier launches it as a child process, as the user's normal CLI. It is the `harness` of an agent in the config.
_Avoid_: provider, agent (the author and the reviewer are agents; the harness is what runs them), runner.

**Model provider** - Who serves the model the harness uses: the harness's own cloud (Anthropic for Claude Code, OpenAI for Codex) or a local server (LM Studio, Ollama). It is the optional `provider` of an account; without it, the harness's own cloud.
_Avoid_: harness, local model (a local model is a model whose provider is a local server).

**Account** - One login of an agent CLI that Carrier can run an agent with: a name, its harness, where its login lives (a config folder, `CLAUDE_CONFIG_DIR` or `CODEX_HOME`, or this Mac's own) and how its CLI is run (binary, launch arguments, compaction). It is what the config calls a `provider`: a role, a failover list and a chat agent each name one. It is kept in `providers.json`, and the app's Providers page lists the tools found on this Mac with their accounts under each.
_Avoid_: provider (the app's page of tools, and the config key under which accounts are kept), login, connection, option (the older name), identity (a GitHub profile is that).

**GitHub profile** - User-configured reference to an available GitHub identity and its authentication mechanism. It is assigned to the orchestrator, author or reviewer; it is independent of the AI harness/model and of an agent's working session.
_Avoid_: model, agent session, AI identity for a GitHub account.

**Orchestrator's profile** - The GitHub profile Carrier reads issues and PRs and changes labels with (`orchestratorProfile`). Left out of the config it is the author's profile; `carrier init` asks for it and Settings → Engine sets it. Set it apart from the author's when the author's bot is not installed on a repo Carrier must read.
_Avoid_: orchestrator identity, reader profile.

**Author** - Agent that invokes `ship` and handles the findings; it keeps its identity throughout the epic.
_Avoid_: implementer, developer.

**Reviewer** - Agent that reviews the final PR in a separate checkout, publishes findings and verifies the fixes. Its GitHub profile differs from the author's, unless the user chose a shared identity.
_Avoid_: external reviewer, review bot.

**Subagent** - A Claude agent launched from inside an execution, with an exact `agentId` in the stream and no session of its own.
A builder subagent builds one slice, in a lane.
A reviewer subagent runs one pass of a review (Spec, Standards, Risk, Experience) and has no slice and no lane.
The slice and the lane of a builder are inferred from the model's wording and the worktree path; the subagent, its times and its end status are exact ([research](../research/claude-subagent-attribution.md)).
A chat session's agent launches them the same way, and the stream tags every message of one with the call that launched it.
_Avoid_: lane (that is where a builder runs), worker, child agent.

**Separate identities** - Setup where the author and the reviewer use different GitHub profiles: two Agent Forge bots, or one bot and the user's `gh` login. It follows from the two roles' accounts, no key says it, and it is what makes the reviewer's comments not the author's own.
_Avoid_: dual identity, bot mode.

**Shared identity** - Setup where the author and the reviewer use the same GitHub profile, normally the user's own `gh` login, so everything the agents publish goes out under that account. It exists for the user who cannot install a GitHub App on the repos they work in. Each role signs what it publishes, and the agents act with everything that login can do. It is not a setting: an epic is shared when its author and reviewer resolve to the same account ([0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)).
_Avoid_: single login, same-account mode, bot-less mode.

**Persona** - What a role (author or reviewer) is given besides its harness and model: a name the user chooses and an optional prompt that says who the agent is and how it behaves. Carrier adds it to the agent's prompt in either identity setup. It is not a GitHub profile: the profile says which account posts, the persona says who is speaking.
_Avoid_: identity (it is ambiguous with the GitHub profile), system prompt, bot name.

**Signature** - The closing line a role puts on everything it publishes under a shared identity: `🤖 <Role> [NAME] via Carrier`, with the persona's name in the brackets. It is mandatory, the user cannot turn it off, and it is what tells the agent's words from the user's own when both come from one account.
_Avoid_: watermark, marker, footer.

**Agent option** - The older name of what a role runs on: a harness, its config folder and a model, declared once in the config and chosen for each epic. It is replaced by an account of the config (a harness and where its login lives) and the model set on the role or on a failover step; an epic no longer chooses ([0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)).
_Avoid_: use account for the login and role for what runs on it.

**Failover** - Carrier moving a role of a running epic from the provider and model that ran out of credits to the next step of that role's chain, with no person involved. A role has failover when its list of steps is not empty, it only ever moves to a step in that list, and it is remembered for that epic only. Each switch is an epic event that says from which provider and model to which, and why.
_Avoid_: fallback, automatic retry (an execution retry repeats the same provider and model; a failover changes them).

**Failover step** - One entry of a role's failover chain: a provider, an account of the config, and optionally a model; without a model it is the account's, then the harness's. A role has as many as the config lists, and the app offers two.

**Role** - One of the three jobs of an epic: Author, Reviewer and Lead reviewer (optional). Each has a GitHub identity, an account, a model, an effort and an optional persona, and its own failover chain. There are no others and the user cannot make more; the same role can differ for one repo.
_Avoid_: agent (the AI that runs a role; and in Agent Forge, a bot), persona (a role's name and prompt, not the role).

**Text generator** - A model that turns text into text with no tools: a server and a model, declared in `providers.json` under `textGenerators` and chosen in the Providers page.
The first kinds are the local servers (LM Studio, Ollama); external APIs come later.
Today the one chosen writes session titles ([0038](../adr/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)).
_Avoid_: model provider (who serves the model an agent runs on), account (a login of an agent CLI), agent (it has no tools and runs nothing), cleanup model (the dictation cleanup keeps its own server and model).
