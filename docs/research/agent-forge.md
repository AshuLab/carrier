# Agent Forge as an identity provider (spike #7)

Date: 2026-10-15 (the UTC timestamps below are already 2026-10-16). Environment: macOS, Node v25.6.0, `gh` 2.102.0. Only `agent-forge` and `gh` were run; no repo code was run.

Result: all acceptance criteria have evidence, with one declared caveat in [What was not observed](#what-was-not-observed) (a truly revoked profile or an uninstalled installation: only the safe analogue was observed).

## Forge version used

```
$ agent-forge --version
0.8.0
```

Installed globally with pnpm (`@ashulab/agent-forge` 0.8.0). The earlier research used commit `8dee1b0` of the repo; this spike reads and runs the installed `dist/launcher.cjs` (0.8.0). Registered profiles (`agent-forge --list`): `artanis-agent` and `tassadar-agent`, two GitHub Apps installed on two accounts (`AshuLab`, `vemec`). `~/.config/agent-forge/agents.json` was not read (it contains paths to private keys); no token or key was printed, and the tokens below are redacted.

## How `gh` is invoked as a bot

```
agent-forge gh <agent> <gh args...>     # mints a fresh token and runs gh with GH_TOKEN/GITHUB_TOKEN
agent-forge token --agent <agent>          # prints only the token (stdout, no newline)
```

Observed rules:

- It must be invoked with separate argv (`execFile`, `shell:false`). Passed as a single string (`agent-forge "gh x --version"`), Forge falls back to the interactive selector and exits with **exit 0** without doing anything.
- The **cwd matters**: the Apps are installed on 2 accounts; without an `installationId` in the registry, Forge resolves the installation from the cwd's `origin`. From `/tmp` it failed:
  ```
  exit=1  ■  GitHub App 4854138 is installed on 2 accounts (AshuLab, vemec). Launch from inside a repo under one of them.
  ```
  From a cwd with `origin` under `AshuLab/*` (the carrier worktree) it worked. The orchestrator must run Forge with `cwd` inside a clone of the right owner; a cwd under `vemec` would mint a token from the wrong installation.
- The token is scoped to the installation: `GET /installation/repositories` with each bot's token lists 8 `AshuLab` repos, including `AshuLab/agent-forge` (verified before acting).
- Minted permissions (stderr line `minted fresh token for ... · scope: ...`): `artanis-agent` = `issues:write contents:write pull_requests:write checks:read actions:read statuses:read metadata:read issue_fields:write issue_types:write organization_projects:write`; `tassadar-agent` = the same without the last three. Both can write issues, labels, content and PRs.
- Forge adds that line of its own to stderr, so `gh`'s stderr does not arrive clean.

## Evidence: `gh` as a bot in a test repo

Test repo: `AshuLab/agent-forge` (use explicitly authorized by Diego). Footprint: one issue, one temporary label and one branch; see [Footprints](#footprints-in-ashulabagent-forge).

Issue created by the author bot (`artanis-agent`):

```
$ agent-forge gh artanis-agent issue create --repo AshuLab/agent-forge --title "[carrier spike] forge identity test - safe to close" --body "..."
exit=0   stdout: https://github.com/AshuLab/agent-forge/issues/27
$ agent-forge gh artanis-agent issue view 27 --repo AshuLab/agent-forge --json author,...
author: "app/artanis-agent"  (is_bot: true)
```

Label and comment (the comment is made by the second bot, `tassadar-agent`):

```
$ agent-forge gh artanis-agent label create carrier-spike-tmp --repo AshuLab/agent-forge ...   exit=0
$ agent-forge gh tassadar-agent issue comment 27 --repo AshuLab/agent-forge --body "..."
exit=0   stdout: https://github.com/AshuLab/agent-forge/issues/27#issuecomment-6205875110
  (comment author: tassadar-agent)
```

Commit authored by the bot, on branch `spike/carrier-forge-20261016012437` (no PR; `main` stayed at `8dee1b0` before and after):

```
git clone --depth 1 https://github.com/AshuLab/agent-forge.git /tmp/spike/clone
git checkout -b spike/carrier-forge-20261016012437
GIT_AUTHOR_NAME="artanis-agent[bot]" GIT_AUTHOR_EMAIL="325794106+artanis-agent[bot]@users.noreply.github.com" \
GIT_COMMITTER_NAME=... GIT_COMMITTER_EMAIL=... git commit -m "chore: carrier spike forge identity test (throwaway)"
git -c credential.helper='!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f' push origin HEAD:refs/heads/spike/...
exit=0   * [new branch] HEAD -> spike/carrier-forge-20261016012437
$ gh api repos/AshuLab/agent-forge/commits/5957170...
author_login: artanis-agent[bot]  author_type: Bot  committer_login: artanis-agent[bot]  parent: 8dee1b0
```

(`GH_TOKEN` came from `agent-forge token --agent artanis-agent` and was never printed.)

Important finding: **the Forge token only grants push permission; it does not set authorship**. Forge exports `GIT_AUTHOR_*`/`GIT_COMMITTER_*` only in the interactive `launchAgent` mode; the `gh` and `token` subcommands do not. The runner must set, per execution, `GIT_AUTHOR_NAME=<agent>[bot]` and `GIT_AUTHOR_EMAIL=<botId>+<agent>[bot]@users.noreply.github.com` (and the committer ones) itself. Forge computes `botId` with `GET /users/<agent>[bot]` (a public endpoint; `artanis-agent[bot]` = 325794106); if the agent has `botName` or `botId` in the registry, it uses those. The commit is not signed (`verification.verified: false`).

## Evidence: orchestrator profile (`gh issue list --label ... --json ...` and label change)

Orchestrator = `artanis-agent` (the spec's `author-bot`):

```
$ agent-forge gh artanis-agent issue edit 27 --repo AshuLab/agent-forge --add-label carrier-spike-tmp      exit=0
$ agent-forge gh artanis-agent issue list --repo AshuLab/agent-forge --label carrier-spike-tmp --state all --json number,labels
  (+0 s)  []
  (+3 s)  [{"labels":["carrier-spike-tmp"],"number":27}]       (same at +8 s and +15 s)
$ agent-forge gh artanis-agent issue edit 27 --repo AshuLab/agent-forge --remove-label carrier-spike-tmp   exit=0
$ agent-forge gh artanis-agent issue list ... --label carrier-spike-tmp --json number
  (+5 s)  []
```

All with exit 0. Finding: `issue list --label` is **eventually consistent**: immediately after changing a label it returned the previous state (seen after adding and after removing); about 3 s later it was correct. The engine must not assume read-after-write on `list`; to confirm one's own change, read with `gh issue view --json labels` (it returned the correct state) or tolerate one polling cycle.

## Diego's personal profile: not supported by Forge

Forge has a single credentials path: GitHub App installation tokens (`generateGithubAppToken`: RS256 JWT with the App's key, then `POST /app/installations/{id}/access_tokens`). There is no "user" mode; no PAT or user OAuth. `--help` only offers `token --agent` and `gh <agent>`, both over Apps. So a personal identity cannot come from Forge and no attempt was made to act as Diego. The personal account is `gh`'s own login (`gh auth status`: account `vemec`, token in keyring) and is used by calling `gh` directly, without Forge. A bot token does not act as a person (authors appear as `app/...`) nor does it have a person's permissions (e.g. user projects).

## Token renewal

There is no cache or state: every `agent-forge token` and every `agent-forge gh` signs a new JWT and mints a new installation token (it lasts ~1 h according to GitHub). Renewing = calling again. Proof (tokens identified by the first 8 hex of the sha256, not by value):

```
token#1 exit 0 sha256[:8] 55eabaf5   token#2 exit 0 sha256[:8] 91a8de2e   different: true
GET /rate_limit with #1 -> exit 0     GET /rate_limit with #2 -> exit 0
DELETE /installation/token with #1 (revokes only that ephemeral token; not the App or the installation) -> 204
#1 dead: gh api /installation/repositories        -> exit 1  {"message":"Bad credentials","status":"401"}  gh: Bad credentials (HTTP 401)
#1 dead: gh issue list --repo AshuLab/agent-forge -> exit 1  HTTP 401: Bad credentials (https://api.github.com/graphql)
#2 still valid -> exit 0 (8 repos)
token#3 (renewal, with #1 already dead) exit 0 sha256[:8] 1379ab24 -> GET /installation/repositories exit 0 (8 repos)
```

The real hour was not waited out: expiry was simulated by revoking the token (GitHub answers 401 `Bad credentials` the same for an expired or a revoked token) and a new call returned a valid token. Tokens #2, #3 and another test one were revoked at the end; the others expire on their own.

Consequences for the runner: a process that was injected with `GH_TOKEN` does not renew itself. For executions of up to 4 h, `gh` must always be invoked via `agent-forge gh` (fresh token per call); for long-lived processes (agent in a container) the adapter must re-mint with `agent-forge token --agent` before ~1 h (e.g. every ~45 min) and re-inject the token. Re-minting creates an independent token; it does not invalidate the previous ones.

## Observable shape of errors (to derive `AuthError`)

Forge's own errors go out through the same `main().catch`: **exit 1**, empty stdout, stderr `│` + newline + `■  <message>`. `gh`'s errors are propagated with its own code, normally 1, so the exit code alone does not distinguish; classification must go by stderr.

| Case | How it was obtained | exit | stderr (after `■  `) |
|---|---|---|---|
| Profile does not exist in Forge | real: `agent-forge gh no-such-agent-xyz --version` and `token --agent no-such-agent-xyz` | 1 | `Agent not found: no-such-agent-xyz` |
| Private key not found | temporary `AGENT_FORGE_CONFIG` with a nonexistent `privateKeyPath` | 1 | `Private key for "<agent>" not found or unreadable: <path>` |
| Key that does not belong to the App (analogue of a revoked/deleted key) | temporary `AGENT_FORGE_CONFIG`: real `appId`, freshly generated RSA key | 1 | `GitHub API /app/installations: 401 A JSON web token could not be decoded — the App JWT was rejected. Check that appId matches privateKeyPath ...` |
| Several installations and cwd without a repo of the owner | real, from `/tmp` | 1 | `GitHub App <id> is installed on 2 accounts (AshuLab, vemec). Launch from inside a repo under one of them.` (cwd/config, not auth) |
| Incorrect usage | real: `agent-forge gh no-such-agent-xyz` | 1 | `Usage: agent-forge gh <agent-name> <gh args...>` |
| Minted token expired or revoked, used by `gh` | real (revoked token) | 1 | `gh: Bad credentials (HTTP 401)` / `HTTP 401: Bad credentials (https://api.github.com/graphql)` |

The simulations pointed `AGENT_FORGE_CONFIG` at a temporary file with fake profiles: the real registry was not touched, no App or bot was created, and the test key was deleted.

Suggested classification rule (validate in the adapter with fixtures of these messages):

- `AuthError` (stops the profile's epics): `Agent not found:`, `Private key for ... not found or unreadable`, `GitHub API ...: 401` with "App JWT was rejected", `GitHub App ... has no installations` (read in the code, not observed), `Bad credentials`/`HTTP 401` from `gh`.
- Not `AuthError`: `installed on N accounts` (adapter cwd/configuration error), `Usage:`, 404/422 on resources (normal operation error).
- All are exit 1: parse stderr, not the code. A `Bad credentials` from `gh` can be a token that expired mid-execution: it is advisable to re-mint once and retry before declaring `AuthError`.

## What was not observed

- A **truly revoked** profile (installation uninstalled/suspended or key deleted in the App): nothing real is revoked. The safe analogue was observed (key that does not belong to the App → 401) and the "no installations" message is read in the code, not observed. It would be closed by a disposable test bot that Diego can uninstall and reinstall, repeating `agent-forge token --agent <bot>`.
- The real 1 h cap on the token: taken from GitHub's documentation; what was verified is the renewal.

## Proposal: shape of `profiles` and command

```json
"profiles": {
  "author-bot":   { "kind": "forge", "agent": "artanis-agent" },
  "reviewer-bot": { "kind": "forge", "agent": "tassadar-agent" },
  "diego":        { "kind": "gh" }
}
```

- `kind: "forge"`: bot via Forge; `agent` is the name in Forge's registry. No secrets in the config (the keys live in Forge's registry).
- `kind: "gh"`: `gh`'s own login (personal account, which Forge does not support); `gh` is run directly.

Exact command, separate argv and `cwd` inside a clone of the right owner:

```ts
execFile("agent-forge", ["gh", profile.agent, ...ghArgs], { cwd, timeout: githubCallTimeoutSeconds * 1000 })
```

For `kind: "gh"`: `execFile("gh", ghArgs, { cwd, timeout })`. Always pass an explicit `--repo <owner>/<repo>`. For `git` as a bot: `agent-forge token --agent <agent>`, export `GIT_AUTHOR_*`/`GIT_COMMITTER_*` as above and pass the token to the credential helper via `GH_TOKEN`.

The spec was updated in this same PR (`docs/specs/autonomous-orchestrator.md`: the `profiles` example and the sentence that said the shape would be fixed after the spike). The current schema (`src/config/schema.ts`) accepts each profile as `z.looseObject({})`; tightening it to these two shapes is left for the configuration slice (this PR is documentation only).

## Footprints in `AshuLab/agent-forge`

Deleted: the branch `spike/carrier-forge-20261016012437` and the label `carrier-spike-tmp`. Verified at the end: `main` at `8dee1b0` (unchanged), branches = `["main"]`, labels = the 7 pre-existing ones (without the temporary one), no PR.

Remaining: issue #27 `[carrier spike] forge identity test - safe to close`, **closed** (`not planned`), with its two comments (one from `tassadar-agent`, one closing comment from `artanis-agent`) and its event history (label added and removed); an issue cannot be deleted via the API. Actors: only `artanis-agent` and `tassadar-agent`. No real credential was rotated, revoked or deleted; only ephemeral installation tokens minted during the test were revoked.
