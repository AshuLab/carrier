# Command line

Reference for the `carrier` command. The quick tour is in the [README](../README.md); the config file is in [configuration](configuration.md).

| Command | What it does |
|---------|--------------|
| `carrier` | Runs Carrier in this terminal with the live panel until `Ctrl+C`. Reads `~/.carrier/engine.json`; `--config <path>` uses another file. One instance per Carrier folder. |
| `carrier init` | Guided setup that writes the config. |
| `carrier doctor` | Checks the config and the machine. |
| `carrier schema` | Prints the config's JSON Schema. |
| `carrier start` / `stop` / `pause` / `resume` / `check` | Run it in the background and control it from any terminal. |
| `carrier reload` | Make the running Carrier read `engine.json` and `providers.json` again, with no restart. |
| `carrier status` / `watch` | Show what the running Carrier is doing. |
| `carrier restart` | Resume an epic that stopped in `needs-human`. |
| `carrier recover` | Continue a running epic whose agent is not alive, from where it really is. |
| `carrier chat` / `chat-host` | Talk to an agent in a session. |
| `carrier usage` | Live quotas of your accounts and what was used. |
| `carrier config` | Change a setting of the Carrier folder: one request as a line of JSON on standard input, the reply as a line on standard output. |

From a clone, run `pnpm build` and then `node dist/terminal/cli/main.js`, or `node src/terminal/cli/main.ts --config ...` (Node 26 runs the TypeScript directly).

## `carrier init`

It opens by saying what it will ask, then looks at the machine (stopping with the fix if `git`, `gh` or every agent CLI is missing) and shows what it found: each agent CLI with its path, version and login, and the local servers that answer. While it waits for the machine or for GitHub it shows a spinner. Then it asks, in this order:

1. **Repos to watch**, picked from the repos your `gh` login can push to (grouped by owner, with "Load more…" for the next page) or typed. "None for now" is an answer: the config is written with no repos, and Carrier watches nothing until you add one in the file or in the Mac app's Settings.
2. **Accounts.** One account per agent CLI found is added for you, with the login that CLI already has, and written to `~/.carrier/providers.json` (even when `--out` moves the config). You are asked only for **extra** accounts, one at a time, and Enter says no: the CLI, the local server when one is running, and for Claude and Codex the config folder (the `~/.claude`, `~/.claude-*` and `~/.codex` it finds with their login state, the environment, or a typed path; Antigravity has none), then a name that must be a lowercase word and unique.
3. **GitHub identities.** A short note explains what they are, then each role picks a bot of Agent Forge or your own `gh` login. Picking the same one twice is accepted, and the recap then says the signature will show it. If there is no bot it can run `agent-forge add` for you on the spot.
4. **Each role** (author, reviewer, and a lead reviewer if you say yes; Enter says no): the account that runs it, its model, its effort (`low`, `medium`, `high`, `xhigh` or `max`, or the CLI's own, which writes nothing) and an optional persona (a name and a prompt, each skippable).
5. **Failover**, with two or more accounts: for each role, whether to turn it on (Enter says no) and up to two steps, each an account and a model (the `failover` block).
6. **Where to save**: `~/.carrier/engine.json` (one global file per user), or another file with `--out`.

Before saving it shows a recap with three choices: save, **change an answer** (it asks everything again, starting from the same answers) or cancel; nothing is written until you save. It then runs the checks of `carrier doctor`, printing only what fails (otherwise a single count), shows how many epics are waiting, and offers to start Carrier.

Run again on an existing config, it offers to edit it (its answers are the starting points), start over, save a new one in another file, or leave it. Editing keeps the accounts of `providers.json` and lets you add more (editing or removing one is done in the file), starts each role's effort, persona and lead reviewer from the file, and asks whether to keep the failover steps it has; `-` in a persona field clears it.

Every question has a flag (`carrier init --help`). `--author` and `--reviewer` (`<harness>:<model>`, with `--author-provider` and `--reviewer-provider`) each add an account named after its harness to `providers.json` (the one found, when it matches) and, when both are given, skip the extra-accounts and failover questions. `--author-profile` and `--reviewer-profile` answer the identities, `--author-persona-name`, `--author-persona-prompt`, `--reviewer-persona-name` and `--reviewer-persona-prompt` the personas, and `--author-effort`, `--reviewer-effort` and `--lead-reviewer-effort` the efforts. `--yes` never asks, so an agent can run it too (`--author-profile gh --reviewer-profile gh` makes both roles your `gh` login):

```bash
carrier init --yes --repo AshuLab/my-repo \
  --author-profile forge:<agent-1> --author claude:<model> \
  --reviewer-profile forge:<agent-2> --reviewer codex:<model>
```

Without `--author` and `--reviewer`, `--yes` gives the author the first account found and the reviewer another one when there is one, each with the model the wizard would suggest; the flags above choose them.

## `carrier doctor` and `carrier schema`

`carrier doctor` verifies the tools are installed, that each identity can get a token for each repo, that the orchestrator can read it, and that each repo it could read has the labels Carrier reads (`labels.epic` and `labels.ready`, by default `solve:epic` and `solve:epic:ready`; the fix is to run `solve:setup` in the repo). It checks a config of yours or a hand-written one at any time. `carrier schema` prints the JSON Schema of the config for your editor.

For each role of each repo it also asks whether each skill the role invokes exists for the account the role runs on: the author's `ship` and `fix`, the reviewer's `review` and `publish` (none when `publish` is `null`), as `skills` in the config names them.
Each skill gets one check with one of three answers.
Present is ok.
Absent means Carrier read every place the harness looks and none had the skill: it fails when you named the skill, and only warns when it is Solve's default, because an epic runs without it today.
Cannot tell is a warning: a place the harness may read could not be read (the plugin list failed or was unreadable, a manifest could not be parsed, or a manifest filters skills with `include_only` or `exclude`).
For Claude Code the places are the account's `skills/<name>/SKILL.md` and `commands/<name>.md` (its `configDir`, or `~/.claude`), `.claude/skills/<name>` in the repo and its parent folders up to the repo root, and the skills of each plugin `claude plugin list --json` reports for that account.
A bare name matches `<name>` or `<plugin>:<name>`.
Codex and Antigravity are read the same way, in their own places; [troubleshooting](troubleshooting.md) lists them.

`carrier doctor --json` prints the checks as a JSON array (`{ name, status, detail?, fix?, repo?, profiles? }`, `status` `ok`, `warn` or `fail`; `repo` and `profiles`, the names under `config.profiles` the check stands for, are set together on the checks about one repo) and nothing else, with the same exit code (1 when any fails); the macOS app's Health tab reads it.

## Writing the config by hand

See [configuration](configuration.md): the minimal file, every field with its default, and `providers.json`. Invalid configs print every error with its field and exit without starting anything.

## Run without a terminal

`carrier start --config <path>` launches Carrier as a detached run (its own session, its output in `<folder>/engine/logs/start.log`) and returns once the control socket answers, within 15 seconds (it opens before the engine has recovered the epics that were running, and the panel says `starting` until then); in a Carrier folder where Carrier already runs it says so, does nothing and exits 0, and if it does not come up it prints the end of the log and exits 1. `carrier stop`, `pause`, `resume` and `check` do from any terminal what the panel's `Ctrl+C`, `p` and `r` do (`check` looks at GitHub now) and confirm in one line: exit 0 on success (`stop` also when none runs), 1 when no Carrier runs (or answers), 2 when it speaks another protocol. See [ADR 0010](adr/0010-carrier-runs-in-the-background-as-a-detached-process.md).

`carrier reload` asks the running Carrier to read `engine.json` and `providers.json` again and run on them, without a restart: use it after editing the files by hand (the Mac app asks by itself after each save). It prints `Reloaded` and exits 0; when a file does not match it prints the problem with the key named, exits 1 and Carrier goes on with the settings it had. It also exits 1 when no Carrier runs or when the running one is too old to reload (restart it), and 2 when it speaks another protocol. Which settings follow, and what keeps what it started with: [configuration](configuration.md#changing-the-config-while-carrier-runs).

## Status and the panel

`carrier status` prints the panel of the running Carrier once, from any terminal; exit 0 it runs, 1 it is not running, 2 it speaks another protocol.
`carrier watch` attaches the live panel to it with the same keys as the foreground one, except `q` (and `Ctrl+C`) only leave: Carrier keeps running.
It exits 1 when none runs or when the Carrier it watches stops.
Both show each epic's stage history (running, needing you, or ready for test), asked over the socket, and under a ready-for-test epic that has them a line such as `2 unanswered observations: pass already taken` (or `last round`; [why](troubleshooting.md#an-epic-is-ready-for-test-with-observations-nobody-answered)); on a running card, `retrying in 2m` while an `api_error` waits for its retry ([why](troubleshooting.md#an-epic-waits-before-it-retries)); a Carrier that does not list `sessions` in its hello is drawn from the snapshot alone, and an epic whose request fails is drawn without it.
An epic with several reviewers also shows how many reviewers gave a verdict out of how many are configured, for its latest decided round: `reviewers 1 of 3 gave a verdict` in the dashboard and `reviewers: 1 of 3 gave a verdict` in the plain lines.
Under it each reviewer that gave none has a line with its slot and why (`reviewer-2: ran out of usage`), on a running card, under an epic that needs you and, in the dashboard, under a ready-for-test epic that had fewer verdicts than reviewers, which is ready for test all the same.
An epic with one reviewer shows nothing new, and a round still waiting for a reviewer is not counted.
The same round is an event of the epic (`round_decided`) with the count and the reasons.

The panel is a dependency-free ANSI dashboard: uptime, repos watched and the next check, slots, a card per running epic (stage chain, review round, blockers, time in stage, last activity, links, errors), the queue, epics that need you and the ones ready for test, a hint when it is idle, and below it the epics that ended inside the finished window: DONE (merged) and CANCELLED (closed without a merge, with the stored reason), ten each and a `+N more` line; plain lines when there is no TTY. On a terminal it reads keys; a row is always selected (highlighted), each running card shows a `now` line of what its agent is doing (three lines when selected), and the footer lists only the keys that apply: `↑`/`↓` (or `j`/`k`) select, `enter` opens the PR or issue, `l` shows the agent's output, `r` checks GitHub now, `p` pauses or resumes taking new epics, `?` lists them, `q` quits like `Ctrl+C` (stops Carrier; in `watch` it only leaves).

## Restart a stopped epic

`carrier restart <owner/name>#<issue> [--author <option>] [--reviewer <option>] [--reviewer-2 <option>] [--reviewer-3 <option>] [--reviewer-4 <option>] [--lead <option>] [--from <ship|review|fix>] [--extra-rounds <K>]` resumes an epic in needs-human from the terminal (the `resumeEpic` request of the socket), on the agent option of each role you choose.
In a terminal and without flags it asks for each role the epic has, extra reviewers and lead included, with the current option preselected and the role of the execution that failed marked; without a terminal it keeps the current options.
`--reviewer-2` to `--reviewer-4` and `--lead` name an option for that extra reviewer or the lead; Carrier refuses, with the reason printed, an option the repo does not declare and a role the epic does not have.
A restart that changes the option of one role keeps every other role of the epic, the extra reviewers and the lead included, and the `resumed` event records the options chosen.
A Carrier that does not list `resumeReviewerOptions` in its hello is not asked for those four, and the command says it is too old (restart it).
The same option continues the agent's session with `--resume`; another one starts a new session in the epic's worktree and pull request, rebuilt from SQLite and GitHub like a lost session.
With `--from review` or `--from fix` the epic keeps its round, pull request, worktree and blockers and starts at that stage instead of ship; it still goes through the queue and takes a slot.
Carrier refuses it, with the reason printed, when the epic has no pull request, when the pull request is not open, or, at `fix`, when its head is not the one Carrier saved, since the blockers it hands to the author belong to that head: restart it with `--from review` (which adopts the new head) or from ship then.
At `review` a head that moved is not a refusal: the epic stores the new head and its review starts on it, and the `resumed` event says which head was adopted, from which one.
An epic that stopped on the review limit and is resumed at `review` or `fix` gets more review rounds counted from the round it is at: `limits.maxReviews` of them by default, or `--extra-rounds K` (a positive whole number) of them.
`--extra-rounds` needs `--from review` or `--from fix`, and an epic that stopped on the review limit: it is refused otherwise, with the reason printed.
The epic stops again with `review_limit` when it has used them, and the panel shows its own cap in the round.
`--from ship`, or no `--from`, starts from ship with the review rounds reset, as before.
A Carrier that does not list `resumeFromStage` in its hello is not asked for `--from` or `--extra-rounds`, and the command says it is too old (restart it).
Every restart is an event of the epic, `resumed`, that says a command asked for it and from which stage (`ship` when none is named).
It prints one line and exits 0; a refusal prints the engine's reason and exits 1 (so does no Carrier running), a malformed argument or another protocol exits 2.

## Recover a running epic

`carrier recover <owner/name>#<issue>` asks the running Carrier to continue one epic that is `running` but has no agent alive (the `recoverEpic` request of the socket).
The engine does what it does at start for that epic: it reads the epic's last execution and GitHub, and goes on from there, through the same code as the check's recovery.
It sets no status, stage or round, and it answers once the epic was continued.
It refuses, with the reason printed, when Carrier does not know the epic, when the epic is not `running` (one in `needs-human` is resumed with `carrier restart`), and when an execution of it is alive, or a launch or a retry of it is in flight, so two agents never act on one workspace.
It also refuses while Carrier is still recovering its epics at start (that recovery launches them itself), and when the epic is in a state a recovery does not move, such as a retry that owns it or a stage it has left: nothing is changed and no event is left.
Each use that continued the epic is an event of the epic, `recovered`, that says a command asked for it.
It exits 0 on success and 1 on a refusal, with no Carrier running, or when the running Carrier is too old to list `recoverEpic` (restart it); a malformed argument or another protocol exits 2.

## Chat host

`carrier chat --workspace <folder> [--agent <name>]` opens a conversation (it prints the answer as it streams; `/options` and `/option <id> <value>` show and change the agent's options; `/agent <name>` switches the session to another agent from `chat.json` when it is idle, keeping the transcript and folder, so the next line goes to that agent, and prints the host's words when it refuses, as it does for a working session or the agent it already has; against a host older than this command it says the host has to be restarted; `/quit` leaves and the session stays open (the chat asks after it every 20 seconds while it is at the prompt, and the host closes an idle session that nobody names for ten minutes)), `carrier chat --list [--archived]`, `--archive`, `--unarchive` and `--delete <id>` (deleting leaves nothing of the session; a working one is refused) talk to the chat host, a process of its own that keeps everything in `<folder>/chat/` (the Carrier folder, `~/.carrier` or `CARRIER_HOME`), and starts it detached when none answers. It needs no engine config: with nothing but the Carrier folder it starts, its optional settings are in `<folder>/chat.json` ([configuration](configuration.md#chat-configuration)), and it reads the accounts its agents name from `<folder>/providers.json`, the file the engine reads too. It ends by itself a minute after the last client leaves, or at once with `carrier chat --stop`. The engine and the host run side by side and neither's stop touches the other. `carrier chat-host` runs it in the foreground. See [ADR 0013](adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) and [the spec](specs/chat-host.md).

`carrier usage [--json] [--refresh] [--days <7|14|30>] [--provider <all|claude|codex|agy|local>] [--source <all|epic|chat|external>]` asks the chat host (started on demand, like `carrier chat`; no engine is needed or started) for the live quotas of each account in `providers.json` (the windows used and when they reset, extra credits where the provider shows them) and for what was used over the last 7, 14 or 30 days (default 30): the total, then by model and by workspace, from epic runs, Carrier chats and the sessions the agent CLIs wrote on their own. Quotas are kept for a minute; `--refresh` asks again. Costs are the API price estimated from a bundled table, not what a plan charges, `$0.00` for local servers; a model with no price shows `unpriced` (the Mac app can map or price it). `--json` prints the host's answer as is. It takes no `--config`.

`carrier config` reads one request on standard input as one line of JSON, the request of the chat host's socket without its `id`, and prints the reply the socket would give, without its `id`, as one line of JSON.
For now it takes `editChatSettings` (`{"cmd":"editChatSettings","changes":{"archiveAfterDays":7,"idleCloseMinutes":null}}`): the two ages of the session clock, `worktreeStart` and `idleCloseMinutes` of `chat.json`, where `null` removes a key.
It sends the request to the chat host when one answers and otherwise writes `chat.json` itself with the same code, which edits the file as it is, checks the whole result and renames a temporary file over it, so a refused change leaves the file as it was.
It exits 0 when it saved, 1 when it refused (the reply has the `code` and the key path and kind as `params`) and 2 when standard input is not a request.

## What the engine does

- **Survives interruptions.** SQLite is the source of truth and labels are its mirror; technical failures are retried by a new execution that first verifies the real state (no duplicate PRs, comments or commits); `Ctrl+C` stops the agents but keeps sessions and work; a restart reconciles against GitHub before continuing.
- **Config.** A user JSON file merged over defaults, validated with Zod at startup and on each [reload](configuration.md#changing-the-config-while-carrier-runs) with one error per field; per-repo overrides for identity, agent option and persona; an epic is shared when author and reviewer resolve to the same account, derived from the roles, with no key for it.
- **Polling and queue.** FIFO across repos with pagination, rate-limit and outage handling; one instance per Carrier folder (an exclusive SQLite lock released by the OS on death).
- **Scheduler.** Atomic reservation, configurable concurrency, label management (`running`, `ready-for-test`, `needs-human` are created in each repo if missing).
- **Stages.** Ship, review and fix loops with a typed caller result (`completed`, `changes_requested`, `needs_human`) imported idempotently in a single transaction.
- **Failure handling.** Execution retries with session resume, per-execution timeouts (or `unlimited`), Forge authentication errors that stop only the affected profile, repos removed from config, and a stop rule when the final PR is merged or the epic is closed.
- **Agent runners.** Real adapters for the Claude, Codex and Antigravity (`agy`) CLIs (cloud models, or local ones from LM Studio or Ollama through Claude and Codex) as child processes (session id, resume, output capture, stop, orphan detection), with per-execution credentials and the bot's git identity.
- **Workspaces.** Managed clones in `<folder>/engine/repos/`, and a separate detached checkout for the reviewer in `<folder>/engine/reviews/`; an epic's worktree is found with git, wherever it is.
- **Logging.** [`@ashulab/universal-logger`](https://github.com/AshuLab/universal-logger) to files, with token redaction, and 30-day retention of logs and sessions.
