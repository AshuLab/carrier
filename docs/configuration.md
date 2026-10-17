# Configuration

`carrier init` writes this file for you, by default to `~/.carrier/config.json` (global, one per user; `carrier` and `carrier doctor` read it when you do not pass `--config`); this page is the reference for editing it by hand. `carrier doctor --config <file>` checks it and `carrier schema` prints its JSON Schema (add it to your editor for completion).

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
| `agents.author` / `agents.reviewer` | yes | | `{ profile, provider, model }` for each role. `provider` is `claude` or `codex`. For Claude prefer an alias (`sonnet`, `opus`, ...): the CLI resolves it to the latest model, so it does not go stale. Codex has no aliases: use an id from `codex`'s own list (`carrier init` offers it). |
| `root` | no | `~/.solve` | The folder shared with Solve: `repos/`, `worktrees/`, `reviews/`, `orchestrator/`. |
| `pollIntervalMinutes` | no | `5` | How often it looks for ready epics. |
| `logLevel` | no | `info` | `debug`, `info`, `warn` or `error`. |
| `limits.maxConcurrentEpics` | no | `3` | Epics running at the same time. |
| `limits.maxReviews` | no | `5` | Review rounds before the epic goes to `needs-human`. |
| `limits.maxExecutionRetries` | no | `3` | Retries after a technical failure of an agent execution. |
| `limits.maxExecutionHours` | no | `4` | Time limit of one agent execution, or `"unlimited"`. `0` does not mean infinite. |
| `limits.githubCallTimeoutSeconds` | no | `30` | Limit for each short call to GitHub or Forge. |

## Profiles

A profile names a GitHub identity. There are two kinds and neither holds a secret:

- `{ "kind": "forge", "agent": "<name in your Agent Forge registry>" }`: a bot (a GitHub App) through [Agent Forge](https://github.com/AshuLab/agent-forge). Each run gets a short-lived token with the minimum scope.
- `{ "kind": "gh" }`: your own `gh` login.

The author and the reviewer need **different identities**, so that the reviewer's comments and approvals are not the author's own. The config rejects the same profile name for both, and `carrier doctor` also catches two names pointing to the same bot or both being `gh`.

## Per-repo overrides

A repo inherits every value from the global `agents` and replaces only what it names:

```json
{ "name": "AshuLab/big-repo", "agents": { "reviewer": { "model": "<other-model>" }, "author": { "profile": "other-bot" } } }
```

Profile names used in an override must exist in `profiles`. The author and the reviewer must still differ after the override.

## Things that are checked

- Every profile named anywhere is declared in `profiles`.
- Repo names are `owner/name`, and no two repos share the same folder name (Solve's worktree paths have no owner).
- The effective configuration of an epic is saved, without credentials, when it starts and kept when it resumes, even if you change the file in between.
