# Troubleshooting

First step for almost everything: `carrier doctor --config <file>`.

Where to look: the panel in the terminal shows each epic's stage, round and reason. `<root>/orchestrator/logs/orchestrator.log` has the process log and `<root>/orchestrator/logs/executions/<id>/` the full output of each agent run (default root `~/.solve`). Neither contains tokens.

## An epic ends in `solve:epic:needs-human`

The reason is in the panel and the logs. Carrier stops the epic and leaves everything as it was (sessions, worktrees, uncommitted work); the others keep going. Common reasons:

| Reason | What happened | What to do |
|--------|---------------|------------|
| `inconclusive review: ...` or any reason written by an agent | The agent decided it needs a person. | Read the reason, decide, finish the work on the PR yourself. |
| `ran out of ship retries (N attempts): ...` | The agent process failed technically N times. | Look at the execution logs. Usually auth, network or CLI trouble. |
| `the ship execution exceeded the time limit` | One execution went past `maxExecutionHours`. Not retried. | Look at what it was doing; raise the limit or use `"unlimited"` for the next epic. |
| review rounds exhausted | The reviewer still asked for changes after `maxReviews` rounds. | Read the open findings on the PR and decide. |
| `PR #N is not open`, `the head changed during the review`, a PR that references another epic | The PR does not match what Carrier expected. Repeating would not fix it. | Check the PR and its commits. |
| `could not prepare the workspace: ...` | Clone, checkout or worktree failed. | Check disk, git credentials and `<root>/worktrees`. |
| `authentication error for profile X` | Forge could not authenticate that profile. Only epics using it stop. | `agent-forge token --agent <name>` from a clone of the repo; fix the App, key or installation. |

An epic in `needs-human` is not reactivated by Carrier, not even on restart: you resolve it outside Carrier. There is no reactivation command in this version.

## Start-up errors

- **`Invalid config <file>:` + fields.** Fix each listed field. `carrier schema` shows what is allowed.
- **`Another carrier instance is already running on <root>/orchestrator`.** One instance per root. Stop the other one (Ctrl+C). If none is running the lock is released by the OS when a process dies, so this message is real: look for the process (`pgrep -fl carrier`).
- **`carrier failed to start: GitHub answered HTTP 404`.** The orchestrator's identity cannot see a repo in `repos`: wrong name, or the bot is not installed on that owner. `carrier doctor` names the repo.
- **`could not mint a token for <agent>`.** Forge could not mint it: agent not in the registry (`agent-forge --list`), private key unreadable, App not installed on the repo's owner.
- **An `agy` run waits about a minute and fails with `authentication failed or timed out`.** Antigravity is not logged in. Run `agy` once in a terminal and sign in; Carrier cannot shorten that wait.
- **`agent-forge: command not found`.** Install it (or use only `gh` profiles, with the caveat that author and reviewer then cannot both be `gh`).

- **`LM Studio is not answering at http://localhost:1234` / `... not downloaded there`.** The agent uses a local model (`provider` in the config): start the server (LM Studio: Developer tab, or `lms server start`; Ollama: `ollama serve`) and make sure the model is downloaded. `carrier doctor` repeats the check.

## While it runs

- **GitHub is down or rate limiting.** Carrier keeps the queue, shows the error and tries again at the next interval or after the wait GitHub indicates. It does not spend agent retries.
- **An epic is not picked up.** It needs the `solve:epic:ready` label, the issue open, and a free slot (`maxConcurrentEpics`). Epics go FIFO across all repos.
- **A repo was removed from the config.** On restart its pending epics are stopped with that reason and recovered if you add it back (unless they were in `needs-human`).
- **Ctrl+C.** Stops the agents and keeps everything; the next start reconciles with GitHub and resumes. Known limit: without a container, stopping does not guarantee an agent's child processes die (Codex leaves its command process even on SIGTERM). If you see leftover `codex` or `claude` processes, `pgrep -fl 'codex|claude'` and kill them.
- **A Codex reviewer ends in `needs-human` after 3 attempts writing its result.** Known residual risk: it can mangle the result path. Look at the execution log, finish the review by hand.

## Cleaning up

Logs and sessions of an ended or cancelled epic are deleted after 30 days. SQLite (`<root>/orchestrator/carrier.db`) and worktrees are never deleted by Carrier.
