# Configuration

`carrier init` writes this file for you, by default to `~/.carrier/config.json` (global, one per user; `carrier` and `carrier doctor` read it when you do not pass `--config`; `CARRIER_HOME` changes the folder); this page is the reference for editing it by hand. `carrier doctor --config <file>` checks it and `carrier schema` prints its JSON Schema (add it to your editor for completion).

The file is a JSON object merged over the defaults: objects merge field by field, simple values replace the default, lists replace it whole. A value of the wrong type is an error, never converted. An invalid config prints every error with its field and exits without starting anything.

## Minimal file

```json
{
  "repos": [{ "name": "AshuLab/my-repo" }],
  "profiles": {
    "author-bot": { "kind": "forge", "agent": "<forge-agent-1>" },
    "reviewer-bot": { "kind": "forge", "agent": "<forge-agent-2>" }
  },
  "orchestratorProfile": "author-bot",
  "agentOptions": {
    "claude": { "harness": "claude", "model": "<model>" },
    "codex": { "harness": "codex", "model": "<model>" }
  },
  "agents": {
    "author": { "profile": "author-bot", "option": "claude" },
    "reviewer": { "profile": "reviewer-bot", "option": "codex" }
  }
}
```

## Fields

| Field | Required | Default | Meaning |
|-------|----------|---------|---------|
| `repos` | yes, at least one | | Repos to watch. Each is `{ "name": "owner/name", "agents"?: ... }`. |
| `profiles` | yes | | The GitHub identities you can use, by name (below). |
| `orchestratorProfile` | yes | | Profile used to read issues and PRs and to change labels. It may be the author's. |
| `agentOptions` | yes | | The ways to run an agent, by name. See [Agent options](#agent-options). |
| `agents.author` / `agents.reviewer` | yes | | `{ profile, option, persona? }` for each role: the GitHub identity it acts as and the name of the agent option it runs on. |
| `agents.<role>.persona` | no | none | `{ name?, prompt? }`: who the agent of that role is. `name` is one line of at most 40 characters; `prompt` is text of at most 4000 characters, given to the agent as you wrote it. See [Personas](#personas). |
| `failover` | no | off | `{ enabled, order }`: moves a role to the next agent option when its credits run out. See [Failover](#failover). |
| `root` | no | `~/.solve` | The folder shared with Solve: `repos/`, `worktrees/`, `reviews/`, `orchestrator/`. |
| `pollIntervalMinutes` | no | `5` | How often it looks for ready epics. |
| `finishedWindowDays` | no | `15` | Days a merged or cancelled epic stays in the snapshot after it ends, a whole number from 1 to 30 (30 is the retention purge). |
| `logLevel` | no | `info` | `debug`, `info`, `warn` or `error`. |
| `identities` | no | `separate` | `separate` or `shared`. Under `separate` the author and the reviewer must be different identities. Under `shared` they may use the same profile, normally your `gh` login. See [Profiles](#profiles). |
| `limits.maxConcurrentEpics` | no | `3` | Epics running at the same time. |
| `limits.maxReviews` | no | `5` | Review rounds before the epic goes to `needs-human`. |
| `limits.maxExecutionRetries` | no | `3` | Retries after a technical failure of an agent execution. |
| `limits.maxExecutionHours` | no | `4` | Time limit of one agent execution, or `"unlimited"`. `0` does not mean infinite. |
| `limits.githubCallTimeoutSeconds` | no | `30` | Limit for each short call to GitHub or Forge. |
| `limits.optionChoiceSeconds` | no | `60` | With two or more `agentOptions`, how long a reserved epic holds its slot waiting for the option of each role to be chosen. When it passes, or nobody answers, the epic starts on the options of `agents`. With one option nothing waits. |

## Agent options

An agent option is a named way to run an agent. The config declares them once in `agentOptions`, and each role points at one by name in `agents.<role>.option`, the way it points at a profile.

```json
"agentOptions": {
  "claude-ashu": { "harness": "claude", "model": "opus", "configDir": "~/.claude-ashu-lab" },
  "claude-personal": { "harness": "claude", "model": "opus", "configDir": "~/.claude" },
  "codex": { "harness": "codex", "model": "<model>" }
},
"agents": {
  "author": { "profile": "author-bot", "option": "claude-ashu" },
  "reviewer": { "profile": "reviewer-bot", "option": "codex" }
}
```

| Field of an option | Required | Meaning |
|--------------------|----------|---------|
| (the key) | | The option's name: a lowercase word, with letters, digits and hyphens, starting with a letter, up to 40 characters. |
| `harness` | yes | The agent CLI that runs it: `claude` (Claude Code), `codex` or `agy` (Antigravity). |
| `model` | yes | For Claude prefer an alias (`sonnet`, `opus`, ...): the CLI resolves it to the latest model, so it does not go stale. Codex has no aliases: use an id from `codex`'s own list; for Antigravity, one from `agy models` (`carrier init` offers all of them). |
| `provider` | no | Who serves the model: `lmstudio` or `ollama` for a local server; without it, the harness's own cloud. See [Local models](#local-models). Not for `agy`. |
| `configDir` | no | The harness's config folder, which holds its login: `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. It must be an absolute path once a leading `~` is expanded. Without it the agent inherits the environment of the process that started Carrier. Not for `agy`, which has no setting for it. |

A repo's `agents.<role>` can override `profile`, `option` and `persona`; the option is looked up in the same `agentOptions`. `harness`, `model` and `provider` used to be written inside `agents.<role>`: a config that still does so is refused, with a message that says they moved here. There is no migration; move the three fields into an option and point the role at it.

### Choosing the option of an epic

With one option nothing is asked. With two or more, a reserved epic does not start its author at once: it holds its slot for `limits.optionChoiceSeconds` (default 60) while the option of each role can be chosen over the control socket (`chooseOptions`, listed in the hello's `capabilities` as `agentOptions`). `carrier status` shows the epic as waiting for its choice, with the seconds left. A role that is not chosen runs on the option `agents.<role>.option` names, and so does every role when the time passes, when nobody answers, or when Carrier starts again after the deadline. The definitions of the options are saved with the epic when it is reserved: editing the config later changes no epic that is waiting or running.

### Failover

Off unless the config has a `failover` block with `enabled: true`. `order` is the list of option names a role may move to, and it is an allowlist: switching can send the code of a private repo to another provider and spend another account, so a role never moves to an option that is not in it, even if it is the other role's option.

```jsonc
"failover": { "enabled": true, "order": ["claude-personal", "codex"] }
```

When an execution of a role ends because its option ran out of credits (`usage_limit`), the role moves to the first name in `order` that has not already run out in this epic, and the stage runs again as a new session in the epic's worktree and pull request, with its context rebuilt from SQLite and GitHub (the conversation of the agent is lost, the work is not). It spends no retry and records an `option_switched` event with the role, the two options and the stage. Only the role that ran out moves; the other keeps its option. When no name in `order` is left, the epic stops in `needs-human` with kind `usage_limit` and a reason that names every option that ran out. With `enabled: false`, or without the block, a `usage_limit` stops the epic at once, as before. Nothing is remembered across epics: the next epic starts on its own choice, and pays one failed attempt if that option is still out.

Every name in `order` must be declared in `agentOptions`, and none may appear twice.

## Personas

A role, author or reviewer, can have a persona: a name and a prompt that say who the agent is and how it behaves. Carrier adds them to that agent's prompt, right after the line that says which role it is and before what the stage asks. The persona belongs to the role, not to a stage: the author's is used in `ship` and `fix`, the reviewer's in `review`. Either field can be left out, and without a persona the prompt is the one it always was.

```json
"agents": {
  "reviewer": { "profile": "reviewer-bot", "option": "codex", "persona": { "name": "Rex", "prompt": "Be strict about migrations." } }
}
```

A repo's `agents.<role>.persona` replaces the global persona of that role whole, not field by field. When `carrier init` edits a config, an empty answer keeps a persona field and `-` clears it. The name is trimmed and cannot contain a line break; the prompt is trimmed and cannot be empty.

## Profiles

A profile names a GitHub identity. There are two kinds and neither holds a secret:

- `{ "kind": "forge", "agent": "<name in your Agent Forge registry>" }`: a bot (a GitHub App) through [Agent Forge](https://github.com/AshuLab/agent-forge). Each run gets a short-lived token with the minimum scope.
- `{ "kind": "gh" }`: your own `gh` login.

With `identities: "separate"` (the default) the author and the reviewer need **different identities**, so that the reviewer's comments and approvals are not the author's own. The config rejects the same profile name for both, and `carrier doctor` also catches two names pointing to the same bot or both being `gh`.

With `identities: "shared"` the author and the reviewer may use the same profile (for example `gh` for both), for someone who cannot get a second GitHub identity. Both roles then act with everything that login's token can do. An epic counts as shared, and its agents sign, when both roles resolve to the same account: the same profile, two names for your `gh` login, or two names for the same bot. The config and `carrier doctor` no longer require them to differ; `carrier doctor` still checks that each profile can get a token and read each repo. Two different profiles stay valid under `shared`, for a repo whose override uses a bot. See [ADR 0011](adr/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md).

## Per-repo overrides

A repo inherits every value from the global `agents` and replaces only what it names:

```json
{ "name": "AshuLab/big-repo", "agents": { "reviewer": { "option": "claude-personal" }, "author": { "profile": "other-bot" } } }
```

Profile names used in an override must exist in `profiles`, and option names in `agentOptions`. Under `identities: "separate"` the author and the reviewer must still differ after the override.

## Things that are checked

- Every profile named anywhere is declared in `profiles`, and every option named anywhere in `agentOptions`.
- Every name in `failover.order` is declared in `agentOptions` and appears once.
- Option names are lowercase words, a `configDir` is absolute after `~` is expanded, and an option has no field this page does not list.
- Repo names are `owner/name`, and no two repos share the same folder name (Solve's worktree paths have no owner).
- A `provider` is only accepted for a harness that can use it (Claude Code and Codex; not Antigravity), and so is a `configDir`.
- The effective configuration of an epic is saved, without credentials, when it starts and kept when it resumes, even if you change the file in between.

## Local models

An agent option is three separate things: the **harness** (the CLI that runs the loop and the tools), the **provider** that serves the model, and the **model**. By default the provider is the harness's own cloud; it can also be a local server. An agent can use a model served by [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com) on this machine instead of a cloud model. The harness is still Claude Code or Codex, which talk to the local server:

```json
"agentOptions": { "local": { "harness": "codex", "model": "google/gemma-4-12b", "provider": "lmstudio" } },
"agents": { "reviewer": { "profile": "reviewer-bot", "option": "local" } }
```

- **Codex** gets `-c model_provider="lmstudio"` (or `ollama`); **Claude Code** gets `ANTHROPIC_BASE_URL` pointing at the server (and a placeholder token, never your real API key).
- The servers are expected on their default ports (LM Studio `1234`, Ollama `11434`). Start the server and download the model first; `carrier doctor` checks both, and `carrier init` lists the models the running server has.
- Antigravity (`agy`) cannot be pointed at a local server: `provider` on an option with `harness: "agy"` is rejected. Its models come from `agy models`, which `carrier init` lists.
- A per-repo override points a role at another option, so to go back to a cloud model in one repo, override `option` with one that has no `provider`.
- Expect it to be **slow** (a trivial prompt took 15 to 140 s on a laptop, mostly loading the model and the CLI's long system prompt) and **weaker** on long agentic work. `ship` and a full review make hundreds of tool calls; small local models often lose the thread. A local reviewer is the realistic use; test it on a throwaway epic before trusting it.
