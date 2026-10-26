# Troubleshooting

First step for almost everything: `carrier doctor` (it reads `~/.carrier/config.json`; pass `--config <file>` for another).

Where to look: the panel in the terminal shows each epic's stage, its history, round and reason (for a Carrier started with `carrier start`, `carrier status` prints it once and `carrier watch` follows it). `<root>/orchestrator/logs/orchestrator.log` has the process log and `<root>/orchestrator/logs/executions/<id>/` the full output of each agent run (default root `~/.solve`). A detached Carrier writes what it prints to `<root>/orchestrator/logs/start.log`, replaced at each start (the macOS app's start uses `app-start.log`). None contains tokens. In the panel, select an epic with `↑`/`↓` and press `l` to read what its agent is doing, without leaving it; `?` lists the keys.

## An epic ends in `solve:epic:needs-human`

The reason is in the panel and the logs. Carrier stops the epic and leaves everything as it was (sessions, worktrees, uncommitted work); the others keep going. Common reasons:

| Reason | What happened | What to do |
|--------|---------------|------------|
| `inconclusive review: ...` or any reason written by an agent | The agent decided it needs a person. | Read the reason, decide, finish the work on the PR yourself. |
| `ran out of ship retries (N attempts): ...` | The agent process failed technically N times. | Look at the execution logs. Usually auth, network or CLI trouble. |
| `the ship execution exceeded the time limit` | One execution went past `maxExecutionHours`. Not retried. | Look at what it was doing; raise the limit or use `"unlimited"` for the next epic. |
| review rounds exhausted | The reviewer still asked for changes after `maxReviews` rounds. | Read the open findings on the PR and decide. |
| `PR #N is not open`, `the head changed during the review`, a PR that references another epic | The PR does not match what Carrier expected. Repeating would not fix it. | Check the PR and its commits. |
| a reason saying the spec, an ADR or the glossary is missing | The epic refers to files that are not on the remote (they only exist in someone's working copy). | Commit them as the first commit of the epic branch (or merge them into the base branch), push, then put `solve:epic:ready` back. |
| `could not prepare the workspace: ...` | Clone, checkout or worktree failed. | Check disk, git credentials and `<root>/worktrees`. |
| `authentication error for profile X` | Forge could not authenticate that profile. Only epics using it stop. | `agent-forge token --agent <name>` from a clone of the repo; fix the App, key or installation. |

**To continue an epic that is in `needs-human`:** fix what the reason says (outside Carrier), then use **Resume** on the epic in the macOS app. Underneath, Carrier does what you can do by hand: it puts the `solve:epic:ready` label back on the issue and checks at once (`r` in the panel does the check), so the epic is queued again and starts from `ship`, which reuses the epic's worktree and its PR; the review rounds start over. Without the app, put the label back yourself and wait for the next check. Without that label the epic stays stopped, even across restarts. Nothing checks that the cause is fixed: if it is not, the epic stops again with the new reason. If the app says the epic did not restart, the label is on and the next check takes it.

## Start-up errors

- **`Invalid config <file>:` + fields.** Fix each listed field. `carrier schema` shows what is allowed.
- **`Another carrier instance is already running on <root>/orchestrator`.** One instance per root. Stop the other one (`carrier stop`, or Ctrl+C where it runs). If none is running the lock is released by the OS when a process dies, so this message is real: look for the process (`pgrep -fl carrier`).
- **`carrier start` says `Carrier exited before it was ready` or `did not answer within 15 seconds`.** It prints the end of `start.log`: that is the start-up error, so read it against this list. `carrier status` says whether something runs after all.
- **`carrier status`, `watch`, `stop`... say Carrier is not running (exit 1) but it is.** They look at the `root` of the config they read: pass the same `--config` the Carrier was started with. Exit 2 means the socket speaks another protocol (a Carrier of another version).
- **`carrier failed to start: GitHub answered HTTP 404`.** The orchestrator's identity cannot see a repo in `repos`: wrong name, or the bot is not installed on that owner. `carrier doctor` names the repo.
- **`could not mint a token for <agent>`.** Forge could not mint it: agent not in the registry (`agent-forge --list`), private key unreadable, App not installed on the repo's owner.
- **An `agy` run waits about a minute and fails with `authentication failed or timed out`.** Antigravity is not logged in. Run `agy` once in a terminal and sign in; Carrier cannot shorten that wait.
- **`agent-forge: command not found`.** Install it (or use only `gh`: under separate identities author and reviewer cannot both be `gh`, but with a shared identity they can, see `carrier init --identities shared`).
- **`LM Studio is not answering at http://localhost:1234` / `... not downloaded there`.** The agent uses a local model (`provider` in the config): start the server (LM Studio: Developer tab, or `lms server start`; Ollama: `ollama serve`) and make sure the model is downloaded. `carrier doctor` repeats the check.

## While it runs

- **GitHub is down or rate limiting.** Carrier keeps the queue, shows the error and tries again at the next interval or after the wait GitHub indicates. It does not spend agent retries.
- **An epic is not picked up.** It needs the `solve:epic:ready` label, the issue open, and a free slot (`maxConcurrentEpics`). Epics go FIFO across all repos. Check that the panel does not say `PAUSED` (`p` pauses and resumes taking epics), and press `r` to check GitHub now instead of waiting for the interval.
- **A repo was removed from the config.** On restart its pending epics are stopped with that reason and recovered if you add it back (unless they were in `needs-human`).
- **Ctrl+C, `q` or `carrier stop`.** (In `carrier watch`, `q` and Ctrl+C only leave: Carrier keeps running.) Stops the agents and keeps everything; the next start reconciles with GitHub and resumes. Known limit: without a container, stopping does not guarantee an agent's child processes die (Codex leaves its command process even on SIGTERM, Claude on SIGKILL; Antigravity cleans up on SIGTERM). If you see leftover `codex`, `claude` or `agy` processes, `pgrep -fl 'codex|claude|agy'` and kill them.
- **A restart stops the agents the previous run left, and only those.** It recognises them as executions of its own database, so a live agent of another Carrier (another root) on the same machine is never touched.
- **A Codex reviewer ends in `needs-human` after 3 attempts writing its result.** Known residual risk: it can mangle the result path. Look at the execution log, finish the review by hand.

## Cleaning up

Logs and sessions of an ended or cancelled epic are deleted after 30 days. SQLite (`<root>/orchestrator/carrier.db`) and worktrees are never deleted by Carrier.
