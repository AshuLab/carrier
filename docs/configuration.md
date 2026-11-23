# Configuration

`carrier init` writes this file for you, by default to `~/.carrier/engine.json` (global, one per user; `carrier` and `carrier doctor` read it when you do not pass `--config`; `CARRIER_HOME` changes the folder); this page is the reference for editing it by hand. `carrier doctor --config <file>` checks it and `carrier schema` prints its JSON Schema (add it to your editor for completion).

The file is a JSON object merged over the defaults: objects merge field by field, simple values replace the default, lists replace it whole. A value of the wrong type is an error, never converted. An invalid config prints every error with its field and exits without starting anything.

## Changing the config while Carrier runs

A running Carrier applies a changed `engine.json` or `providers.json` when it is asked to reload, with no restart. The Mac app asks after each save, and `carrier reload` asks by hand, for an edit in the file (it prints `Reloaded`; it exits 1 with the problem when a file does not match, and also when Carrier is not running or is too old to reload). Nothing watches the files: an edit by hand that is never followed by `carrier reload` waits for the next start.

The engine reads both files again, from the same config path and Carrier folder it started with, and checks them as a start does. A file that does not match is refused with the key named, the same lines a start would print, and Carrier goes on with the settings it had; fix the file and reload again.

What follows a reload: everything the engine reads from those files, that is `pollIntervalMinutes`, `labels`, `finishedWindowDays`, `logLevel`, the five `limits`, the repos with their roles, effort, persona and failover, the `profiles` and `orchestratorProfile`, and the accounts of `providers.json`.
A reload also re-arms the next check from now with the interval then in force and asks for one, so a shorter interval does not wait out the old one and a repo just added is seen at once.

Work already running keeps what it started with, and a change reaches what starts after it:

- An agent run keeps the agent, account and time limit it was launched with.
- An epic keeps the configuration it stored when it started (see [Things that are checked](#things-that-are-checked)); epics that start later use the new roles, effort, persona, failover and accounts, and a restarted epic takes the settings of that moment.
- A limit is read when the decision is made: a changed `maxReviews` or `maxExecutionRetries` applies at the epic's next review or failure, and a `maxConcurrentEpics` lowered below the epics running only stops new ones from starting.
- A repo taken out of `repos` has its epics parked as `repo_removed` where they were, its active agent runs stopped (they end interrupted) and no more calls to GitHub; adding it back restores them.
- A profile removed while a running epic names it stops that epic's next run in `needs-human`, naming the profile; put the profile back and restart the epic.

Still read only at start: the Carrier folder, the `--config` path and the one-instance lock, and updates of Carrier or of the agent CLIs. The chat host is separate and reads its own settings as [Chat configuration](#chat-configuration) says.

## The Carrier folder

Carrier keeps everything it owns in one folder: `~/.carrier/`, or the one in `CARRIER_HOME`. The folder is only that: no key of the config and no `--config` changes it. `--config <file>` only chooses which config file to read (by default `<folder>/engine.json`); to run a second Carrier, give it a second `CARRIER_HOME`.

The top of the folder holds only the files you edit; each process has its own folder next to them, and only that process writes in it ([ADR 0034](adr/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)).

```
<folder>/
  engine.json      the engine's config, this page
  chat.json        the chat's settings (see Chat configuration), optional
  providers.json   the accounts both read (see AI providers)
  projects.json    the projects you work on, read and written by the app and the chat host (see Projects)
  engine/          the engine's own folder
  chat/            the chat host's own folder: state/, logs/, worktrees/, projects/, pending/, sessions/
  app/             the macOS app's own folder: state/, logs/, cache/
```

A file dropped in a message is copied to the chat's `pending/<id>/`; when the message is sent the host moves it to `sessions/<session>/attachments/<id>/`, and deleting the session deletes it.
A copy never sent is swept from `pending/` after a day.

The app's `state/` has its terminals and dictation history, `logs/` its `dictation.log`, and `cache/` the speech models it downloads and the shell setup of its terminals.
`cache/` is kept out of Time Machine and can be deleted: the shell setup is rewritten at the next start, and the speech models are downloaded again from Settings.

`orchestrator.log` and `chat-host.log` rotate at 10 MB: the full one becomes `.1`, the one before `.2`, and so on, keeping 10 files in all.

What each part of `engine/` holds:

| Folder | Holds |
|--------|-------|
| `state/` | `carrier.db` (SQLite, the authority, in WAL mode: `carrier.db-wal` and `carrier.db-shm` appear beside it while it is open and are part of it, so do not delete them or copy `carrier.db` alone while Carrier runs; `.backup` of `sqlite3` takes a consistent copy), `control.sock` (the control socket the CLI and the app use), `carrier.lock` (one engine per folder), the results of each execution (deleted with its logs), and `forge-cwd/<owner>/<name>` (the stub folder Forge runs in before a repo's first clone). |
| `logs/` | `orchestrator.log`, `executions/<id>/` (each agent run's full output), and `start.log` (what a detached Carrier prints; the macOS app's start writes `app-start.log`). |
| `repos/` | Carrier's clones, `<owner>/<repo>`. |
| `reviews/` | The reviewer's separate checkouts, `<repo>/<epic>/`. |
| `worktrees/` | `<repo>/<feature>/`, Carrier's own place for an epic's worktree by default. Any other place works: Carrier finds an epic's worktree with `git worktree list`. |

When an epic is merged or cancelled the engine removes, always, its reviewer checkout, the author's worktree and Solve's `<worktree>--lane-N` worktrees beside it, wherever they are, and the epic's local branches whose tip is already on the remote.
An author or lane worktree with uncommitted files or commits on no branch is kept, and so is a branch that is not on the remote; the log says so.
It does this at the next poll, also for epics that ended earlier; a failure is logged and tried again at the following one.

The socket path has a length limit (about 100 bytes), so keep a `CARRIER_HOME` short; `carrier doctor` warns when `engine/state/control.sock` does not fit.

## Minimal file

```json
{
  "repos": [{ "name": "AshuLab/my-repo" }],
  "profiles": {
    "author-bot": { "kind": "forge", "agent": "<forge-agent-1>" },
    "reviewer-bot": { "kind": "forge", "agent": "<forge-agent-2>" }
  },
  "orchestratorProfile": "author-bot",
  "agents": {
    "author": { "profile": "author-bot", "provider": "claude", "model": "<model>" },
    "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "<model>" }
  }
}
```

The accounts the roles name (`claude` and `codex` here) are declared in `providers.json`, next to this file in the Carrier folder; see [AI providers](#ai-providers).

## Fields

| Field | Required | Default | Meaning |
|-------|----------|---------|---------|
| `repos` | yes, may be `[]` | | Repos to watch. Each is `{ "name": "owner/name", "agents"?: ... }`. With none, Carrier runs and watches nothing until one is added (in the file, or in the app's Settings, Repos). |
| `profiles` | yes | | The GitHub identities you can use, by name (below). |
| `orchestratorProfile` | no | the author's profile | Profile used to read issues and PRs and to change labels. Left out, it is `agents.author.profile`; set it only when the author's profile cannot read a repo, for instance a repo of another owner where the author's bot is not installed. `carrier init` asks for it, before the author and the reviewer. You can also choose it in the Mac app, under GitHub identity in Settings > Engine (the default takes the key out of the file). When a repo's read check fails with a 404, the doctor's fix names this key as the second way out, besides installing the App. |
| `agents.author` / `agents.reviewer` | yes | | `{ profile, provider, model, persona? }` for each role: the GitHub identity it acts as, the AI provider it connects through, and the model it uses. |
| `agents.leadReviewer` | no | none | Optional technical lead role `{ profile, provider, model, persona? }` (configuration setup; reserved for upcoming lead reviewer gating in the Carrier flow). |
| `agents.<role>.effort` | no | none | How hard the model thinks: one of `low`, `medium`, `high`, `xhigh` or `max`, in the global role and in a repo's override of it. Passed as `--effort` to Claude and Antigravity and as `-c model_reasoning_effort=<level>` to Codex, in every run and resume. Without it nothing is passed and the CLI uses its own. Anything else is refused naming the key. |
| `agents.<role>.persona` | no | none | `{ name?, prompt? }`: who the agent of that role is. `name` is one line of at most 40 characters; `prompt` is text of at most 4000 characters, given to the agent as you wrote it. See [Personas](#personas). |
| `failover` | no | none | `{ triggers?, roles? }`: for each role, a list of steps it moves through when its credits run out or service fails. See [Failover](#failover). |
| `pollIntervalMinutes` | no | `5` | How often it looks for ready epics. |
| `labels` | no | the `solve:epic…` names below | The label of each role, the same in every repo: `{ epic, ready, running, readyForTest, needsHuman }`, each optional. A name is one line without commas, at most 50 characters, and no two roles, stages or kinds of stop may share one (GitHub ignores case, so `Solve:Epic` is `solve:epic`): a config that repeats one is refused naming the second. See [Labels](#labels). |
| `finishedWindowDays` | no | `15` | Days a merged or cancelled epic stays in the snapshot after it ends, a whole number from 1 to 30 (30 is the retention purge). |
| `logLevel` | no | `info` | `debug`, `info`, `warn` or `error`. |
| `limits.maxConcurrentEpics` | no | `3` | Epics running at the same time. |
| `limits.maxReviews` | no | `5` | Review rounds before the epic goes to `needs-human`. |
| `limits.maxExecutionRetries` | no | `3` | Retries after a technical failure of an agent execution. |
| `limits.maxExecutionHours` | no | `4` | Time limit of one agent execution, or `"unlimited"`. `0` does not mean infinite. |
| `limits.githubCallTimeoutSeconds` | no | `30` | Limit for each short call to GitHub or Forge. |

## Labels

Carrier reads and writes five labels on an epic's issue, each named by a role in `labels`:

| Role | Default | Who writes it | What it means |
| --- | --- | --- | --- |
| `epic` | `solve:epic` | Solve, a person | Marks an epic. Carrier reads the open ones for the slice progress and the title. |
| `ready` | `solve:epic:ready` | Solve, a person | Queues the epic. Carrier takes it off when the epic starts and never leaves it on a stopped one, so a person puts it back to restart: pick a label that is not part of your own workflow. |
| `running` | `solve:epic:running` | Carrier | An orchestrator is building the epic. |
| `readyForTest` | `solve:epic:ready-for-test` | Carrier | Reviewed on the current head; a person tests and merges. |
| `needsHuman` | `solve:epic:needs-human` | Carrier | Stopped for a person, with the reason in the app. |

Two more groups are off until you name them, so a Carrier that does not name them writes exactly what it wrote before:

- `labels.stages`: `{ ship, review, fix }`, each optional. While an epic runs, the issue carries the label of its stage beside `running`, and the next stage replaces it.
- `labels.reasons`: one optional label per kind of stop, `review_limit`, `agent_needs_human`, `retries_exhausted`, `timeout`, `auth`, `workspace`, `pr_invalid` and `usage_limit`. While an epic waits for a person, the issue carries the label of its kind beside `needsHuman`.

A stage label costs one more write to GitHub at each stage change, which is why it is opt-in. Carrier creates these labels in a repo like the three it owns (a stage in light blue, a stop in yellow), and removes them from the issue when the epic moves on or ends.

The first time Carrier writes a label on a repo it creates the three it owns that the repo lacks, with their colour and description; it never creates `epic` or `ready` (Solve creates the defaults), and `carrier doctor` reports one of them missing in a repo, saying you create it when its name is not the default.
A change applies to the next check after a reload: an epic already queued stays queued (and is cancelled at its start if its issue lost the `ready` label then in force), and an issue that carries the old name of a status label keeps it, because Carrier only removes the names it has now.

## AI providers

An AI provider represents an account/login setup for an AI harness (e.g. Claude Code with a specific `configDir`, Antigravity, or Codex). A provider defines the account and installation independently of the model.

The accounts live in `providers.json` in the Carrier folder (`~/.carrier`, or `CARRIER_HOME`), next to `engine.json` and wherever `--config` points: [ADR 0020](adr/0020-accounts-live-in-a-file-both-processes-read.md). It is optional (without it there is one account per harness, see below), it is read when the engine starts and again on a [reload](#changing-the-config-while-carrier-runs), and a file that does not match stops the start, or is refused by the reload, with the key named. An `engine.json` that still has `providers` is refused and told to move it here.

```json
{
  "providers": {
    "claude-work": { "harness": "claude", "configDir": "~/.claude-work", "displayName": "Work" },
    "claude-personal": { "harness": "claude", "configDir": "~/.claude" },
    "codex": { "harness": "codex" },
    "agy": { "harness": "agy" }
  }
}
```

The file has three keys, `providers` and the two of [Text generators](#text-generators), and no other.

| Field of a provider | Required | Meaning |
|----------------------|----------|---------|
| (the key) | | The provider's name: a lowercase word, with letters, digits and hyphens, starting with a letter, up to 40 characters. |
| `harness` | yes | The agent CLI that runs it: `claude` (Claude Code), `codex` or `agy` (Antigravity). |
| `displayName` | no | What an app shows instead of the key: one line, trimmed, 1 to 60 characters. |
| `label` | no | A short tag an app shows beside the account: one line, trimmed, 1 to 12 characters. |
| `icon` | no | The icon an app draws for the account: `bolt`, `star`, `briefcase`, `person`, `people`, `code`, `flask`, `leaf`, `moon`, `heart`, `cube`, `letter`, `flame`, `sparkles`, `paperplane`, `globe`, `shield`, `key`, `house`, `book`, `hammer`, `cloud` or `bell`. Without it, the tool's own mark. |
| `color` | no | The color an app gives the account: `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `mint`, `cyan`, `indigo`, `brown` or `gray`. Without it, none. |
| `model` | no | Optional default model for this provider connection, used when a failover step names this provider without a model or when inherited by a role. |
| `provider` | no | Who serves the model: `lmstudio` or `ollama` for a local server; without it, the harness's own cloud. See [Local models](#local-models). Not for `agy`. |
| `configDir` | no | The harness's config folder, which holds its login: `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. It must be an absolute path once a leading `~` is expanded. Without it the agent inherits the environment of the process that started Carrier. Not for `agy`. |
| `command` | no | The binary to run, instead of looking the harness's name up on the `PATH`. An absolute path, or one that starts with `~/`. `carrier doctor` fails the account when it does not exist or does not run (`--version`). |
| `autoCompact` | no | When the CLI compacts the conversation. Claude: `"auto"` or a token count from 100000 to 1000000, passed as `--autocompact`. Codex: a positive token count, passed as `-c model_auto_compact_token_limit=N`. Not for `agy`. |
| `idleCompaction` | no | Claude only: a boolean passed on every run as `--settings '{"idleCompaction":…}'`, so the `settings.json` of the person changes in nothing. Absent passes nothing. Not for Codex or `agy`. |
| `launchArgs` | no | A list of strings appended to the arguments Carrier passes, for example `["--chrome"]`. An empty entry is refused, and so are the flags Carrier sets itself, below. Not for `agy`. |

A flag in `launchArgs` is judged by its name, so `--model=x` and `--model x` are the same. These are refused when the file is read, naming the key, because repeating them would change the permission mode or break the parsing of events:

- Claude: `-p`, `--model`, `--permission-mode`, `--output-format`, `--resume`, `--name`, `--add-dir`, `--settings`, `--autocompact`.
- Codex: `--model`, `--json`, `--dangerously-bypass-approvals-and-sandbox`, `--sandbox`, and the key of a `-c` or `--config` pair, in each form the CLI takes (`-c k=v`, `-ck=v`, `--config k=v`, `--config=k=v`), when it is `model_provider`, `carrier_marker` or `model_auto_compact_token_limit`.

The file holds no secret; a log names an account and a flag, never the value of an argument.

Without `providers.json` there is one account per harness, named after it: `claude`, `codex` and `agy`, each with this Mac's own login (no `configDir`). A role may name them. A file that has a `providers` key replaces them: only the accounts it lists exist.

### Text generators

A text generator is a model that turns text into text with no tools: a local server, LM Studio or Ollama, and one of its models.
It is declared in `providers.json` next to the accounts, and one of them is named as the one in use:

```json
{
  "textGenerators": {
    "local": { "kind": "ollama", "model": "qwen3:8b" },
    "studio": { "kind": "lmstudio", "model": "google/gemma-4-12b" }
  },
  "textGenerator": "local"
}
```

| Key | Required | Meaning |
|-----|----------|---------|
| `textGenerators` | no | The generators by name, each `{ "kind", "model" }`. The name follows the same rule as an account's. Without it, `{}`. |
| `textGenerators.<name>.kind` | yes | The server: `lmstudio` or `ollama`, the local ones on this Mac. |
| `textGenerators.<name>.model` | yes | The model the server runs: one trimmed, non-empty string. |
| `textGenerator` | no | The name of the generator in use. It must be a key of `textGenerators`, so a name with none declared, or `""`, is refused. Without it there is no generator. |

An unknown key inside a generator is refused.
The engine reads these keys with the same schema as the chat host and ignores them; the chat host reports the one in use in its `providers` reply.
A file that does not match stops the engine's start, is refused by `carrier reload` and is answered by the host as a problem, each naming the key.

The strict schema is why the host's hello lists `textGenerators`: a `carrier` that does not list it refuses a file with these keys, so the Mac app writes them only while it is there.

The chat host calls the generator in use to write session titles, in three cases:

- Automatically, in the background, when the first turn of a session ends well: the title comes from the first message and the first reply, and the person never waits for it.
  A session started by a delegation (a child) keeps its own title.
  An automatic title only replaces a first-line title, so a title the person set with Rename is never replaced and a generated title is not rewritten by the next turn.
  When the call fails, the title stays as it was, the cause goes to the log without any notice in the session, and the session tries again at the end of its next turn while its title is still the first line.
- When the person asks for one session (Regenerate title in a session's menu, the `regenerateTitle` request): the new title replaces whatever the title is, a renamed one included, and the request answers it.
- For the earlier sessions (the `regenerateTitles` request, "Titles of earlier sessions" in Providers): in the background and one session at a time, for every session of the list and of the archive whose title is still the first line, children left out.
  It answers at once how many sessions it will do; the titles show in the lists as they land.

Each call sends the server a fixed system message and the session's first message and first reply, each cut to 2,000 characters, with no tools, to `/v1/chat/completions` on the server's default port (LM Studio 1234, Ollama 11434).
It reads `providers.json` at each use, so a change needs no restart, and it makes one call at a time, each with a limit of 30 seconds.
A call can fail: the server is not running, the model is missing, there is no answer in 30 seconds, or the answer is empty.
Then the title stays as it was and the cause is in `<folder>/chat/logs/chat-host.log`.
`regenerateTitle` is refused, with words that say to choose a generator in Providers or what failed.
`regenerateTitles` is refused only when no generator is chosen (or `providers.json` is invalid); once it has started, a session whose call fails is skipped, logged, and the rest go on.

`carrier init` does not ask which providers to use: it looks for the agent CLIs on the Mac (their real binary, never a wrapper under `~/.paradev` or `~/.superset`), shows where each is with its version and whether it is signed in, and writes one account per CLI it found, named after it. It says how many accounts it added, and then asks only for extra accounts (another login of the same CLI, or one on a local server), with Enter meaning no. The accounts go to `providers.json` in the Carrier folder, even when `--out` puts the config elsewhere, and the recap says so. The flags that declare an account (`--author-provider` and the like) add it to the file, and `--yes` writes it without asking. When it edits an existing setup it starts from the accounts already in that file instead. When assigning roles, each role points at a declared account (a `provider` in the file) and specifies its model.

The questions about the roles follow the schema. The first asks who Carrier reads GitHub as, the orchestrator's identity (a bot of Agent Forge or your `gh` login), and writes it as `orchestratorProfile`; with `--yes`, or with both `--author-profile` and `--reviewer-profile`, nothing asks and it is the author's identity. For each role: its identity (a bot of Agent Forge or your `gh` login; the same one for the author and the reviewer is accepted, and the recap says the signature will show it, as no question or flag about sharing exists), its provider, its model and its `effort`. With two or more accounts it then asks, for each role, whether to turn failover on (Enter says no) and for up to two steps, each a provider and a model; a step that repeats another or is the role's own provider and model is refused. The flags `--author-effort`, `--reviewer-effort` and `--lead-reviewer-effort` take one of the five levels, and `--yes` with them writes the same file without asking. Editing an existing config starts each role from its effort and asks whether to keep the failover steps it has; saying no asks for them again. Before saving, the recap lets you change an answer, which asks everything again from the same answers.

## Agents and roles

Each role in `agents` (`author`, `reviewer`, and optional `leadReviewer`) specifies its GitHub identity (`profile`), its AI connection (`provider`), the `model` it runs on, an optional `effort`, and an optional `persona`.

```json
"agents": {
  "author": { "profile": "author-bot", "provider": "claude-work", "model": "sonnet", "effort": "high" },
  "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "gpt-5.3-codex" },
  "leadReviewer": { "profile": "reviewer-bot", "provider": "claude-personal", "model": "opus" }
}
```

- For Claude models, prefer an alias (`sonnet`, `opus`, ...): the CLI resolves it to the latest model, so it does not go stale.
- Codex has no aliases: use an id from `codex`'s own list.
- For Antigravity, use an id from `agy models` (`carrier init` offers all of them).

### Starting an epic and restarting it

An epic starts at once on its roles: nothing waits for a provider to be chosen, however many accounts are declared. The account each role ran on is recorded, because resuming its session and moving the role on failover need it.

`carrier restart <owner/name>#<issue>` of a stopped epic is the one place a provider is chosen: it offers every declared account to each role, with no timer, and `--author` and `--reviewer` name one without asking.

A config with `limits.optionChoiceSeconds`, or a `providers.json` account with `enabled`, is refused naming the key: an epic starts at once on its roles, so there is no choice to wait for or to hold back accounts from. Delete the key.

### Failover

A role has failover when its list of steps in `failover.roles` is not empty. There is no global switch and no default list: a missing or empty list (`[]`) means that role stops when its login runs out.

A step is a provider, an account of `providers.json`, and optionally the model to run there and its `effort` (one of the five levels). Without a model the step uses the account's `model`, then the harness's default; without an `effort` it keeps the one the role was running with (the role's own for the first step).

```jsonc
"failover": {
  // Events that trigger failover (defaults to all three):
  "triggers": ["usage_limit", "rate_limit", "service_down"],

  "roles": {
    "author": [{ "provider": "claude-personal", "model": "sonnet", "effort": "medium" }, { "provider": "codex" }],
    "reviewer": [{ "provider": "claude-personal", "model": "haiku" }],
    "leadReviewer": []
  }
}
```

The old shape is refused naming this one: `failover.enabled` and `failover.default` are gone, and a step written as a name (`["codex"]`) must be `{ "provider": "codex" }`. Nothing is migrated.

#### Triggers
- `usage_limit`: The agent CLI or API ran out of credits/billing quota.
- `rate_limit`: Persistent HTTP 429 rate limit that exceeds normal backoff retry.
- `service_down`: Provider or local server unavailable (`ECONNREFUSED`, 5xx, or CLI connection failure).

#### Fallback resolution
When a role experiences a failure matching `triggers`, and its list has steps:
1. The role moves to the next step not already tried in this epic (a step is tried by its provider and model, the role's own included). The stage restarts as a fresh session in the epic's worktree with its context rebuilt from SQLite and GitHub, on that step's model, spending no retry.
2. The epic's events record an `option_switched` with the provider and model it moved from and to (`from`, `fromModel`, `to`, `toModel`).
3. If no step is left, the epic stops in `needs-human` naming each provider and model that ran out.

Every step's `provider` must be declared in `providers.json`; the error names the key. A step with an empty provider, a step repeated in its list, and a step equal to the role's own provider and model are refused naming their position.

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

There is no `identities` key. An epic is **shared** when its author and reviewer resolve to the same account, and **separate** when they differ; nothing in the file says which, and the config and `carrier doctor` never require them to differ. Two names for the same bot and your own `gh` login on both roles are shared; two different bots, or a bot and your login, are separate. A shared epic's agents sign what they post (`🤖 <role> via Carrier`), because everything then comes from one account, and both roles act with everything that login's token can do. A config that still has `identities` is refused: delete the key. `carrier doctor` still checks that each profile can get a token and read each repo. See [ADR 0011](adr/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md) and [ADR 0021](adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md).

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

Profile names used in an override must exist in `profiles`, and provider names in `providers.json`.

## Chat configuration

The chat host and `carrier chat` start from the Carrier folder alone (`~/.carrier`, or `CARRIER_HOME`) and read no engine config. The chat reads `providers.json` in the same folder for its accounts, and nothing else of the engine's. Everything the chat owns is in `<folder>/chat/` (`state/`, `logs/`, `projects/`, `worktrees/`), and its settings are in the optional `<folder>/chat.json`. Every key is optional and so is the file; with neither, the chat uses the defaults below. Unknown keys are errors. A file that is not valid JSON or does not match makes `carrier chat-host` exit with a message that names the file and the key, and the host does not start.

```json
{
  "agents": {
    "claude": { "account": "claude" },
    "claude-opus": { "account": "claude-work", "model": "opus", "options": { "permissionMode": "plan" } },
    "codex": { "account": "codex" }
  },
  "projectsFolder": "~/Projects/carrier",
  "githubCallTimeoutSeconds": 30,
  "logLevel": "info",
  "archiveAfterDays": 15,
  "deleteAfterDays": 30,
  "worktreeStart": "remote",
  "idleCloseMinutes": 10,
  "worktreeCleanup": { "afterPrMerged": true, "afterInactiveDays": 14 }
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `agents` | `claude` and `codex` | The agents a chat can start with, by name, in the order written, and only those (`{}` means none). `carrier chat` without `--agent` uses the first. See [Chat agents](#chat-agents). Read when the host starts (the accounts they name are read from `providers.json` at each request). |
| `projectsFolder` | `<folder>/chat/projects` | Where the host puts the repositories it clones (`<owner>/<repo>` inside it). An absolute path, or one starting with `~/`. It may not lie inside `<folder>/engine/` or the chat's own `state/`, `logs/` or `worktrees/`. Read at each request, so a change applies to the next clone with no restart. See [Projects folder](#projects-folder). |
| `githubCallTimeoutSeconds` | `30` | A positive whole number: how long a call to GitHub (the repository list, the login) may take. Read when the host starts. |
| `logLevel` | `info` | `debug`, `info`, `warn` or `error`. Read when the host starts. |
| `archiveAfterDays` | `15` | Days of no activity after which a session is archived: a positive whole number, or `"never"`. A wrong value (`0`, a negative, a fraction, a text such as `"15"`, `null`) stops the host naming the key. See [The session clock](#the-session-clock). |
| `deleteAfterDays` | `30` | Days of no activity after which an archived session is deleted, with its worktree and branch: a positive whole number, or `"never"`. It must be greater than `archiveAfterDays` when both are numbers (the error is reported on `deleteAfterDays`); with `"never"` on either side there is no such rule. Same checks as `archiveAfterDays`. See [The session clock](#the-session-clock). |
| `worktreeStart` | `remote` | Where a new session's worktree is cut from when its plan does not say: `remote` is `origin/<branch>` as of the last fetch, `local` is the local branch. Any other value or type stops the host naming the key. A branch that exists only locally is cut from the local branch either way, and a branch that already carries `origin/` is cut from that ref. A plan's own `worktree.startFrom` wins over it. Read at each plan, so a change applies to the next session with no restart, and a file that is wrong keeps the last value that was good. See [ADR 0037](adr/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md). |
| `idleCloseMinutes` | `10` | Minutes after which the host closes the agent of an idle session that no request names (reading its events, sending to it and changing its options name it; listing the sessions does not): `10`, `30` or `60`. The session stays in the list as asleep and wakes where it left off with the next message; one that works, waits for an approval or waits for a task it started is never closed for being idle. Any other value or type stops the host naming the key. The host takes a change of the file with no restart, at the next listing of the sessions (the app lists them every few seconds) or hourly clock pass, and uses it from the next time a session is named; a session already waiting keeps the time it was armed with until then. |
| `worktreeCleanup` | `afterPrMerged: true`, `afterInactiveDays: 14` | When the clock removes the folder of a session's worktree and keeps its branch. The whole folder goes, including every file git ignores (build output and dependencies, but also a local `.env` or config you kept inside the worktree); a folder with uncommitted or untracked files, or whose HEAD is detached, is kept. The rules: `afterPrMerged` (`true` or `false`) once the session's pull request is merged, `afterInactiveDays` (a positive whole number or `"never"`, same checks as `archiveAfterDays`) once the session is archived and has had no activity for that many days (the clock of `archiveAfterDays` and `deleteAfterDays`: it counts from the last activity, not from the archiving). To turn it all off, set `"afterPrMerged": false` and `"afterInactiveDays": "never"`. See [ADR 0042](adr/0042-a-session-worktree-folder-is-cleaned-by-default.md) and [The session clock](#the-session-clock). |

A session never works inside `<folder>/engine/`, nor through a symlink into it. The engine's config has no `chat` section: it rejects one like any unknown key.

### The session clock

The chat host applies the two ages in one pass when it starts and again every hour while it runs, never while it is stopped: a host that was off for 40 days catches up on its next start.

- **Counted from the last activity.** Both ages count from the session's last message or event, not from when it was archived. Restoring a session from the archive counts as activity, so it is not archived again at once.
- **`"never"`.** `archiveAfterDays: "never"` archives nothing, and with it nothing is deleted by the clock, whatever `deleteAfterDays` says. `deleteAfterDays: "never"` archives but never deletes.
- **What the clock skips.** A session that is working, waiting for an approval or open in the host is left alone and looked at again on the next pass.
- **What an automatic delete spares.** An archived session whose worktree has uncommitted changes or commits that exist nowhere else is not deleted: it stays archived and the Archive page shows it as kept, until a later pass finds the worktree clean (and deletes it) or you restore or delete it yourself. A worktree that git cannot read is left alone, the failure is logged and the next pass tries again. A session in your own folder has no worktree and is deleted without that check. Archiving loses nothing and has no such check.
- **Cleaning up a worktree's folder.** With `worktreeCleanup` on, which is the default (a merged pull request, or archived and untouched for 14 days), the same pass removes only the folder of a session's worktree, keeping the session, its branch and its commits, pushed or not. The whole folder goes, including every file git ignores: build output and dependencies, but also a local `.env` or config you kept inside the worktree, which is not in the branch and does not come back. Copy such a file out first, turn the cleanup off, or bring it back with a `newWorktree` action of the project (they run again each time the folder comes back, so `cp "$CARRIER_PROJECT/.env" .` works; an action with no `onFail` only warns when it fails, and `"onFail": "stop"` refuses the open and goes on from that action the next time). It counts from the last activity as the two ages do, so a session archived by hand is cleaned once it has been untouched for 14 days, whatever its pull request says, and one the clock archives (after 15) is cleaned in the same pass. To keep every folder, set `"afterPrMerged": false` and `"afterInactiveDays": "never"`. It never does it for a session that is working, waiting or open, nor for a worktree with uncommitted or untracked (not ignored) files, nor one whose HEAD is detached or mid-rebase (a commit made there is held by no branch; a HEAD on another branch is cleaned, as that branch stays in the clone), nor one with an initialised submodule (it keeps its folder, edited or not), files marked `--assume-unchanged` or `--skip-worktree`, or a commit made detached and then left behind by switching back (only the worktree's own reflog holds it), which are skipped and looked at again on the next pass. The removal can take up to three minutes, and a session resumed meanwhile waits for it. A folder git cannot read (a removal killed halfway can leave one) is kept and logged on every pass: [Troubleshooting](troubleshooting.md#a-sessions-worktree-folder-is-gone) has the manual fix. The next message to that session brings the folder back on its branch first, without its dependencies until something installs them; if the branch is gone, the host refuses in words.
- **What is never deleted.** The clones in the [projects folder](#projects-folder) and anything else in it.
- **Changing it.** Edit the two keys here, or in the macOS app under Settings, Sessions: each age is a number of days or Never, and it is saved as you change it, and the page says in dates when a session left alone from today is archived and deleted. The host reads the file at each pass, so no restart is needed; if the file is wrong at that moment the pass is skipped and the log says why. The Archive page shows when each archived session will go ("Deletes in N days", "Deletes soon" once due) or "Kept because its worktree has unsaved work". If a session is kept, see [Troubleshooting](troubleshooting.md#an-archived-session-is-kept-and-not-deleted).

The reasons are in [ADR 0019](adr/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md).

## Chat agents

A chat (`carrier chat`) starts with one of the agents in `agents`. Each names an [account](#ai-providers) of `providers.json`, and a chat on it runs that account's harness with its login (`configDir`) and its binary (`command`), with the provider's defaults unless the agent says otherwise. Without `agents` in `chat.json` the agents are the accounts of `providers.json` except Antigravity's, each named as its account (so `claude-work` is an agent as soon as it is an account, with no restart); without `providers.json` those are `claude` and `codex`.

A chat applies every key of its account that starts the CLI: `configDir` and `command`, and also `autoCompact`, `idleCompaction` and `launchArgs`, as the engine does. For Claude they reach the SDK as `--autocompact`, `--settings '{"idleCompaction":…}'` and the launch arguments; for Codex, `app-server` starts with `-c model_auto_compact_token_limit=N` and then the launch arguments (a real `codex app-server` honours that pair, which the gated integration test of the Codex adapter checks). An account that sets none of them starts the CLI as before. In a chat, a `launchArgs` entry must be a long flag (`--chrome`, `--max-turns 5` or `--max-turns=5`) for Claude; any other entry stops the session from opening, naming its place and not its text. `displayName`, `label`, `icon`, `color` and `enabled` mean nothing to a chat: any declared account may be named by an agent.

`providers.json` is read each time the host opens a session or answers the list of agents, so an edit reaches the next chat with no restart, and a file that does not match stops the request with the key named. A session on an account that is not in `providers.json`, or that is Antigravity's (a chat does not offer it), is refused naming the account. The list of agents says, for each one, the account it runs on (`account`) and whether that account's binary is found.

| Field | Required | Meaning |
|-------|----------|---------|
| the key | yes | The agent's name: lowercase letters, digits and hyphens, starting with a letter. |
| `account` | yes | The name of an account in `providers.json`, which sets the harness, the login and the binary. A `claude` or `codex` account; Antigravity is not offered in a chat. `harness` and `command` are no longer keys of an agent: they are refused, naming the key. |
| `model` | no | The model the provider starts with. Not empty. |
| `options` | no | Default options of the provider, by the provider's own option id. An option the provider does not list is refused when the session opens. |

## Projects

The projects you work on live in `projects.json` in the Carrier folder (`~/.carrier`, or `CARRIER_HOME`), next to `engine.json`, `chat.json` and `providers.json`: [ADR 0041](adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md).
The app and the chat host both read and write it, each reading the file again just before it writes, so you can edit it by hand while Carrier runs.
It is optional: without it there are no projects.
A file that does not match is reported with the field named and neither the app nor the host writes over it.
The host reads it as no projects until you fix it.

```json
{
  "projects": [
    { "path": "/Users/ana/notes", "origin": "added" },
    {
      "path": "~/work/carrier",
      "name": "Carrier",
      "origin": "cloned",
      "pinned": true,
      "hidden": false,
      "tags": ["work", "swift"],
      "icon": { "color": "teal", "mark": "bolt" },
      "defaults": { "agent": "claude", "workIn": "worktree", "baseBranch": "main" },
      "actions": [{ "name": "Install", "command": "pnpm install", "when": "newWorktree", "on": true, "onFail": "warn" }]
    }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `path` | yes | The project's folder, absolute or starting with `~/`. It is the project's identity: two projects cannot share it. |
| `name` | no | What the project is called; the folder's name when absent. Not blank. |
| `origin` | yes | How it came to be: `cloned`, `created` or `added`. |
| `pinned`, `hidden` | no | Booleans. |
| `tags` | no | A list of words, each trimmed, in lower case and listed once. |
| `icon` | no | `color`, `mark` and `image` (a file name in the app's project-icons folder), each a non-empty string. |
| `defaults` | no | What a new session starts with: `agent`, `workIn` (`baseFolder` or `worktree`) and `baseBranch`. Absent means the same as everywhere. |
| `actions` | no | Commands the project runs: `name` and `command` (not blank), `when` (`newWorktree` or `afterClone`), `on` (a boolean) and `onFail` (`warn` or `stop`). |

The file is strict: an unknown key, a field of the wrong type, a repeated path, an empty path, a blank name or command and a tag that is not trimmed and in lower case are each refused, naming the field (`projects.1.name`).
What can be worked out is never stored: the remote, the branch, the worktrees and their size.

## Projects folder

The chat host clones a GitHub repository for a session when the first message is sent (the `clone` step of a plan, or the older `cloneRepo` request).
It goes to `<projects folder>/<owner>/<repo>`; one already there (a `.git` whose `origin` is that repository) is fetched instead, and anything else at that path stops the request and is left untouched.
The clone and the fetch use the token of your active `gh` login, handed to git in its environment, so `gh` must be installed and signed in.
Each git command has ten minutes.
A new project (the `project` step of a plan the host prepares when the first message is sent, the older `createProject` request, or `newProject` from Settings, which also registers it in `projects.json` with origin `created` and may go under another folder for that one project) is a folder at `<projects folder>/local/<name>` with `git init -b main`; the name is a plain folder name (letters, digits, `_`, `.` and `-`, at most a hundred, not starting with a dot or a dash), one that is taken is refused and nothing is changed.
Its branches are listed, without the repository being on your Mac, for the draft's worktree choice (the `repoBranches` request, with the same `gh` login).
The same host lists your repositories for the app's "My GitHub repositories" step (the `githubRepos` request, thirty a page, with the same `gh` login): every repository that login can read, as owner, collaborator or organisation member, archived and disabled ones left out; it needs no config.
The Projects page of the app clones into the same folder (or into a parent chosen for that one clone), in the background, and registers the folder in `projects.json` when it ends; it never adds the repository to `engine.json`'s `repos`.
Carrier never deletes anything in the folder, except the half-made clone or project of a request that failed or was cancelled.

## Things that are checked

- Every profile named anywhere is declared in `profiles`, and every provider named anywhere in `providers.json`.
- Every `provider` of a step in `failover.roles` is declared in `providers.json`, and a step appears once per list and is not the role's own provider and model.
- Provider names are lowercase words, a `configDir` is absolute after `~` is expanded, and a provider has no field this page does not list.
- Repo names are `owner/name`, and no two repos share the same folder name (Solve's worktree paths have no owner).
- A `provider` (local model server) is only accepted for a harness that can use it (Claude Code and Codex; not Antigravity), and so is a `configDir`.
- A `command` is absolute after `~` is expanded; `autoCompact` and `idleCompaction` are accepted only where the table says, `autoCompact` in its range; `launchArgs` is a list of non-empty strings that repeats none of the flags above.
- The effective configuration of an epic is saved, without credentials, when it starts and kept when it resumes, even if you change the file in between.

## Local models

A provider defines the **harness** (the CLI that runs the loop and the tools) and where it connects. By default the connection is the harness's own cloud; it can also be a local model server. An agent can use a model served by [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com) on this machine instead of a cloud model. The harness is still Claude Code or Codex, which talk to the local server:

```json
// providers.json
{ "providers": { "local": { "harness": "codex", "provider": "lmstudio" } } }
// engine.json
"agents": {
  "reviewer": { "profile": "reviewer-bot", "provider": "local", "model": "google/gemma-4-12b" }
}
```

- **Codex** gets `-c model_provider="lmstudio"` (or `ollama`); **Claude Code** gets `ANTHROPIC_BASE_URL` pointing at the server (and a placeholder token, never your real API key).
- The servers are expected on their default ports (LM Studio `1234`, Ollama `11434`). Start the server and download the model first; `carrier doctor` checks both, and `carrier init` lists the models the running server has.
- Antigravity (`agy`) cannot be pointed at a local server: `provider` on an entry with `harness: "agy"` is rejected. Its models come from `agy models`, which `carrier init` lists.
- A per-repo override points a role at another provider, so to go back to a cloud model in one repo, override `provider` with one that has no local `provider`.
- Expect it to be **slow** (a trivial prompt took 15 to 140 s on a laptop, mostly loading the model and the CLI's long system prompt) and **weaker** on long agentic work. `ship` and a full review make hundreds of tool calls; small local models often lose the thread. A local reviewer is the realistic use; test it on a throwaway epic before trusting it.
