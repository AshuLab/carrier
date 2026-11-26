# carrier init: accounts first, one closed block per role, repos last

Status: spec

## Problem

`carrier init` asks its questions in an order that does not follow how a person thinks about the setup, and it gives no way back.
It lists the repos first, although nothing that comes after depends on them, then the accounts, then the GitHub profiles of the orchestrator, the author and the reviewer, then the model, effort and persona of the author, then of the reviewer, then the lead reviewer, and only at the end the failover of all the roles at once.
A role is therefore spread over four places, so a person who is configuring the reviewer is asked about its account in one place and about its failover in another.
The engine runs up to three extra reviewers beside the Reviewer, and the wizard cannot configure any of them.
Esc and Ctrl+C both leave the whole wizard, and changing one answer from the recap asks every question again, about eighteen of them with all the defaults.

It also loses things a person did not ask to lose.
`init --yes` and "Start over" replace `providers.json` with the agent CLIs found on the machine and drop any account added by hand, such as a second Claude login with its own config folder, which the app and the engine share.
`init --config x.json` is accepted and ignored, and with `--yes` it overwrites the global `engine.json`.
Edit mode on a config that does not validate hides the reason and then overwrites the file with no confirmation.
Edit mode on a valid one promises that its answers are the starting points, but it writes `engine.json` from those answers alone, so `limits`, `labels`, `skills`, `behavior`, the per-repo overrides and any extra reviewers the file has are lost without a word.
Ctrl+C at "Start Carrier now?", after the config is saved and checked, prints "Cancelled" and exits 0, as if nothing was saved, and skips the closing line that says what to run next.

It hurts whoever sets Carrier up from a terminal, which today is Diego; nobody else was asked.
It is fixed when a person can go through `init` accepting the defaults with a few answers per role, can step back one question when they chose wrong, never loses an account or a file by running it, and can give every answer as a flag, with a mistake in a flag reported before the wizard spends seconds looking at the machine.
This was checked by running the wizard in a pseudo-terminal against a scratch Carrier folder and by reading `src/terminal/wizard`; the running side of the CLI (the panel, `status`, `watch`) was audited too and is a separate brief.

## Solution

### The order

First the AI accounts, found automatically with the option to add more; then the orchestrator's GitHub profile, as it is asked today; then one closed block for each role in turn, the Author, the Reviewer, each extra reviewer the person adds, and the Lead reviewer; and last the repos Carrier watches.
After the Reviewer's block it asks whether to add another reviewer, and it asks again after each one until the engine's limit of three extra reviewers.
The Lead reviewer comes after all the reviewers, and the repos come after every role, because nothing about a role needs them.
The repos are still listed with the person's own `gh` login: listing them with the orchestrator's profile would need a token from Agent Forge for a bot, which is a different change.
The answer the repo list collapses to shows `owner/name`, not the bare name, when the repos come from several owners.

### A role block

A role block is one reusable piece that takes the role and nothing else.
It asks the GitHub profile and the account, which are always asked, then shows the model and the effort it would use and asks only whether to change them, with Enter meaning no, and asks a single "customise the persona?" with Enter meaning no, instead of the several persona prompts asked today.
Inside the same block it asks for the role's failover, so every role is closed before the next one starts.
The failover question is asked only when the person has two or more accounts, since with one there is nowhere to move; with one account the block prints a line that says so instead of skipping the question in silence.
A role left on its defaults costs two choices and two Enters.
An extra reviewer that is given no failover uses the Reviewer's, as the engine does.

The defaults are Claude with `sonnet` at `high`; Codex with the model the Codex CLI already has in its own `config.toml`, or the first model it lists when there is none, at `high`; and Antigravity with `gemini-4-hydrogen-high`, or the first model `agy models` lists when that id is gone, with no `--effort` passed because the effort is already in the id.
No Codex model id is written in the code, because the list changes with the CLI's version and has no alias for a tier; the Antigravity id is the one constant, in one place, and needs updating by hand when it changes.

In edit mode every answer of the file is the starting point of its question.
An extra reviewer in the file is walked as a block with its values, and the "add another reviewer?" question starts on Yes while the file has one more, the same way "Add a lead reviewer?" starts on the file's answer today; a No ends the list there, so it drops that reviewer and the ones after it.
A role with a failover in the file is asked "keep the failover you have?" first, as today.

### Going back

Esc returns to the previous question, across the edge of a block into the last question of the previous role.
Ctrl+C leaves, and before Save nothing has been written.
The recap's "Change an answer" becomes a menu of where to jump to (accounts, orchestrator, each role, repos), and the jump starts from the answers already given, so changing one thing is one block and not the whole wizard.
Ctrl+C at "Start Carrier now?", when the config is already saved, counts as no and prints the line that says what to run.

### Flags

Every question has a flag, and the flags come from the same table of roles as the blocks do.
`--<role>` takes `<harness>:<model>`, and `--<role>-profile`, `--<role>-provider`, `--<role>-effort`, `--<role>-persona-name`, `--<role>-persona-prompt` and `--<role>-failover <account>[:<model>]`, repeatable and in order, complete it, with `<role>` one of `author`, `reviewer`, `reviewer-2`, `reviewer-3`, `reviewer-4` and `lead-reviewer`.
The help shows the pattern once and not forty lines.
The flags are checked before the wizard probes the machine and GitHub, and an error names the flag; today a flag mistake is reported after four to ten seconds and the message for a missing repo does not say which flag.
`--yes` prints what it chose, so a person who skipped every question still sees which profiles, accounts and models were picked.

### What `init` writes

It writes without taking anything away.
The agent CLIs found are added to the accounts already in `providers.json` and never replace them, "Start over" resets only the answers of `engine.json`, and no path of `init` removes an account; removing one is done from the app or with `carrier config`.
Editing an existing config keeps everything the wizard does not ask: `engine.json` is written as the file already is, with only the keys the wizard asks replaced, so `limits`, `labels`, `skills`, `behavior`, the poll interval, the per-repo overrides and the extra reviewers already in the file survive an edit.
"Start over" and a new file are written whole from the answers, as today.
`--config` is refused on `init` with a line that says `init` writes with `--out`.
An existing config that does not validate is reported with its first error, and the wizard asks what to do before touching the file.
The checks of the doctor stop printing their JSON log lines on the screen during `init`, and a non-interactive run that finds the file already there says how to go on (`--yes` or `--out`).
The words go back to the glossary: the wizard says profile and not identity, and failover and not fallback.
`docs/cli.md`, the help of `--yes`, which still says one claude option runs both roles, and the first-run steps of the `README` are corrected to what the wizard does.

### What was weighed and cut

Keeping the repos first, because nothing depends on them and the orchestrator's profile is the better thing to know before choosing them.
Listing the repos with the orchestrator's profile, which is the stronger reason to move them but needs a token for a bot from Agent Forge and was left for later.
Offering failover with one account, including another model of the same account, because a usage limit is usually the account's and another model of it does not help.
One compact repeatable `--extra-reviewer "agent=codex:gpt-5,effort=high"` flag, which is short but breaks the style of the flags the wizard already has.
Making `--config` an alias of `--out`, which is friendlier but leaves two names for one thing, and `providers.json` goes to the Carrier folder in either case.
Asking every question in full, because with up to six roles the flow would be thirty answers to accept the defaults.
Writing a Codex model id in the code as the equivalent of `sonnet`, which would be out of date with the next version of the CLI.
No ADR was written: each of these is easy to change later, so none meets the three-part test.
The glossary changed in two places, the Role entry, which still said there were only three roles, and a new Extra reviewer entry.

## Scope

1. `init` finds the agent CLIs on the machine, adds each as an account, and offers to add more, before any other question.
2. The accounts already in `providers.json` are kept by every path of `init` (`--yes`, "Start over", edit, a new file); what is found is added to them.
3. The orchestrator's GitHub profile is asked after the accounts, as it is today.
4. The Author is configured in one block: profile, account, the model and effort with a "change?" question, a "customise the persona?" question, and its failover.
5. The Reviewer is configured in a block of the same kind, and then "add another reviewer?" is asked until there are three extra reviewers.
6. Each extra reviewer is a block of the same kind, named `reviewer-2` to `reviewer-4`; one given no failover uses the Reviewer's.
7. The Lead reviewer is asked after the last reviewer, in a block of the same kind.
8. With fewer than two accounts the block does not ask the failover and prints one line that says why.
9. The repos are asked last, listed with the person's `gh` login, and a repo of several owners shows as `owner/name` in the collapsed answer.
10. The defaults are `sonnet` at `high` for Claude, the Codex CLI's own configured model (else its first listed) at `high` for Codex, and `gemini-4-hydrogen-high` (else the first listed) with no effort flag for Antigravity.
11. Esc goes back one question, across blocks, with the earlier answer as the starting point; Ctrl+C leaves; before Save nothing is written.
12. "Change an answer" in the recap is a menu of blocks to jump to, and the jump keeps every other answer.
13. Ctrl+C at "Start Carrier now?" after the save counts as no and prints what to run.
14. In edit mode the file's answers, its extra reviewers and its failovers are the starting points, and a No at "add another reviewer?" drops that reviewer and the ones after it.
15. Every question has a flag from the role table: `--<role>`, `--<role>-profile`, `--<role>-provider`, `--<role>-effort`, `--<role>-persona-name`, `--<role>-persona-prompt` and the repeatable `--<role>-failover`.
16. A flag that cannot work is refused before the wizard probes the machine, and the message names the flag: a value that does not parse, an extra reviewer's flag with no flag for the one before it, a failover account that does not exist, a repo that is not `owner/name`, and `--yes` with no `--repo`.
17. `--yes` prints which profiles, accounts, models and efforts it chose.
18. `init --config` is refused, naming `--out`.
19. An existing config that does not validate is reported with its first error, and the wizard asks before replacing it.
20. The doctor's log lines do not appear on the screen during `init`, and a non-interactive run on an existing file says to use `--yes` or `--out`.
21. The help shows the role flags as one pattern, and `docs/cli.md`, the help of `--yes`, the `README` first-run steps and the wizard's wording follow the glossary and the real flow.
22. Editing an existing config writes `engine.json` as the file already is, with only the keys the wizard asks replaced, so every other setting of the file survives.

## Decisions

**Back and the jump are one mechanism, an answer journal at the `Ui` contract.**
Every question has a stable id (`author.account`, `reviewer-2.effort`, `repos`), and the journal keeps the answer given to each id.
The flow stays linear code.
Esc drops the answer of the last question asked and runs the flow again from the top, and every question that has an answer in the journal is answered from it without showing anything, so the person lands on the dropped question with its old answer as the starting point.
The recap's jump drops the answers of the ids of one block and replays the same way, so the other blocks keep theirs.
An answer whose option no longer exists (a profile the changed account no longer offers) is asked again.
Results of work that costs something, the GitHub and CLI calls under `busy` and the result of `agent-forge add` for a new bot, are journalled too and never run twice.
A step that writes nothing is replayed freely, and nothing is written before Save, so a replay has no side effect.
The unit of a block is its set of ids, so the same piece serves all six roles.

**Esc and Ctrl+C are told apart by the key that was pressed.**
Clack gives both the same cancel action, so the wrapper in `src/terminal/prompts/clack.ts` keeps a `keypress` listener on standard input that remembers the last key, and decides after a prompt resolves with the cancel symbol: Esc becomes a `Back`, Ctrl+C stays `Cancelled`.
It was probed in a pseudo-terminal against the installed `@clack/prompts` for the seven kinds the wrapper uses (`select`, `text`, `confirm`, `multiselect`, `groupMultiselect`, `autocomplete` and `autocompleteMultiselect`), and the last key read `escape` or `ctrl+c` correctly in all of them.

```ts
/** Esc: the person wants the previous question. Ctrl+C is `Cancelled`. */
export class Back extends Error {}
```

**The role table is the single source of the blocks and of the flags.**
The wizard's block, the options of `parseArgs` in `src/terminal/cli/args.ts`, the `InitFlags` type and the help pattern are all built from it, so a seventh role would be one line.

```ts
export const roleSlots = ['author', 'reviewer', 'reviewer-2', 'reviewer-3', 'reviewer-4', 'lead-reviewer'] as const;
```

`reviewer-2` to `reviewer-4` are the engine's names for the extra reviewers ([ADR 0048](../adr/review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md)); the lead keeps the `lead-reviewer` of the flags `init` already has, not the engine's `lead`.
`--reviewer-2` and the others already exist in the option table for `restart`, where they name an option of the config; in `init` they take `<harness>:<model>`, as `--author` and `--reviewer` already mean one thing in `init` and another in `restart`.

**Extra reviewers are positional.**
The config keeps them in an ordered list, so a flag for `reviewer-3` with none for `reviewer-2` has no place to go and is refused naming the missing flag.
An extra reviewer exists in the config when any flag names it, or when the person adds it in the wizard; the ones the flags name are not asked again, and "add another reviewer?" is asked once after the last of them when there is room.
Under `--yes`, with no flag naming an extra reviewer there is none.

**`--<role>-failover` is `<account>[:<model>]`, split at the first colon.**
Account names are a lowercase word of letters, digits and hyphens, so they never hold a colon, and a model may (`llama3:8b`), so everything after the first colon is the model.
It is refused when the account part is empty or does not match that pattern, when the account is not among the ones found or in the file, and when a colon is given with an empty model; `-failover` repeated gives the steps in the order given, up to the two steps the wizard offers, and a step equal to the role's own account and model is refused as the wizard already refuses it.
A step with no model uses the account's, then the harness's ([ADR 0021](../adr/agents/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)).

**Flags are validated in one function that runs before `detect`.**
It takes the parsed flags and returns the first error naming its flag, so the wizard does not call the machine or GitHub for a command that cannot succeed.
Anything that needs the machine (that an account exists) is checked as soon as the accounts are known, still before the first question.

**`init` merges accounts and never replaces them.**
The accounts of the file are the base, and each harness found that has no account of its own is added under the harness's name; "Start over" and `--yes` differ from edit only in the engine's answers.

**An edit replaces only the keys the wizard owns.**
The owned keys are `repos` (a repo that stays in the answers keeps its existing entry, with its per-repo overrides, a repo that leaves is dropped and a new one is `{ "name": "owner/name" }`), `profiles` (the profiles the answers use are set over the file's, the others stay), `orchestratorProfile`, `failover.roles.author`, `failover.roles.reviewer` and `failover.roles.leadReviewer` (replaced by the answers, with `failover.triggers` kept when the file has them), and `agents.author`, `agents.reviewer` and `agents.leadReviewer` (each replaced in `profile`, `provider`, `model`, `effort` and `persona` only, so a role keeps the other keys it has, its `skills` for one, and `leadReviewer` is removed when the person answers no to it).
`agents.extraReviewers` is not owned until the extra reviewers are asked, and from then on it is.
"Start over", a new file and `--out` to a file that is not the one being edited are written whole from the answers.

**The edit mode follows the repo's own convention for an optional role.**
Extra reviewers use the shape the lead reviewer already has: a confirm that starts on the file's answer, and a No removes it.

Testing seams, broadest first, per story:

- Stories 1, 3 to 10 and 14: `runInit` in `wizard.test.ts` with `quietUi` and `fakeDeps`, asserting the sequence of questions asked and the config and `providers.json` written.
  The defaults of story 10 are also unit-tested where the question is built (`agent.test.ts`, `options.test.ts`) with fakes for the Codex CLI's `config.toml` and `agy models`.
- Story 2: `runInit` over `fakeDeps` files, with a `providers.json` holding an account added by hand, through `--yes`, "Start over", edit and a new file.
- Story 22: `runInit` in edit mode over a fake `engine.json` that holds `limits`, `labels`, `skills`, a per-repo override, a role's `skills` and an extra reviewer, asserting what is written still holds each, and the same file under "Start over" holding none.
- Stories 11 and 12: a new unit test of the journal wrapping a scripted `Ui`, with a `Back` thrown at chosen questions (the first of a block, the last, across a replayed `busy` and a replayed bot added), and `runInit` tests that throw a `Back` and a jump from the recap.
  The step from the key pressed to `Back` or `Cancelled` is a small pure function with its own unit test; the key listener on a real terminal has no automated test, because Node has no pseudo-terminal without a new dependency, and is checked by hand in one before the epic closes, as the probe above was.
- Story 13: `runInit` with a scripted Ui that throws `Cancelled` at "Start Carrier now?", asserting the closing line and the result.
- Stories 15, 16 and 21 (the parse): `args.test.ts`, the pure `parseCli`, for the options built from the table, the repeatable failover and the usage pattern; and a new test of the flag-validation function, the broadest pure seam for story 16, with the wrong-typed and empty cases (`--x-failover ""`, `a:`, `:m`, `claude:llama3:8b`, `--reviewer-3` alone, an unknown account, `--yes` with no repo).
  That nothing is probed when a flag is wrong is a `runInit` test whose fake deps count their calls.
- Stories 17 and 19: `runInit` with the fake Ui, asserting the summary printed under `--yes` and the first error with its question for an invalid config.
- Story 18 and the real flow: `main.test.ts`, which runs the real process, for `init --config x` exiting 2 with the message, and for `init --yes` leaving no JSON log line on standard error.
- Story 20: the second half through `runInit` and the first through the process in `main.test.ts`, since the doctor's log lines are a property of the process's logger and not of the wizard.
- Story 9: `repos.test.ts`, on the label the question builds.
- Story 21 (the docs): no test, `docs/cli.md` and the `README` are reviewed against the wizard's real flow; the help is covered by `args.test.ts`.

## Out of scope

The running side of the CLI: the panel, `status`, `watch`, the commands' flags per command, help per command, `carrier logs` and `--json`, which are the next brief and start from the audit of the running Carrier.
Listing the repos with the orchestrator's profile.
A setup flow in the macOS app, which today only says the engine is not configured and does not name `carrier init`.
Spanish copy of the wizard, which stays English only.
Removing accounts from `init`.
