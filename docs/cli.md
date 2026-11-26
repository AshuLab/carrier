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

It opens by saying what it will ask, then looks at the machine (stopping with the fix if `git`, `gh` or every agent CLI is missing) and shows what it found: each agent CLI with its path, version and login, and the local servers that answer.
While it waits for the machine or for GitHub it shows a spinner.
Then it asks, in this order:

1. **Accounts.** One account per agent CLI found is added for you, with the login that CLI already has, and written to `~/.carrier/providers.json` (even when `--out` moves the config).
   The accounts that file already holds are kept as they are: what is found is added to them and nothing is replaced or removed.
   You are asked only for **extra** accounts, one at a time, and Enter says no: the CLI, the local server when one is running, and for Claude and Codex the config folder (the `~/.claude`, `~/.claude-*` and `~/.codex` it finds with their login state, the environment, or a typed path; Antigravity has none), then a name that must be a lowercase word and unique.
2. **The orchestrator's GitHub profile.** A short note explains what a profile is, then you pick a bot of Agent Forge or your own `gh` login for the orchestrator, which only reads issues and PRs and changes labels.
   If there is no bot it can run `agent-forge add` for you on the spot.
3. **One block for each role**, closed before the next one starts: the author, the reviewer, any extra reviewers, and a lead reviewer if you say yes at "Add a lead reviewer?" (Enter says no).
   After the reviewer it asks "Add another reviewer?" (Enter says no); each yes opens a block for an extra reviewer that starts with its **name**, which is required and has no suggestion (a blank answer, or a name another extra reviewer has, asks again), and its **type**, a slug that starts on `general` (`security`, `ux`, anything else you write), and goes on with the questions below; after the third it is not asked again.
   The extra reviewers are written to `agents.extraReviewers` as a map in that order, each under a key `init` derives from its name (`Seguridad API` is `seguridad-api`; see [configuration](configuration.md#extra-reviewers-and-the-lead-reviewer)); one with no failover steps has no `failover` key and so uses the reviewer's.
   Going back with Esc to an extra reviewer's block and changing its name keeps the answers to the block's other questions.
   The lead reviewer comes after all of them.
   Each block asks, in this order:
   - The GitHub profile the role acts as: a bot of Agent Forge or your own `gh` login.
     Picking the same one for two roles is accepted, and the recap then says the signature will show it.
   - The account that runs it (not asked when there is only one).
   - "Model and effort: `<model>` at `<effort>`, change them?", with Enter meaning no.
     A yes opens the model and then the effort (`low`, `medium`, `high`, `xhigh` or `max`, or the CLI's own, which writes nothing).
   - "Customise the persona?", with Enter meaning no.
     A yes asks a name and a prompt, each skippable.
   - The failover, only with two or more accounts: whether to turn it on (Enter says no) and up to two steps, each an account and a model (the `failover` block).
     With one account the block prints one line saying that failover needs a second account and asks nothing.

   With every default accepted a role costs its profile, its account and Enter for the rest.
   Claude starts on `sonnet` at `high`.
   Codex starts on the model in its own `config.toml`, or the first model it lists, at `high`.
   Antigravity starts on `gemini-4-hydrogen-high`, or the first model `agy models` lists, with no effort because the effort is in the id.
4. **Repos to watch**, last because nothing about a role needs them: picked from the repos your `gh` login can push to (grouped by owner and shown as `owner/name`, with "Load more…" for the next page) or typed.
   "None for now" is an answer: the config is written with no repos, and Carrier watches nothing until you add one in the file or in the Mac app's Settings.
5. **Where to save**: `~/.carrier/engine.json` (one global file per user), or another file with `--out`.

Before saving it shows a recap with three choices: save, **change an answer** or cancel; nothing is written until you save.
"Change an answer" shows a menu of the AI accounts, the orchestrator, each role (author, reviewer, the extra reviewers there are and the next one to add, lead reviewer) and the repos: you pick one, `init` asks only that block's questions starting from its current answers, and every other block keeps its answers.
In `init` **Esc goes back one question** (at the start of a block, to the last question of the one before) and shows it with the answer it had; every answer already given stays, and going back does not run the GitHub or CLI calls (listing repos, adding an Agent Forge bot) again.
At the very first question Esc leaves, like Ctrl+C.
At the recap, Esc at "Which part do you want to change?" goes back to "Save it?", and Esc at the first question of a block you jumped to goes back to the recap with that block as it was.
**Ctrl+C leaves** from any question, with nothing written before Save.
`restart`, which asks its options through the same prompts, leaves on Esc as well as on Ctrl+C.
It then runs the checks of `carrier doctor`, printing only what fails (otherwise a single count), shows how many epics are waiting, and offers to start Carrier.
Ctrl+C (or Esc) at that last question, once the config is saved and checked, counts as no: it prints the closing line with what to run (`carrier`, with `--config` when the file is not the global one), exits 0, and the saved files stay.
While `init` runs, the log lines of the checks go to `engine/logs/orchestrator.log` in the Carrier folder and never to the screen.

Run again on an existing config, it offers to edit it (its answers are the starting points), start over, save a new one in another file, or leave it.
Editing keeps the accounts of `providers.json` and lets you add more (editing or removing one is done in the file), starts each role's model, effort, persona and lead reviewer from the file, and asks whether to keep the failover steps it has; `-` in a persona field clears it.
Editing keeps the rest of the file: `engine.json` is written as it is, with only the keys the wizard asks replaced.
Those are `repos` (a repo you keep keeps its entry and its per-repo overrides, a repo you leave out is dropped, a new one is `{ "name": "owner/name" }`), `profiles` (the ones you picked are set over the file's), `orchestratorProfile`, the failover of the author, the reviewer and the lead reviewer (`failover.triggers` stays), and each of those roles' `profile`, `provider`, `model`, `effort` and `persona`.
`agents.extraReviewers` is owned too: each extra reviewer in the file's map is walked in the order of the map as a block starting from its name, its type and its other values, "Keep `<name>`?" starts on Yes while the file has one more, and a No drops that reviewer and the ones after it.
The map is replaced by the answers: an extra keeps its key, even when you change its name, and the keys the wizard does not ask, such as its `skills` and the failover steps you keep; the key is removed when there are none.
Everything else survives: `limits`, `labels`, `skills`, `logLevel`, `pollIntervalMinutes`, `finishedWindowDays` and a role's own `skills`; a lead reviewer you decline is removed.
"Start over", a new file and `--out` to another file are written whole from the answers.
A config that does not validate is not edited: the wizard prints its first error (path and message) and asks whether to start over, save a new one in another file or leave it, and writes nothing until you answer.
A file whose `agents.extraReviewers` is still a list is one of them: the error names the map it needs.
With `--yes` it replaces the file, as the flag says, and prints that first error.
`--config` is not a flag of `init`: it exits 2 and writes nothing, because `init` writes where `--out` says.

Every question has a flag (`carrier init --help`), and they all follow one pattern, with `<role>` one of `author`, `reviewer` and `lead-reviewer`:

| Flag | Answers |
|---|---|
| `--repo <owner/name>` | The repos to watch; repeat it for several. |
| `--orchestrator-profile <forge:<agent>\|gh>` | The orchestrator's GitHub profile; without it, and when both `--author-profile` and `--reviewer-profile` are given or `--yes` is, no question asks it: it is the file's own when editing, else the author's. |
| `--<role> <harness>:<model>` | The role's account and model; it adds an account named after its harness to `providers.json` (the one found, when it matches). |
| `--<role>-profile <forge:<agent>\|gh>` | The GitHub profile the role acts as. |
| `--<role>-provider <lmstudio\|ollama>` | The local server that runs the role's model. |
| `--<role>-effort <level>` | `low`, `medium`, `high`, `xhigh` or `max`. |
| `--<role>-persona-name <text>`, `--<role>-persona-prompt <text>` | The persona, within the schema's limits. |
| `--<role>-failover <account>[:<model>]` | One failover step; repeat it, in order, for up to two. |

With `--author` and `--reviewer` both given, the extra-accounts question and every role's failover question are skipped, and the failover steps the file has stay (a `--<role>-failover` flag still sets its role's steps).
An extra reviewer has no flags: the ones that named it by its place (`--reviewer-2` to `--reviewer-4` and their companions) are gone, so `--yes` creates no extra reviewer, and flags that name one by its name are not there yet.

The failover step is split at the first colon, so `--author-failover claude:llama3:8b` is the account `claude` with the model `llama3:8b`; a step with no model uses the account's, then the harness's.
The account must be one found on this Mac or already in `providers.json` (or one a `--<role>` flag declares).
A role given failover flags is not asked its failover, and the steps replace the ones the file had.
`--yes` never asks and needs at least one `--repo`, so an agent can run it too (`--author-profile gh --reviewer-profile gh` makes both roles your `gh` login):

```bash
carrier init --yes --repo AshuLab/my-repo \
  --author-profile forge:<agent-1> --author claude:<model> \
  --reviewer-profile forge:<agent-2> --reviewer codex:<model>
```

`--yes` asks nothing, so it prints, before the checks run, the same recap the wizard shows before saving: the orchestrator's profile, for each role its profile, account, model and effort, and where the files go.
Without a terminal and without `--yes`, a config file that is already there is not replaced: `init` exits 1 and says to use `--yes` to replace it or `--out` to write another file.

Without `--author` and `--reviewer`, `--yes` gives the author the first account found and the reviewer another one when there is one, each with the model the wizard would suggest; the flags above choose them.

## `carrier doctor` and `carrier schema`

`carrier doctor` verifies the tools are installed, that each profile can get a token for each repo, that the orchestrator can read it, and that each repo it could read has the labels Carrier reads (`labels.epic` and `labels.ready`, by default `solve:epic` and `solve:epic:ready`; the fix is to run `solve:setup` in the repo).
It checks a config of yours or a hand-written one at any time.
`carrier schema` prints the JSON Schema of the config for your editor.

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

`carrier start --config <path>` launches Carrier as a detached run (its own session, its output in `<folder>/engine/logs/start.log`) and returns once the control socket answers, within 15 seconds (it opens before the engine has recovered the epics that were running, and the panel says `starting` until then); in a Carrier folder where Carrier already runs it says so, does nothing and exits 0, and if it does not come up it prints the end of the log and exits 1. `carrier stop`, `pause`, `resume` and `check` do from any terminal what the panel's `Ctrl+C`, `p` and `r` do (`check` looks at GitHub now) and confirm in one line: exit 0 on success (`stop` also when none runs), 1 when no Carrier runs (or answers), 2 when it speaks another protocol. See [ADR 0010](adr/orchestration/0010-carrier-runs-in-the-background-as-a-detached-process.md).

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

`carrier restart <owner/name>#<issue> [--author <option>] [--reviewer <option>] [--lead <option>] [--from <ship|review|fix>] [--extra-rounds <K>]` resumes an epic in needs-human from the terminal (the `resumeEpic` request of the socket), on the agent option of each role you choose.
In a terminal and without flags it asks for each role the epic has, extra reviewers and lead included, with the current option preselected and the role of the execution that failed marked; without a terminal it keeps the current options.
`--author`, `--reviewer` and `--lead` name an option for that role, and an extra reviewer has no flag (the terminal asks about it); Carrier refuses, with the reason printed, an option the repo does not declare and a role the epic does not have.
A restart that changes the option of one role keeps every other role of the epic, the extra reviewers and the lead included, and the `resumed` event records the options chosen.
A Carrier that does not list `resumeReviewerOptions` in its hello is not asked for the extra reviewers and the lead, and the command says it is too old (restart it).
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

`carrier chat --workspace <folder> [--agent <name>]` opens a conversation (it prints the answer as it streams; `/options` and `/option <id> <value>` show and change the agent's options; `/agent <name>` switches the session to another agent from `chat.json` when it is idle, keeping the transcript and folder, so the next line goes to that agent, and prints the host's words when it refuses, as it does for a working session or the agent it already has; against a host older than this command it says the host has to be restarted; `/quit` leaves and the session stays open (the chat asks after it every 20 seconds while it is at the prompt, and the host closes an idle session that nobody names for ten minutes)), `carrier chat --list [--archived]`, `--archive`, `--unarchive` and `--delete <id>` (deleting leaves nothing of the session; a working one is refused) talk to the chat host, a process of its own that keeps everything in `<folder>/chat/` (the Carrier folder, `~/.carrier` or `CARRIER_HOME`), and starts it detached when none answers. It needs no engine config: with nothing but the Carrier folder it starts, its optional settings are in `<folder>/chat.json` ([configuration](configuration.md#chat-configuration)), and it reads the accounts its agents name from `<folder>/providers.json`, the file the engine reads too. It ends by itself a minute after the last client leaves, or at once with `carrier chat --stop`. The engine and the host run side by side and neither's stop touches the other. `carrier chat-host` runs it in the foreground. See [ADR 0013](adr/sessions/0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md) and [the spec](specs/chat-host.md).

`carrier usage [--json] [--refresh] [--days <7|14|30>] [--provider <all|claude|codex|agy|local>] [--source <all|epic|chat|external>]` asks the chat host (started on demand, like `carrier chat`; no engine is needed or started) for the live quotas of each account in `providers.json` (the windows used and when they reset, extra credits where the provider shows them) and for what was used over the last 7, 14 or 30 days (default 30): the total, then by model and by workspace, from epic runs, Carrier chats and the sessions the agent CLIs wrote on their own. Quotas are kept for a minute; `--refresh` asks again. Costs are the API price estimated from a bundled table, not what a plan charges, `$0.00` for local servers; a model with no price shows `unpriced` (the Mac app can map or price it). `--json` prints the host's answer as is. It takes no `--config`.

`carrier config` changes one setting of a Carrier folder file from one line of JSON: see [`carrier config`](#carrier-config).

## `carrier config`

`carrier config` changes one setting of the Carrier folder (`CARRIER_HOME`, else `~/.carrier`; it takes no `--config`).
It is how the Mac app saves when the process that owns the file is not running, and it works from a terminal too ([who writes each file](configuration.md#who-writes-each-file), [ADR 0053](adr/config/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)).

- The request is one line of JSON on standard input: the request of the owner's socket without its `id`, such as `{"cmd":"editChatSettings","changes":{"archiveAfterDays":7,"idleCloseMinutes":null}}` (`null` removes a key).
- The reply is one line of JSON on standard output, the one the socket would give without its `id`: `{"ok":true,"data":{...}}`, or `{"ok":false,"error":"...","code":"...","params":{...}}` for a refusal.
- It forwards the request to the process that owns the file when that one answers its socket and lists the `config` capability, and otherwise writes the file itself with the same code: it edits the raw file, validates the whole result with the file's strict schema and renames a temporary file over it, so a refused change leaves the file as it was.
- The exit code is 0 when it saved, 1 when it refused (`code` and `params` say what: `config.problem` carries the key path and the kind of problem) and 2 when it could not run (standard input is not JSON, or not a request of the list below: `request.invalidJson` or `request.invalid`).
- `carrier init` writes `engine.json` and `providers.json` through the same code.

The chat host owns the files of its fifteen requests.
For `chat.json`: `editChatSettings` (`archiveAfterDays`, `deleteAfterDays`, `worktreeStart`, `idleCloseMinutes`) and `setProjectsFolder { folder }`.
For `providers.json`:
`setAccounts` (`{"accounts":[{"name":"agy","harness":"agy"}]}`, adds each account),
`addAccount` (`{"account":{"name":"claude-work","harness":"claude","configDir":"~/.claude-work"}}`),
`editAccount` (`{"name":"claude-work","changes":{"displayName":"Work","icon":null}}`),
`removeAccount` (`{"name":"claude-work"}`, refused while a role, a repo override, a failover list or a chat agent names it) and
`setTextGenerator` (`{"choice":{"server":"ollama","model":"qwen3:8b"}}`, `{"choice":null}` clears it).
For `projects.json`:
`addProject { folder }`, `removeProject { path }`, `editProject { path, key, value }` (`key` is `name`, `pinned` or `hidden`), `moveProject { path, folder }`, `editProjectIcon { path, changes }`, `editProjectDefaults { path, changes }`, `editProjectTags { path, add, remove }` and `setProjectActions { path, actions }`.

The engine owns `engine.json`, through its nine requests:
`setWatchedRepos { repos }`, `editBehavior { changes }`, `editRole { role, changes }`, `editRepoRole { repo, role, fields }` (`fields: null` removes the override), `editPersona { role, name, prompt }`, `editFailover { role, first, second }`, `setLeadReviewer { draft }` (`draft: null` turns it off), `setOrchestratorProfile { name }` and `addExtraReviewer { draft }` (the draft has `name`, `type`, `identity`, `provider`, `model` and an optional `effort`; the key is derived from the name and never sent).

A reply that saved has `saved`, the part of the file it changed (`addProject` also says `added`, `removeProject` says `removed`).
For `engine.json` and `providers.json` it also has `engine`: `applied` when the running engine read the file again, `refused` (with its `reason` for `engine.json`, `engineReason` for `providers.json`: words, code and params) when it kept its settings and the file is saved all the same, and `notRunning` when no engine answers.

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
