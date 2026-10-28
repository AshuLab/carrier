# An epic runs on the agent option you choose, and can switch when one runs out of credits

Status: spec

## Problem

Carrier runs every agent with the environment of the process that started it, so everything it runs uses one Claude login. It happened for real: the login ran out of credits in the middle of an epic, the execution ended as `usage_limit`, the engine retried it in seconds, burned every retry and stopped the epic in needs-human. The person had credits on another Claude login, and on Codex and Antigravity, and could not use any of them without restarting Carrier under another environment, which would not move the epic anyway.

The same hurts before an epic starts: when Diego already knows a login is nearly out and has a new epic, he cannot say which login should run it. We know it is fixed when he can start an epic on a chosen option, and when a stopped epic can be resumed on a different one, in the same worktree, in a few clicks.

## Solution

### The directory of agent options

The config gets a directory, `agentOptions`: each entry is a name and the way to run an agent, `harness`, `model`, `provider?` as they are today under `agents.<role>`, plus a new `configDir?`, the harness's config folder (`CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex). The folder holds the login, so it is what picks the account. A second Claude login, Codex and Antigravity are four interchangeable options. Each role keeps its `profile` (the GitHub identity) and its `persona` and now points at an option by name, the way it points at a profile.

```jsonc
"agentOptions": {
  "claude-ashu":     { "harness": "claude", "model": "opus", "configDir": "~/.claude-ashu-lab" },
  "claude-personal": { "harness": "claude", "model": "opus", "configDir": "~/.claude" },
  "codex":           { "harness": "codex",  "model": "<model>" }
},
"agents": {
  "author":   { "profile": "author-bot",   "option": "claude-ashu" },
  "reviewer": { "profile": "reviewer-bot", "option": "codex" }
},
"failover": { "enabled": false, "order": ["claude-personal", "codex"] }
```

A repo's `agents.<role>` can still override `profile`, `option` and `persona`. An option without `configDir` inherits the environment, as every agent does today. The names are lowercase words, so they are safe to store and show. The old shape, with `harness` and `model` inside `agents.<role>`, is refused by the loader with a message that says they moved to `agentOptions` and where the docs are; there is no migration and no second way to say the same thing. `carrier init` writes the new shape, in the section described below.

### The choice

The epic stores one option name per role, and the definitions are frozen with the rest of the effective config when the epic is reserved, so editing the config later moves no running epic. When the config has two or more options and an epic is reserved, the engine does not start the author at once: it marks the epic as waiting for its choice, with a deadline from `limits.optionChoiceSeconds` (default 60). The panel, in the foreground run and in `carrier watch`, shows that epic with a countdown and a line per role with the role's default option; `o` lets the person change a role's option with the arrow keys and `enter` starts the epic with what is shown, and `a` is **Automatic**, which starts it with the defaults now. The deadline passing, no panel being open, a non-interactive `watch`, or an engine restart with a deadline already gone starts the epic with the defaults. The wait holds the epic's slot, since it is short. With one option nothing is asked.

A stopped epic is resumed from the terminal with a new command, `carrier restart <owner/repo>#<issue>`, because `carrier resume` already means taking the queue off pause and `retry` is the glossary's word for repeating an execution. It does what `resumeEpic` does, which today only the macOS app can ask for, and takes `--author <option>` and `--reviewer <option>`; with neither flag, in a terminal, it asks for each role with the role's current option preselected and the one that failed marked, and with no terminal it keeps the current options. It prints the engine's reason when it is refused and exits 1, as the other commands do when Carrier cannot do what was asked. Restarting with the same option continues the agent's session with `--resume`. Resuming with another one starts a new session of the role and rebuilds its context from SQLite and GitHub, the way a lost session is rebuilt today, in the epic's existing worktree and pull request. The conversation of the agent is lost, the work is not.

The control socket gets `chooseOptions` for the start and an optional `author` and `reviewer` on `resumeEpic`, both under a new capability, `agentOptions`; the `epic` reply lists the options, each role's option and, while waiting, the deadline. An engine without the capability cannot be asked, and a client that does not see it offers no choice. The macOS app is not touched in this epic; it can use the same requests when it is worked on.

### Credits running out

A `usage_limit` failure no longer burns the retries. It does not count in the failure streak, like a timeout, and it does not relaunch the same option. The epic stops in needs-human at once with a new kind, `usage_limit`, that names the option that ran out and the reset time the agent printed, and the epic's line in the panel and `carrier status` say to pick another option with `carrier restart`.

Claude already reports the failure kind; Codex and Antigravity get it in this epic, from what [the research](../research/agent-usage-limit-signals.md) found. Codex says it in text only: a run that hit its limit ends with a `turn.failed` and exit 1, which every failed turn shares, so the adapter matches only the final `turn.failed`, never the `error` events before it, and only a message that starts with `You've hit your usage limit`, `You hit your spend cap`, `Your workspace is out of credits` or `Quota exceeded.`. A transient rate limit is retried inside Codex and does not match, and any other `turn.failed` stays `api_error`. The reset time is a local-time string at the end of the message, kept as the detail and never computed on. Antigravity ends with a `result` whose `status` is `ERROR`, and the adapter matches its `error` against `AI credits balance is too low`, `individual quota reached` or `exhausted your quota`; it carries no reset time. Antigravity's own `agy -p "/usage" --output-format json` does give the remaining fraction and the reset time of each quota at no cost, which is what a later "the option with the most credits" would read, and is not used here.

Failover is the opt-in version of that. With `failover.enabled` the engine, instead of stopping, moves the role of the failed execution to the next name in `failover.order` that has not already ended on `usage_limit` in this epic, rebuilds the session, runs the stage again and records an `option_switched` epic event with the role, the two options and the stage. The list is an allowlist: it never moves to an option that is not in it. When none is left the epic stops with `usage_limit` and names each option that ran out. The engine remembers nothing about an option across epics, so the epic after one that ran out pays one failed attempt on its first execution.

### The wizard

`carrier init` gets a section of its own before the roles, **Agent options**, where Diego adds the options one at a time and the roles then only choose among the ones already created. Each option asks for the harness among the installed ones, the provider when there is a local one (as the role question does today), the model, and for Claude and Codex the config folder: it offers the folders it finds (`~/.claude`, `~/.claude-*`, `~/.codex`) with their login state, the harness's default as "inherit the environment", and a typed path. A name is suggested from the harness and the folder and must be unique and a lowercase word. After each option it asks whether to add another. The role questions that ask for the harness, provider and model are replaced by one question per role, which option runs it, a choice among the created ones. With two or more options it then asks whether to turn failover on and, if so, in which order. Running `init` again on an existing config keeps its options and lets Diego add more; editing or removing one is done in the file. The flags `--author` and `--reviewer`, `<harness>:<model>`, and the provider flags keep answering non-interactively by declaring one option for that role, named after its harness, so `init` still runs unattended.

### Where the folder is read back

Each execution records the option it ran on and its `configDir`, next to the harness, model and provider it already records. The resume descriptor takes `configDir` from there, and Continue in Terminal, which already builds `CLAUDE_CONFIG_DIR=… claude --resume` and `CODEX_HOME=… codex resume` from it, now has the real folder. The 30-day cleanup looks for each session in the folders of the executions that wrote it, plus the environment's own for rows that predate the column. `carrier doctor` gets a check per option: `claude auth status` with the option's `CLAUDE_CONFIG_DIR` and `codex login status` with its `CODEX_HOME`, both of which answer without interaction (verified: `~/.claude-ashu-lab` is logged in and `~/.claude` is not; Codex refuses a `CODEX_HOME` that does not exist). Antigravity has no such command, so the check runs `agy -p "/usage" --output-format json` in a throwaway folder, with stdin closed and an inert `BROWSER`: logged in it answers in about five seconds with `status: "SUCCESS"`, and logged out it prints `Authentication required` on stderr and then waits 62 seconds before failing, so doctor calls it logged out at that first line and kills the process, without logging the login URL. A token file is not a test, because agy may keep its token in the keychain. A role's option that is not logged in is a failure, any other option a warning.

Antigravity has no environment variable for its config folder: its state lives under `~/.gemini/antigravity-cli` and follows `HOME`, and `~/.antigravity` belongs to the IDE. So an Antigravity option cannot have a `configDir`, the loader refuses it, and two Antigravity logins are not supported.

What lost. A global active account, because a running epic would change account in silence and concurrent epics could not differ. Choosing only a Claude folder, because it does not cover credits left on another provider. Keeping `harness` and `model` in `agents.<role>` and adding an `options` block next to them, because it leaves two ways to say the same thing for the sake of not editing one file. Failover to any option, because it would send a private repo's code to another provider and spend another account unasked. Copying the session file between folders, because it does not cross harnesses and the rebuild exists. Remembering exhausted options across epics, because the reset time is only text and the memory would go stale. The decisions are in [ADR 0014](../adr/0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md).

## Scope

1. As Diego, I declare agent options in the config and each role points at one; a config with the old shape is refused with a message that says where `harness` and `model` went.
2. As Diego, a Claude option with a `configDir` runs its agents with that `CLAUDE_CONFIG_DIR`, a Codex one with `CODEX_HOME`, and an option without one inherits the environment as today.
3. As Diego, when there are two or more options and an epic is about to start, the panel shows it with a countdown and the option of each role, and `o` then `enter` starts it on what I chose.
4. As Diego, `a`, the deadline passing, or no panel open starts the epic on the role defaults; with one option I am never asked.
5. As Diego, `carrier restart <owner/repo>#<issue>` resumes a stopped epic, asks for the option of each role in a terminal and marks the role that failed, and takes `--author` and `--reviewer` to skip the questions.
6. As Diego, restarting on the same option continues the agent's session, and restarting on another one starts a new session in the epic's existing worktree and pull request.
7. As Diego, a `usage_limit` stops the epic at once in needs-human, naming the option that ran out and the reset time, and spends none of the retries.
8. As Diego, with failover on, a role that runs out of credits moves to the next option in `failover.order` and the epic goes on, and the epic's history says from which option to which.
9. As Diego, failover is off until I turn it on, never moves to an option outside `order`, and when every option in it has run out the epic stops and names each one.
10. As Diego, each execution records its option and folder, the 30-day cleanup finds its session there, and Continue in Terminal opens with that folder.
11. As Diego, `carrier doctor` tells me for each option whether its login works, Claude, Codex and Antigravity alike.
12. As Diego, in `carrier init` I add my agent options in a section of their own, and then each role picks one of them, so the config comes out in the new shape without editing JSON.
13. As Diego, a Codex or Antigravity run that ends on its usage limit is recorded as `usage_limit`, as a Claude run is, so the stop and the failover work for every harness.

## Decisions

- The shape of the config, the choice, and failover are in [ADR 0014](../adr/0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md); the sketch above is the shape of the files.
- An option's `configDir` must be an absolute path after `~` is expanded and only a Claude or Codex option may have one; `provider` keeps its current rule: Antigravity cannot have one. `failover.order` has no duplicates and every name must be declared. An unknown option name in `agents` or in a repo override is a load error, as an unknown profile is.
- `epics` gets `authorOption`, `reviewerOption` and `choiceDeadline`; `executions` gets `option` and `configDir`; `needsHumanKinds` gets `usage_limit`. All are nullable so existing rows keep reading.
- An execution resumes with `--resume` only when the session was written by the option the role runs on now; otherwise it takes the path of `session_lost`.
- Testing seams, broadest first. Story 1 and the config rules: `loadConfig` and `resolveRepoConfig` in `src/config/load.test.ts` and `resolve.test.ts`. Story 2: the adapters' command, `AgentCommand.env`, in `claude.test.ts` and `codex.test.ts`. Stories 3, 4 and 6: `engine.test.ts` with the fake runner and clock, driven through reserve, `chooseOptions` and `resumeEpic`, observing the options the runner gets and whether `resumeSession` is set, plus `server.test.ts` for the request schema and capability; the panel's keys in `interactive.test.ts` and `ui-state.test.ts` with a fake output, keys and controls. Story 5: the end-to-end style of `src/terminal/cli/main.test.ts`, which runs the real process, for the command, its flags, its refusals and its exit code, and `args.test.ts` for the argument. Stories 7 to 9: `engine.test.ts` with a runner that fails as `usage_limit`, next to the retry tests; the adapter's detection already has `claude-usage-limit.fixture.jsonl`. Story 12: `wizard.test.ts`, `agent.test.ts` and `build-config.test.ts` with the wizard's fake prompts, including the flags path and a re-run on an existing config. Story 13: `codex.test.ts` and `agy.test.ts` through each adapter's line parser, with `codex-usage-limit.fixture.jsonl` and `agy-usage-limit.fixture.jsonl`, each also checked against a plain `turn.failed` or `ERROR` result that must stay `api_error`; both fixtures are constructed from the sources, not captured, and the Antigravity one is replaced by a real capture when someone has one. A Codex message that changes wording in a later version falls to `api_error` and is retried, which is the behaviour today. Story 10: `retention.test.ts` and `src/control/sessions.test.ts`; the app's `ContinueInTerminalTests.swift` already covers building the command from a `configDir` and does not change. Story 11: `doctor.test.ts` through the injected deps, with the Antigravity login check behind one of them so no test starts `agy`. The docs (`docs/configuration.md`, the JSON Schema and the `carrier init` wizard) change with story 1 and have no test of their own beyond the config's.

## Out of scope

Choosing a smarter default, such as the option with the most credits left. Only Antigravity has a verified, free way to read its quota (`agy -p "/usage"`); Claude and Codex have none, and the directory and the failure kind leave room for it. Chat sessions (epic #433), which can reuse the same directory in a later epic. A different failure kind for "no credits until renewed" against "rate limit with a reset time": both are `usage_limit` and the detail carries the reset. Moving an execution that is running now: the choice applies at the start of the epic, at Resume and at a failover. Remembering exhausted options across epics. The macOS app: its option pickers, its Resume sheet and its card for the new stop are worked on separately and can use the same socket requests. Editing or removing an option from the wizard; that is done in the file. A migration of the old config shape.

## Open questions

What the final `result` of Antigravity looks like on a real quota failure, and whether it exits 3 in a single `-p` run. The messages come from its changelog and the strings of its binary, and no account was exhausted to see them, so its fixture is inferred. The rule above is the best reading of the sources; a capture from the first real exhaustion confirms or corrects it.
