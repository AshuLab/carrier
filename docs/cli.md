# Command line

Reference for the `carrier` command. The quick tour is in the [README](../README.md); the config file is in [configuration](configuration.md).

| Command | What it does |
|---------|--------------|
| `carrier` | Runs Carrier in this terminal with the live panel until `Ctrl+C`. Reads `~/.carrier/config.json`; `--config <path>` uses another file. One instance per Carrier folder. |
| `carrier init` | Guided setup that writes the config. |
| `carrier doctor` | Checks the config and the machine. |
| `carrier schema` | Prints the config's JSON Schema. |
| `carrier start` / `stop` / `pause` / `resume` / `check` | Run it in the background and control it from any terminal. |
| `carrier status` / `watch` | Show what the running Carrier is doing. |
| `carrier restart` | Resume an epic that stopped in `needs-human`. |
| `carrier chat` / `chat-host` | Talk to an agent in a session. |
| `carrier usage` | Live quotas of your accounts and what was used. |

From a clone, run `pnpm build` and then `node dist/terminal/cli/main.js`, or `node src/terminal/cli/main.ts --config ...` (Node 26 runs the TypeScript directly).

## `carrier init`

It opens by saying what it will ask, then looks at the machine (stopping with the fix if `git`, `gh` or every agent CLI is missing) and shows what it found: each agent CLI with its path, version and login, and the local servers that answer. While it waits for the machine or for GitHub it shows a spinner. Then it asks, in this order:

1. **Repos to watch**, picked from the repos your `gh` login can push to (grouped by owner, with "Load more…" for the next page) or typed. "None for now" is an answer: the config is written with no repos, and Carrier watches nothing until you add one in the file or in the Mac app's Settings.
2. **Accounts.** One account per agent CLI found is added for you, with the login that CLI already has, and written to `~/.carrier/providers.json` (even when `--out` moves the config). You are asked only for **extra** accounts, one at a time, and Enter says no: the CLI, the local server when one is running, and for Claude and Codex the config folder (the `~/.claude`, `~/.claude-*` and `~/.codex` it finds with their login state, the environment, or a typed path; Antigravity has none), then a name that must be a lowercase word and unique.
3. **GitHub identities.** A short note explains what they are, then each role picks a bot of Agent Forge or your own `gh` login. Picking the same one twice is accepted, and the recap then says the signature will show it. If there is no bot it can run `agent-forge add` for you on the spot.
4. **Each role** (author, reviewer, and a lead reviewer if you say yes; Enter says no): the account that runs it, its model, its effort (`low`, `medium`, `high`, `xhigh` or `max`, or the CLI's own, which writes nothing) and an optional persona (a name and a prompt, each skippable).
5. **Failover**, with two or more accounts: for each role, whether to turn it on (Enter says no) and up to two steps, each an account and a model (the `failover` block).
6. **Where to save**: `~/.carrier/config.json` (one global file per user), or another file with `--out`.

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

`carrier doctor` verifies the tools are installed, that each identity can get a token for each repo, that the orchestrator can read it, and that each repo it could read has the Solve labels (`solve:epic` and `solve:epic:ready`; the fix is to run `solve:setup` in the repo). It checks a config of yours or a hand-written one at any time. `carrier schema` prints the JSON Schema of the config for your editor.

`carrier doctor --json` prints the checks as a JSON array (`{ name, status, detail?, fix?, repo?, profiles? }`, `status` `ok`, `warn` or `fail`; `repo` and `profiles`, the names under `config.profiles` the check stands for, are set together on the checks about one repo) and nothing else, with the same exit code (1 when any fails); the macOS app's Health tab reads it.

## Writing the config by hand

See [configuration](configuration.md): the minimal file, every field with its default, and `providers.json`. Invalid configs print every error with its field and exit without starting anything.

## Run without a terminal

`carrier start --config <path>` launches Carrier as a detached run (its own session, its output in `<folder>/engine/logs/start.log`) and returns once the control socket answers, within 15 seconds; in a Carrier folder where Carrier already runs it says so, does nothing and exits 0, and if it does not come up it prints the end of the log and exits 1. `carrier stop`, `pause`, `resume` and `check` do from any terminal what the panel's `Ctrl+C`, `p` and `r` do (`check` looks at GitHub now) and confirm in one line: exit 0 on success (`stop` also when none runs), 1 when no Carrier runs (or answers), 2 when it speaks another protocol. See [ADR 0010](adr/0010-carrier-runs-in-the-background-as-a-detached-process.md).

## Status and the panel

`carrier status` prints the panel of the running Carrier once, from any terminal; exit 0 it runs, 1 it is not running, 2 it speaks another protocol. `carrier watch` attaches the live panel to it with the same keys as the foreground one, except `q` (and `Ctrl+C`) only leave: Carrier keeps running. It exits 1 when none runs or when the Carrier it watches stops. Both show each epic's stage history (running, needing you, or ready for test), asked over the socket; a Carrier that does not list `sessions` in its hello is drawn from the snapshot alone, and an epic whose request fails is drawn without it.

The panel is a dependency-free ANSI dashboard: uptime, repos watched and the next check, slots, a card per running epic (stage chain, review round, blockers, time in stage, last activity, links, errors), the queue, epics that need you and the ones ready for test, a hint when it is idle, and below it the epics that ended inside the finished window: DONE (merged) and CANCELLED (closed without a merge, with the stored reason), ten each and a `+N more` line; plain lines when there is no TTY. On a terminal it reads keys; a row is always selected (highlighted), each running card shows a `now` line of what its agent is doing (three lines when selected), and the footer lists only the keys that apply: `↑`/`↓` (or `j`/`k`) select, `enter` opens the PR or issue, `l` shows the agent's output, `r` checks GitHub now, `p` pauses or resumes taking new epics, `?` lists them, `q` quits like `Ctrl+C` (stops Carrier; in `watch` it only leaves).

## Restart a stopped epic

`carrier restart <owner/name>#<issue> [--author <option>] [--reviewer <option>]` resumes an epic in needs-human from the terminal (the `resumeEpic` request of the socket), on the agent option of each role you choose. In a terminal and without flags it asks for each role, with the current option preselected and the role that failed marked; without a terminal it keeps the current options. The same option continues the agent's session with `--resume`; another one starts a new session in the epic's worktree and pull request, rebuilt from SQLite and GitHub like a lost session. It prints one line and exits 0; a refusal prints the engine's reason and exits 1 (so does no Carrier running), a malformed argument or another protocol exits 2.

## Chat host

`carrier chat --workspace <folder> [--agent <name>]` opens a conversation (it prints the answer as it streams; `/quit` leaves and the session stays open), `carrier chat --list [--archived]`, `--archive`, `--unarchive` and `--delete <id>` (deleting leaves nothing of the session; a working one is refused) talk to the chat host, a process of its own that keeps everything in `<folder>/chat/` (the Carrier folder, `~/.carrier` or `CARRIER_HOME`), and starts it detached when none answers. It needs no engine config: with nothing but the Carrier folder it starts, its optional settings are in `<folder>/chat/chat.json` ([configuration](configuration.md#chat-configuration)), and it reads the accounts its agents name from `<folder>/providers.json`, the file the engine reads too. It ends by itself a minute after the last client leaves, or at once with `carrier chat --stop`. The engine and the host run side by side and neither's stop touches the other. `carrier chat-host` runs it in the foreground. See [ADR 0013](adr/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) and [the spec](specs/chat-host.md).

`carrier usage [--json] [--refresh] [--days <7|14|30>] [--provider <all|claude|codex|agy|local>] [--source <all|epic|chat|external>]` asks the chat host (started on demand, like `carrier chat`; no engine is needed or started) for the live quotas of each account in `providers.json` (the windows used and when they reset, extra credits where the provider shows them) and for what was used over the last 7, 14 or 30 days (default 30): the total, then by model and by workspace, from epic runs, Carrier chats and the sessions the agent CLIs wrote on their own. Quotas are kept for a minute; `--refresh` asks again. Costs are the API price estimated from a bundled table, not what a plan charges, `$0.00` for local servers; a model with no price shows `unpriced` (the Mac app can map or price it). `--json` prints the host's answer as is. It takes no `--config`.

## What the engine does

- **Survives interruptions.** SQLite is the source of truth and labels are its mirror; technical failures are retried by a new execution that first verifies the real state (no duplicate PRs, comments or commits); `Ctrl+C` stops the agents but keeps sessions and work; a restart reconciles against GitHub before continuing.
- **Config.** A user JSON file merged over defaults, validated with Zod at startup with one error per field; per-repo overrides for identity, agent option and persona; an epic is shared when author and reviewer resolve to the same account, derived from the roles, with no key for it.
- **Polling and queue.** FIFO across repos with pagination, rate-limit and outage handling; one instance per Carrier folder (an exclusive SQLite lock released by the OS on death).
- **Scheduler.** Atomic reservation, configurable concurrency, label management (`running`, `ready-for-test`, `needs-human` are created in each repo if missing).
- **Stages.** Ship, review and fix loops with a typed caller result (`completed`, `changes_requested`, `needs_human`) imported idempotently in a single transaction.
- **Failure handling.** Execution retries with session resume, per-execution timeouts (or `unlimited`), Forge authentication errors that stop only the affected profile, repos removed from config, and a stop rule when the final PR is merged or the epic is closed.
- **Agent runners.** Real adapters for the Claude, Codex and Antigravity (`agy`) CLIs (cloud models, or local ones from LM Studio or Ollama through Claude and Codex) as child processes (session id, resume, output capture, stop, orphan detection), with per-execution credentials and the bot's git identity.
- **Workspaces.** Managed clones in `<folder>/engine/repos/`, and a separate detached checkout for the reviewer in `<folder>/engine/reviews/`; an epic's worktree is found with git, wherever it is.
- **Logging.** [`@ashulab/universal-logger`](https://github.com/AshuLab/universal-logger) to files, with token redaction, and 30-day retention of logs and sessions.
