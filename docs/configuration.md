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
  "providers": {
    "claude": { "harness": "claude" },
    "codex": { "harness": "codex" }
  },
  "agents": {
    "author": { "profile": "author-bot", "provider": "claude", "model": "<model>" },
    "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "<model>" }
  }
}
```

## Fields

| Field | Required | Default | Meaning |
|-------|----------|---------|---------|
| `repos` | yes, at least one | | Repos to watch. Each is `{ "name": "owner/name", "agents"?: ... }`. |
| `profiles` | yes | | The GitHub identities you can use, by name (below). |
| `orchestratorProfile` | yes | | Profile used to read issues and PRs and to change labels. It may be the author's. |
| `providers` | yes | | Configured AI accounts/logins (`harness`, `configDir?`, `provider?`). See [AI providers](#ai-providers). |
| `agents.author` / `agents.reviewer` | yes | | `{ profile, provider, model, persona? }` for each role: the GitHub identity it acts as, the AI provider it connects through, and the model it uses. |
| `agents.leadReviewer` | no | none | Optional technical lead role `{ profile, provider, model, persona? }` (configuration setup; reserved for upcoming lead reviewer gating in the Carrier flow). |
| `agents.<role>.persona` | no | none | `{ name?, prompt? }`: who the agent of that role is. `name` is one line of at most 40 characters; `prompt` is text of at most 4000 characters, given to the agent as you wrote it. See [Personas](#personas). |
| `failover` | no | off | `{ enabled, triggers?, default?, roles? }`: moves a role to the next AI provider when its credits run out or service fails. See [Failover](#failover). |
| `pollIntervalMinutes` | no | `5` | How often it looks for ready epics. |
| `finishedWindowDays` | no | `15` | Days a merged or cancelled epic stays in the snapshot after it ends, a whole number from 1 to 30 (30 is the retention purge). |
| `logLevel` | no | `info` | `debug`, `info`, `warn` or `error`. |
| `identities` | no | `separate` | `separate` or `shared`. Under `separate` the author and the reviewer must be different identities. Under `shared` they may use the same profile, normally your `gh` login. See [Profiles](#profiles). |
| `limits.maxConcurrentEpics` | no | `3` | Epics running at the same time. |
| `limits.maxReviews` | no | `5` | Review rounds before the epic goes to `needs-human`. |
| `limits.maxExecutionRetries` | no | `3` | Retries after a technical failure of an agent execution. |
| `limits.maxExecutionHours` | no | `4` | Time limit of one agent execution, or `"unlimited"`. `0` does not mean infinite. |
| `limits.githubCallTimeoutSeconds` | no | `30` | Limit for each short call to GitHub or Forge. |
| `limits.optionChoiceSeconds` | no | `60` | With two or more `providers`, how long a reserved epic holds its slot waiting for the provider of each role to be chosen. When it passes, or nobody answers, the epic starts on the defaults of `agents`. With one provider nothing waits. |

## AI providers

An AI provider represents an account/login setup for an AI harness (e.g. Claude Code with a specific `configDir`, Antigravity, or Codex). A provider defines the account and installation independently of the model.

```json
"providers": {
  "claude-work": { "harness": "claude", "configDir": "~/.claude-work" },
  "claude-personal": { "harness": "claude", "configDir": "~/.claude" },
  "codex": { "harness": "codex" },
  "agy": { "harness": "agy" }
}
```

| Field of a provider | Required | Meaning |
|----------------------|----------|---------|
| (the key) | | The provider's name: a lowercase word, with letters, digits and hyphens, starting with a letter, up to 40 characters. |
| `harness` | yes | The agent CLI that runs it: `claude` (Claude Code), `codex` or `agy` (Antigravity). |
| `model` | no | Optional default model for this provider connection, used when failover moves to this provider or when inherited by a role. |
| `provider` | no | Who serves the model: `lmstudio` or `ollama` for a local server; without it, the harness's own cloud. See [Local models](#local-models). Not for `agy`. |
| `configDir` | no | The harness's config folder, which holds its login: `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. It must be an absolute path once a leading `~` is expanded. Without it the agent inherits the environment of the process that started Carrier. Not for `agy`. |

`carrier init` configures your AI providers upfront in Stage 2, before role assignment. When assigning roles in Stage 4, each role points at a declared provider and specifies its model.

## Agents and roles

Each role in `agents` (`author`, `reviewer`, and optional `leadReviewer`) specifies its GitHub identity (`profile`), its AI connection (`provider`), the `model` it runs on, and an optional `persona`.

```json
"agents": {
  "author": { "profile": "author-bot", "provider": "claude-work", "model": "sonnet" },
  "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "gpt-5.3-codex" },
  "leadReviewer": { "profile": "reviewer-bot", "provider": "claude-personal", "model": "opus" }
}
```

- For Claude models, prefer an alias (`sonnet`, `opus`, ...): the CLI resolves it to the latest model, so it does not go stale.
- Codex has no aliases: use an id from `codex`'s own list.
- For Antigravity, use an id from `agy models` (`carrier init` offers all of them).

### Choosing the provider of an epic

With one provider nothing is asked. With two or more, a reserved epic does not start its author at once: it holds its slot for `limits.optionChoiceSeconds` (default 60) while the provider of each role can be chosen over the control socket (`chooseOptions`, listed in the hello's `capabilities` as `agentOptions`). `carrier status` shows the epic as waiting for its choice, with the seconds left. A role that is not chosen runs on the provider `agents.<role>.provider` names, and so does every role when the time passes, when nobody answers, or when Carrier starts again after the deadline.

### Failover

Off unless the config has a `failover` block with `enabled: true`.

Failover automatically moves an agent to the next provider in its fallback chain when an execution fails due to account/provider issues, without wasting technical retries on a broken provider.

```jsonc
"failover": {
  "enabled": true,
  // Events that trigger failover (defaults to all three):
  "triggers": ["usage_limit", "rate_limit", "service_down"],

  // Global fallback chain used by any role without a specific override:
  "default": ["claude-teams", "claude-personal", "codex"],

  // Optional role-specific fallback chains:
  "roles": {
    "author": ["claude-teams", "claude-personal", "codex"],
    "reviewer": ["codex", "claude-personal"],
    "leadReviewer": ["claude-personal", "codex"]
  }
}
```

#### Triggers
- `usage_limit`: The agent CLI or API ran out of credits/billing quota.
- `rate_limit`: Persistent HTTP 429 rate limit that exceeds normal backoff retry.
- `service_down`: Provider or local server unavailable (`ECONNREFUSED`, 5xx, or CLI connection failure).

#### Fallback resolution
When a role experiences a failure matching `triggers`:
1. Carrier checks `failover.roles.<role>`. If defined, it uses that role's fallback chain.
2. Otherwise, it falls back to `failover.default`.
3. The role moves to the next provider in the chain that has not already failed in this epic. The stage restarts as a fresh session in the epic's worktree with its context rebuilt from SQLite and GitHub (spending no retry and emitting an `option_switched` event).
4. If no providers in the chain are left, the epic stops in `needs-human` detailing which providers failed.

Every provider name in `default` or `roles.<role>` must be declared in `providers`, and none may appear twice within the same list.

## Personas

A role, author or reviewer, can have a persona: a name and a prompt that say who the agent is and how it behaves. Carrier adds them to that agent's prompt, right after the line that says which role it is and before what the stage asks. The persona belongs to the role, not to a stage: the author's is used in `ship` and `fix`, the reviewer's in `review`. Either field can be left out, and without a persona the prompt is the one it always was.

```json
"agents": {
  "reviewer": {
    "profile": "reviewer-bot",
    "provider": "codex",
    "model": "gpt-5.3-codex",
    "persona": { "name": "Rex", "prompt": "Be strict about migrations." }
  }
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
{
  "name": "AshuLab/big-repo",
  "agents": {
    "reviewer": { "provider": "claude-personal", "model": "opus" },
    "author": { "profile": "other-bot" }
  }
}
```

Profile names used in an override must exist in `profiles`, and provider names in `providers`. Under `identities: "separate"` the author and the reviewer must still differ after the override.

## Chat configuration

The chat host and `carrier chat` start from the Carrier folder alone (`~/.carrier`, or `CARRIER_HOME`) and read no engine config. Everything the chat owns is in `<folder>/chat/` (`state/`, `logs/`, `projects/`, `worktrees/`), and its settings are in the optional `<folder>/chat/chat.json`. Every key is optional and so is the file; with neither, the chat uses the defaults below. Unknown keys are errors. A file that is not valid JSON or does not match makes `carrier chat-host` exit with a message that names the file and the key, and the host does not start.

```json
{
  "agents": {
    "claude": { "harness": "claude" },
    "claude-opus": { "harness": "claude", "model": "opus", "options": { "permissionMode": "plan" } },
    "codex": { "harness": "codex", "command": "/opt/homebrew/bin/codex" }
  },
  "projectsFolder": "~/Projects/carrier",
  "githubCallTimeoutSeconds": 30,
  "logLevel": "info"
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `agents` | `claude` and `codex` | The agents a chat can start with, by name, in the order written, and only those (`{}` means none). `carrier chat` without `--agent` uses the first. See [Chat agents](#chat-agents). Read when the host starts. |
| `projectsFolder` | `<folder>/chat/projects` | Where the host puts the repositories it clones (`<owner>/<repo>` inside it). An absolute path, or one starting with `~/`. It may not lie inside `<folder>/engine/` or the chat's own `state/`, `logs/` or `worktrees/`. Read at each request, so a change applies to the next clone with no restart. See [Projects folder](#projects-folder). |
| `githubCallTimeoutSeconds` | `30` | A positive whole number: how long a call to GitHub (the repository list, the login) may take. Read when the host starts. |
| `logLevel` | `info` | `debug`, `info`, `warn` or `error`. Read when the host starts. |

A session never works inside `<folder>/engine/`, nor through a symlink into it. The engine's config has no `chat` section: it rejects one like any unknown key.

## Chat agents

A chat (`carrier chat`) starts with one of the agents in `agents`, each running its own harness with the binary on the path and the provider's defaults unless it says otherwise.

| Field | Required | Meaning |
|-------|----------|---------|
| the key | yes | The agent's name: lowercase letters, digits and hyphens, starting with a letter. |
| `harness` | yes | `claude` or `codex`. Antigravity is not offered in a chat. |
| `command` | no | The binary, when it is not the one on the path. Not empty. |
| `model` | no | The model the provider starts with. Not empty. |
| `options` | no | Default options of the provider, by the provider's own option id. An option the provider does not list is refused when the session opens. |

## Projects folder

The chat host can clone a GitHub repository for a session (the `cloneRepo` request). It goes to `<projects folder>/<owner>/<repo>`; one already there (a `.git` whose `origin` is that repository) is fetched instead, and anything else at that path stops the request and is left untouched. The clone and the fetch use the token of your active `gh` login, handed to git in its environment, so `gh` must be installed and signed in. Each git command has ten minutes. A new project (the `createProject` request) is a folder at `<projects folder>/local/<name>` with `git init -b main`; the name is a plain folder name (letters, digits, `_`, `.` and `-`, at most a hundred, not starting with a dot or a dash), one that is taken is refused and nothing is changed. The same host lists your repositories for the app's "My GitHub repositories" step (the `githubRepos` request, thirty a page, with the same `gh` login): every repository that login can read, as owner, collaborator or organisation member, archived and disabled ones left out; it needs no config. Carrier never deletes anything in the folder, except the half-made clone or project of a request that failed or was cancelled.

## Things that are checked

- Every profile named anywhere is declared in `profiles`, and every provider named anywhere in `providers`.
- Every name in `failover.default` or `failover.roles` is declared in `providers` and appears once per list.
- Provider names are lowercase words, a `configDir` is absolute after `~` is expanded, and a provider has no field this page does not list.
- Repo names are `owner/name`, and no two repos share the same folder name (Solve's worktree paths have no owner).
- A `provider` (local model server) is only accepted for a harness that can use it (Claude Code and Codex; not Antigravity), and so is a `configDir`.
- The effective configuration of an epic is saved, without credentials, when it starts and kept when it resumes, even if you change the file in between.

## Local models

A provider defines the **harness** (the CLI that runs the loop and the tools) and where it connects. By default the connection is the harness's own cloud; it can also be a local model server. An agent can use a model served by [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com) on this machine instead of a cloud model. The harness is still Claude Code or Codex, which talk to the local server:

```json
"providers": {
  "local": { "harness": "codex", "provider": "lmstudio" }
},
"agents": {
  "reviewer": { "profile": "reviewer-bot", "provider": "local", "model": "google/gemma-4-12b" }
}
```

- **Codex** gets `-c model_provider="lmstudio"` (or `ollama`); **Claude Code** gets `ANTHROPIC_BASE_URL` pointing at the server (and a placeholder token, never your real API key).
- The servers are expected on their default ports (LM Studio `1234`, Ollama `11434`). Start the server and download the model first; `carrier doctor` checks both, and `carrier init` lists the models the running server has.
- Antigravity (`agy`) cannot be pointed at a local server: `provider` on an entry with `harness: "agy"` is rejected. Its models come from `agy models`, which `carrier init` lists.
- A per-repo override points a role at another provider, so to go back to a cloud model in one repo, override `provider` with one that has no local `provider`.
- Expect it to be **slow** (a trivial prompt took 15 to 140 s on a laptop, mostly loading the model and the CLI's long system prompt) and **weaker** on long agentic work. `ship` and a full review make hundreds of tool calls; small local models often lose the thread. A local reviewer is the realistic use; test it on a throwaway epic before trusting it.
