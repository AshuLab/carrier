# Troubleshooting

First step for almost everything: `carrier doctor` (it reads `~/.carrier/config.json`; pass `--config <file>` for another).

## Start with the Health tab

In the macOS app, open Settings and the Health tab first when **a session fails**, **your repositories do not load** or **the engine does not start**. It checks `git`, `gh` and the `claude` and `codex` CLIs and their logins, the `carrier` command, the chat host and the engine, and shows the checks of `carrier doctor` once the engine has a config. See [the Health tab](../macos/README.md#health-tab) for what each state means.

| Symptom | Look at | Usual cause and what to do |
|---------|---------|----------------------------|
| A session fails right after the first message | This Mac, the provider's row | `Signed out`: press its button (`claude auth login` or `codex login` in Terminal). `Not installed`: install the CLI from the link in the row. |
| My GitHub repositories do not load, or cloning is off | This Mac, `gh` | `Signed out`: press `gh auth login`. `Not installed`: install `gh` from the link. |
| New worktree is off | This Mac, `git` | `Not installed`: press `xcode-select --install`. |
| The engine does not start | Carrier, then Engine setup | `carrier` not found: press its fix in Health (`brew install ashulab/tap/carrier` in Terminal), or set “Use this carrier” under Advanced in the Engine tab. Engine not configured: the setup wizard makes `config.json`. Otherwise read the failing doctor checks and their fix text. |
| A row says `Could not check` | The row | The probe timed out or could not be read; press Check again. It never blocks anything. |

Without the app, `carrier doctor` is the same engine-setup check in a terminal; `carrier doctor --json` prints its checks as one JSON array (`{ name, status, detail?, fix?, repo?, profiles? }`, `status` being `ok`, `warn` or `fail`; the checks about one repo, the token each identity can mint, the read and the Solve labels, also carry `repo` and `profiles`, the names under `config.profiles` they stand for) and exits 1 when any fails, as the app reads it.

Where to look: the panel in the terminal shows each epic's stage, its history, round and reason (for a Carrier started with `carrier start`, `carrier status` prints it once and `carrier watch` follows it). `<folder>/engine/logs/orchestrator.log` has the process log and `<folder>/engine/logs/executions/<id>/` the full output of each agent run (`<folder>` is the Carrier folder: `~/.carrier`, or `CARRIER_HOME`). A detached Carrier writes what it prints to `<folder>/engine/logs/start.log`, replaced at each start (the macOS app's start uses `app-start.log`). None contains tokens. In the panel, select an epic with `↑`/`↓` and press `l` to read what its agent is doing, without leaving it; `?` lists the keys.

## Installing and updating with Homebrew

### macOS will not open the app

The cask clears the quarantine attribute after it downloads the app, because the app is signed ad hoc and not notarized ([ADR 0017](adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)). If macOS still says it cannot open or verify `Carrier.app` (for example you copied the app from somewhere else, or the step did not run), clear the attribute by hand and open it again:

```bash
xattr -dr com.apple.quarantine /Applications/Carrier.app
```

The app needs an Apple Silicon Mac on macOS 26 or later; the cask refuses to install on anything else.

### Homebrew refuses the formula because the tap is not trusted

Homebrew 7 loads the code of a tap that is not its own only once you trust it. `brew install ashulab/tap/carrier` (the full name) trusts just that formula. If you installed or upgraded by the short name (`brew install carrier`) and Homebrew refuses it as untrusted, use the full name, or trust the formula once:

```bash
brew trust --formula ashulab/tap/carrier
```

### The app asks to update `carrier` or itself

The app and `carrier` are two things `brew upgrade` can move at different moments. When their sockets speak different protocols the app says which one is behind and does not connect to that chat host or engine:

- "carrier is older than this app": run `brew upgrade carrier` in Terminal, then restart Carrier.
- "This app is older than carrier": the app updates itself; if it has not, run `brew upgrade --cask carrier` in Terminal, then open the app again.

Running both (`brew upgrade carrier` and `brew upgrade --cask carrier`) leaves them at the same release.

### The app never shows an update

The app checks by itself (Sparkle, once a day, and in the background each time it opens) and asks before it installs ([how the update works](releasing.md#2-what-the-installed-app-does)). If a new release does not arrive:

- **The release is not out yet.** The feed is `https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml` and it moves to a version only when its release is published, the last step of a release; a run that stopped in the middle leaves a draft and the feed on the previous version. `gh release list --repo AshuLab/carrier` shows a `Draft`, and `curl -sIL` on the feed shows which version it serves. Finishing the run publishes it ([releasing](releasing.md#what-a-run-that-stops-leaves-and-how-to-finish-it)). For about ten seconds after a release is published the feed may answer 404.
- **The app does not check.** The two choices (check by itself, install by itself) are Sparkle's own preferences and Settings has no page for them yet. `defaults read dev.ashulab.carrier SUEnableAutomaticChecks` printing `0` means checking was turned off; `defaults delete dev.ashulab.carrier SUEnableAutomaticChecks` goes back to the default, on. A build with no feed (run with `swift run`, or under `--fixture`) never checks.
- **The app is older than the first release with Sparkle,** which cannot update itself: run `brew upgrade --cask carrier` once, and from then on it moves by itself.
- **The update was refused.** `log show --last 1h --predicate 'subsystem == "org.sparkle-project.Sparkle"'` says why. "The update is improperly signed" means the zip was not signed with the key inside the installed app (see "The update key was lost" below). The line "Code signature of the new version doesn't match the old version" appears at the Error level on every update of an ad hoc app and is not a failure.
- **This Mac is not supported by the release:** the app needs an Apple Silicon Mac on macOS 26 or later.

### Carrier could not be updated after the app updated

After Sparkle replaces the app, the app finds the installed `carrier` older than itself and upgrades it with Homebrew (`brew update`, then `brew upgrade --formula ashulab/tap/carrier`). When that fails, the Sessions home and the Sessions section of the sidebar show **"Carrier could not be updated"** with the reason: "Homebrew was not found at /opt/homebrew/bin/brew", or "`brew update` failed" / "`brew upgrade` failed, so the app kept the Carrier it has" followed by the last lines of Homebrew's output. Nothing was changed: the old `carrier`, chat host and engine keep working with the new app, and the app tries again the next time it opens.

The whole output is in `<folder>/engine/logs/app-upgrade.log` (`<folder>` is the Carrier folder, `~/.carrier` or `CARRIER_HOME`); each job replaces the previous log. The usual causes:

- **No network.** Connect and open the app again, or run `brew update && brew upgrade --formula ashulab/tap/carrier` in Terminal.
- **Another `brew update` or `brew upgrade` is running** and holds Homebrew's lock. Wait for it, then open the app again.
- **The formula is pinned.** Homebrew skips a pinned formula, so there may be no notice at all and `carrier --version` stays old. `brew list --pinned` lists `carrier`; `brew unpin carrier` and upgrade.
- **Homebrew is not in `/opt/homebrew`.** The app only runs that one `brew` (Apple Silicon); upgrade in Terminal with your own.

### The engine or the chat host is still on the old version after an update

The app replaces them only when doing so loses nothing:

- **The chat host** is replaced when no session is working or waiting for an approval. Otherwise the Sessions home says "The chat host is older than Carrier"; restart it when the session finishes: `carrier chat --stop`, and the next new session starts the installed one.
- **The engine** is replaced only if it was running, and once it has no execution in flight. While it waits the app pauses intake, so the panel and the app show it paused; when the last execution ends the app stops it, starts the installed `carrier` and pauses it again if you had paused it. An engine you had stopped stays stopped: start it with `carrier start`. If the app was quit during the wait, intake stays paused: `carrier resume`, then `carrier stop` and `carrier start` to move to the new version.
- If the upgrade itself failed (the section above), neither is touched.

`carrier --version` prints the installed version; a process started before the upgrade runs the old one until it is restarted.

### The update key was lost

Each release's zip is signed with the update key. If its private half is lost, the next release cannot be signed with the key the installed apps trust, so Sparkle refuses it as improperly signed; the apps keep working but stop updating, and the key cannot be rotated with an ad hoc signature ([releasing, the update key](releasing.md#4-the-update-key)). The owner makes a new pair, puts its public half in `macos/update-key.pub`, sets the repository secret `SPARKLE_PRIVATE_KEY` and cuts a release. People who already have Carrier then run `brew reinstall --cask carrier`, which brings a zip with the new public key; only those who run it are updated again, and their Carrier folder is left alone.

## An epic ends in `solve:epic:needs-human`

The reason is in the panel and the logs. Carrier stops the epic and leaves everything as it was (sessions, worktrees, uncommitted work); the others keep going. Common reasons:

| Reason | What happened | What to do |
|--------|---------------|------------|
| `inconclusive review: ...` or any reason written by an agent | The agent decided it needs a person. | Read the reason, decide, finish the work on the PR yourself. |
| `ran out of ship retries (N attempts): ...` | The agent process failed technically N times. | Look at the execution logs. Usually auth, network or CLI trouble. |
| `... the agent process ended with an error (killed: SIGKILL)` | `killed`: a signal from outside Carrier ended the agent's process (Carrier's own stops and timeouts are not this); the detail is the signal. Often the system killing it for memory (`Exit code 137` in the agent's own commands). | Look at the host memory and load the execution row records (`hostFreeMemMb`, `hostLoad`; on macOS free memory understates what is available), and at what else ran at that time. |
| `the ship execution ran out of usage on option NAME: ...` | `usage_limit`: the agent ended on its usage limit (Claude's API status 429, or Codex's or Antigravity's own message); the detail is what the agent printed, with the time it resets. The epic stops in needs-human at once (kind `usage_limit`), naming the option that ran out, and no retry is spent. | Wait for the reset time in the reason, then Resume the epic, or `carrier restart` it on another option. |
| `... (api_error: HTTP N: ...)` | `api_error`: Claude ended on an API error with status N (not the 401 that is an authentication error, not the usage limit); the detail is the status and the message the agent printed. | Read the message; a 5xx is usually Anthropic's side, so Resume the epic later. |
| `... (crashed: exit code N)` | `crashed`: the agent's process exited with a nonzero code and no signal. | Read the end of the execution's `stdout.log` for what it printed before exiting. |
| `... (spawn_error: ...)` | `spawn_error`: the agent's binary could not start, or its command could not be built. | Check that the harness binary (`claude`, `codex` or `agy`) is installed and on the `PATH` of the machine that runs Carrier; `carrier doctor` checks the setup. |
| `... the agent session is not available` | `session_lost`: the harness no longer has the session Carrier tried to resume. Carrier starts a new one with the context rebuilt from SQLite and GitHub; it shows here only if the retries ran out. | Look at why it failed after the rebuild, in the execution's logs; the execution row keeps the kind. |
| `ran out of ship retries ...` quoting a problem with the result file | `invalid_result`: the agent ended without a complete, valid result file; the detail is the validation message. The stage does not advance and the execution is retried. | Read the message and the execution's `stdout.log` to see what the agent wrote or why it stopped before writing. |
| `... (unknown)` or `... (unknown: ...)` | `unknown`: the process failed and nothing else explains it (for example it ended without an exit code); the text has no detail when the runner gave none. | Read the execution's logs; the row has the exit code, signal, host memory and load. |
| `the ship execution exceeded the time limit` | `timeout`: one execution went past `maxExecutionHours`. Not retried; the execution has the kind and no error text. | Look at what it was doing; raise the limit or use `"unlimited"` for the next epic. |
| review rounds exhausted | The reviewer still asked for changes after `maxReviews` rounds. | Read the open findings on the PR and decide. |
| `PR #N is not open`, `the head changed during the review`, a PR that references another epic | The PR does not match what Carrier expected. Repeating would not fix it. | Check the PR and its commits. |
| a reason saying the spec, an ADR or the glossary is missing | The epic refers to files that are not on the remote (they only exist in someone's working copy). | Commit them as the first commit of the epic branch (or merge them into the base branch), push, then put `solve:epic:ready` back. |
| `could not prepare the workspace: ...` | Clone, checkout or worktree failed. | Check disk, git credentials and `<folder>/engine/repos` and the epic's worktree (by default under `<folder>/engine/worktrees`). |
| `authentication error for profile X` | `auth`: Forge could not authenticate that profile (the detail is `profile X`), or no GitHub token could be minted for it. Only epics using it stop. | `agent-forge token --agent <name>` from a clone of the repo; fix the App, key or installation. |

**To continue an epic that is in `needs-human`:** fix what the reason says (outside Carrier), then use **Resume** on the epic in the macOS app, or `carrier restart <owner/name>#<issue>` in a terminal (add `--author <option>` or `--reviewer <option>` to run a role on another agent option: the same option continues its session, another one starts a new session in the same worktree and pull request). Underneath, Carrier does what you can do by hand: it puts the `solve:epic:ready` label back on the issue and checks at once (`r` in the panel does the check), so the epic is queued again and starts from `ship`, which reuses the epic's worktree and its PR; the review rounds start over. Without the app or the command, put the label back yourself and wait for the next check. Without that label the epic stays stopped, even across restarts. Nothing checks that the cause is fixed: if it is not, the epic stops again with the new reason. If the app says the epic did not restart, the label is on and the next check takes it.

## A new session does not start

Choosing a folder, a repository or a project in New session changes nothing on your Mac. The session is prepared when you send the first message: the conversation shows the steps it needs (clone or fetch, project, worktree, checkout, agent, message), each running, done or failed, until the agent answers. A step that fails stops there and the session stays in the sidebar with the reason in words and your message kept. Press **Try again** to repeat the steps that did not finish (a clone, fetch, project folder or worktree already made is reused). **Cancel** while it runs stops the step, deletes the session and its worktree, and puts what you chose and typed back in the draft. A clone that already finished stays in the projects folder.

- **The checkout step fails with `The folder has N uncommitted files, so its branch was not changed to <branch>`.** You picked a branch for a folder that already existed and has uncommitted changes, and Carrier never takes the branch from under unsaved work. Commit, stash or discard the changes in that folder (or use a worktree instead, which never touches it), then press Try again.
- **The clone or fetch step fails.** The reason says whether the repository was not found or not visible to your `gh` login, `gh` is missing or signed out, there is no network, or it took longer than ten minutes. Fix that (the Health tab's `gh` row, above) and press Try again.
- **The app says the host is older and to restart it.** The chat host that is running does not know how to prepare a plan, and the app sends nothing to it. The app replaces an old host on its own when no session is working; otherwise wait for the session to finish, or stop the host with `carrier chat --stop` (the app starts a new one when you open New session).
- **The session says a step failed as interrupted (`Carrier stopped while this step was running`).** The chat host stopped in the middle of the step. Press Try again.
- **A repository you let Carrier watch is not in the engine's `repos`.** It is added only once the agent has answered, and the engine listens from its next start. A session whose preparation failed or was cancelled adds nothing.

## An archived session is kept and not deleted

In the macOS app the Archive page says "Kept because its worktree has unsaved work" under the session. The clock never deletes a session whose worktree has uncommitted changes or commits that exist nowhere else, so it stays archived, however old, until its worktree is clean or you act (see [The session clock](configuration.md#the-session-clock)). A worktree that git could not read is left alone too, with the failure in `<folder>/chat/logs/chat-host.log`, and tried again an hour later. The clones in the projects folder are never deleted.

To get rid of it, open the Archive page, hover the row and press Delete: the app first lists what would be lost ("3 uncommitted files and 2 commits that exist nowhere else will be removed with its worktree"), and nothing is deleted until you confirm. To keep the work, press Resume and commit and push it from the session's worktree; once nothing in it is unsaved, the session is archived and deleted by the clock again in time. Without the app, `carrier chat --delete <id>` deletes it at once with no question (`carrier chat --list --archived` shows the ids).

## Start-up errors

- **`Invalid config <file>:` + fields.** Fix each listed field. `carrier schema` shows what is allowed.
- **`Another carrier instance is already running on <folder>/engine/state`.** One instance per Carrier folder. Stop the other one (`carrier stop`, or Ctrl+C where it runs). If none is running the lock is released by the OS when a process dies, so this message is real: look for the process (`pgrep -fl carrier`).
- **`carrier start` says `Carrier exited before it was ready` or `did not answer within 15 seconds`.** It prints the end of `start.log`: that is the start-up error, so read it against this list. `carrier status` says whether something runs after all.
- **`carrier status`, `watch`, `stop`... say Carrier is not running (exit 1) but it is.** They look for the control socket in `<folder>/engine/state/` of the Carrier folder they run with: run them with the same `CARRIER_HOME` the Carrier was started with (`--config` only chooses the config file, never the folder). Exit 2 means the socket speaks another protocol (a Carrier of another version).
- **`carrier failed to start: GitHub answered HTTP 404`.** The orchestrator's identity cannot see a repo in `repos`: wrong name, or the bot is not installed on that owner. `carrier doctor` names the repo.
- **`could not mint a token for <agent>`.** Forge could not mint it: agent not in the registry (`agent-forge --list`), private key unreadable, App not installed on the repo's owner.
- **An `agy` run waits about a minute and fails with `authentication failed or timed out`.** Antigravity is not logged in. Run `agy` once in a terminal and sign in; Carrier cannot shorten that wait.
- **`<harness> option <name> is logged in` fails or warns in `carrier doctor`.** That Claude or Codex option has no working login in its config folder (`configDir`, or the environment Carrier runs in when it has none). It fails when a role uses the option and only warns for any other. Log in as the remedy says: `CLAUDE_CONFIG_DIR=<dir> claude /login` or `CODEX_HOME=<dir> codex login` (the folder must exist for Codex). Doctor only reads whether the login works; it never prints the account.
- **`agy option <name> is logged in` fails or warns in `carrier doctor`.** Antigravity has no status command, so doctor runs `agy -p "/usage"` (it costs nothing) in a throwaway folder. If agy asks for a login, the option is not logged in (a failure when a role uses it, a warning otherwise): run `agy` once in a terminal and sign in. If agy neither answers nor asks within 30 seconds, doctor kills it and warns that it could not tell. The login link agy prints is never shown or logged.
- **`agent-forge: command not found`.** Install it (or use only `gh` for both roles: `carrier init --author-profile gh --reviewer-profile gh`).
- **`LM Studio is not answering at http://localhost:1234` / `... not downloaded there`.** The agent uses a local model (`provider` in the config): start the server (LM Studio: Developer tab, or `lms server start`; Ollama: `ollama serve`) and make sure the model is downloaded. `carrier doctor` repeats the check.

## While it runs

- **GitHub is down or rate limiting.** Carrier keeps the queue, shows the error and tries again at the next interval or after the wait GitHub indicates. It does not spend agent retries. The log and the `REPOS GITHUB REFUSED` line say which kind it was and the detail, like `GitHub unavailable (rate_limited: HTTP 403)`: `rate_limited`, `server_error`, `timeout` or `network`.
- **An epic is not picked up.** It needs the `solve:epic:ready` label, the issue open, and a free slot (`maxConcurrentEpics`). Epics go FIFO across all repos. Check that the panel does not say `PAUSED` (`p` pauses and resumes taking epics), and press `r` to check GitHub now instead of waiting for the interval.
- **A repo was removed from the config.** On restart its pending epics are stopped with that reason and recovered if you add it back (unless they were in `needs-human`).
- **Ctrl+C, `q` or `carrier stop`.** (In `carrier watch`, `q` and Ctrl+C only leave: Carrier keeps running.) Stops the agents and keeps everything; the next start reconciles with GitHub and resumes. Known limit: without a container, stopping does not guarantee an agent's child processes die (Codex leaves its command process even on SIGTERM, Claude on SIGKILL; Antigravity cleans up on SIGTERM). If you see leftover `codex`, `claude` or `agy` processes, `pgrep -fl 'codex|claude|agy'` and kill them.
- **A restart stops the agents the previous run left, and only those.** It recognises them as executions of its own database, so a live agent of another Carrier (another Carrier folder) on the same machine is never touched.
- **A Codex reviewer ends in `needs-human` after 3 attempts writing its result.** Known residual risk: it can mangle the result path. Look at the execution log, finish the review by hand.

## Cleaning up

Logs and sessions of an ended or cancelled epic are deleted after 30 days. SQLite (`<folder>/engine/state/carrier.db`) and worktrees are never deleted by Carrier.
