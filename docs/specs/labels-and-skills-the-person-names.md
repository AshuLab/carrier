# Labels and skills the person names

Status: spec

## Problem

Two things in Carrier are written into its code and cannot be changed by the person who runs it.

The labels Carrier writes on an epic's issue all live under `solve:epic:`, although two of the five are written by Solve and three by Carrier, so the name does not say who owns a label.
The names can now be set in `engine.json` (`labels`, merged earlier), but the defaults are still the old ones, so a person who sees `solve:epic:running` on an issue cannot tell that it was Carrier and not Solve who put it there.

The skill each stage runs is written into Carrier's prompts: `ship` for the first stage, `code-review` and then `code-post` for the review, `code-resolve` for a fix.
A person who builds or reviews another way has to edit Carrier's code, and the engine cannot tell before an epic starts that a skill does not exist for the account its role runs on, so a missing skill shows up as an agent that improvises, a run spent and a result that does not fit.

It hurts whoever runs Carrier on real epics, today Diego.
This is the third of four epics that come out of the review of the engine ([the findings](../research/engine-review-2026-11.md)); the first two, [the engine never leaves an epic stuck](engine-never-stuck.md) and [a review to trust and an intake in order](review-to-trust-and-intake.md), are merged, and the last, several reviewers and a lead, starts from `main` once this one is: [several reviewers and a lead](several-reviewers-and-a-lead.md).

## Solution

One epic in two parts that do not depend on each other: the new default names of the labels, and the skills each stage runs.

### The labels Carrier writes are named by Carrier

The `labels` block, its distinctness rule, the optional stage and reason groups, the `carrier doctor` check and the names in the snapshot are already built.
What is left is the defaults ([ADR 0043](../adr/orchestration/0043-labels-are-named-by-who-writes-them-and-every-one-is-configurable.md)): what Solve writes keeps `solve:epic` and `solve:epic:ready`, and what Carrier writes becomes `carrier:status:running`, `carrier:status:ready-for-test` and `carrier:status:needs-human`.
The stage and reason labels stay off until the person names them, and the documentation lists the names the ADR proposes (`carrier:stage:building`, `carrier:stage:reviewing`, `carrier:stage:fixing-review`, `carrier:reason:<kind>`) so a person can copy them.
Carrier only removes the labels it names now, as it always did, so an issue that carries an old name keeps it: nothing cleans the old names, no migration is written, and the CHANGELOG says so.
A person with a board or an automation keyed on `solve:epic:running` changes it or sets the old names in `labels`, and `carrier doctor` already tells them when a repo lacks a label Carrier reads.
The app hides the labels it knows are Carrier's and Solve's from an epic's header, and it knew only the `solve:` prefix, so it also hides `carrier:`.

### The skills each stage runs

The decision is [ADR 0045](../adr/orchestration/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md), amended by what [the research on where each harness looks](../research/skill-discovery-per-harness.md) found.
A `skills` block in `engine.json` names the skill of each stage: `ship`, `review` (with `review` and `publish`) and `fix`, by default Solve's `ship`, `code-review` with `code-post`, and `code-resolve`; `publish` may be `null` for a review skill that publishes by itself.
A repo's `skills` is merged by key onto the global one, a role's own `skills` (`agents.author.skills`, `agents.reviewer.skills`) wins over both, and the global wins over Solve's defaults, so the order is the role's, the repo's, the global and Solve's defaults.
A role names only the stages it runs: the author `ship` and `fix`, the reviewer `review`; another key is refused when the config loads, naming it.
The `lead` stage and the skills of extra reviewers belong to the epic that adds those roles, and this one leaves them out so no key is accepted that does nothing.
A skill is only a name, one that matches the rule in Decisions, and it is checked when the config loads; free text for a stage is refused because it would reach the prompt unchecked.

The prompts invoke the configured skill, spelled `/name`, or `$name` for Codex, as they do now, and Carrier keeps the rest of the prompt and the result contract for every skill.
The sentences that name Solve's own files (the worktree mode of `solve.md`, the design artifacts that must already be on the remote) are said only with the default ship skill; the contract sentences are said for every skill.
A review whose `publish` is `null` no longer tells the agent to publish with a second skill.
The skills of an epic are saved with its effective configuration when it starts, so a reload changes nothing for an epic that runs; an epic restarted from ship takes the skills of that moment, as it takes the rest of the configuration, and an epic saved before this version has none saved and reads the defaults.

Before an epic starts, resumes or changes the option of a role (a failover, or `carrier restart --author`), the engine asks whether each skill the role will invoke exists for the harness and the account of that role, and the answer is one of three: present, absent, or cannot tell.
The places each harness reads are in the research: folders and `claude plugin list --json` for Claude, folders for Codex, folders, manifests and `agy plugin list --json` for `agy`, a bare name matching `name` or `<plugin>:name`.
It answers absent only when it read every place the harness reads and none had the skill, and cannot tell where something it cannot read could hold it (managed settings, a plugin it could not list, a manifest with `include_only` or `exclude`).
An epic stops in needs-human with the new kind `skill_missing` only when the answer is absent for a skill the person named in their configuration, whatever the level they named it at; it names the skill, the role and where it looked, spends no agent run and is not retried.
For a skill that is Solve's default, absent or cannot tell never stops an epic: the person has not asked for it, and Carrier does not stop work that runs today.
Where the answer is cannot tell, the epic goes on.
`carrier doctor` runs the same question for the roles of each repo and shows the three answers, with a warning for a default that is absent and for any cannot tell.
A run that ends because the harness said the skill is unknown does not stop the epic in `skill_missing`: no harness reports it as an error for the prompts Carrier sends, so there is no signal to rely on.

### What was cut, and why

Cleaning the old label names on epics in flight lost, because a person asked not to leave a control that touches labels Carrier does not name, and an old name left on an issue does no harm to Carrier, which does not read it.
Moving Solve's two labels to `carrier:*` lost, because Solve writes `solve:epic:ready` at its hand-off and the epic would stop queueing without a sound.
A switch that turns on the stage and reason labels with their documented names lost, because it is one more key for what a list in the documentation gives.
A stop when the run reports an unknown skill lost, because no harness reports it as an error for a prose prompt.
Stopping when the check cannot tell lost, because a valid install in a place the check cannot read would be blocked with no way out.
Stopping for a default skill that is absent lost, because a role on Codex with no Solve skills runs today, and the person has not asked for them.
Running the harness's catalog command to learn the skills lost for Codex, because it is a debug command that may change; the folders are the documented layout.
Free text per stage, a list of skills per stage, the whole prompt in the config, a different skill per round and a skill per harness lost, for the reasons in ADR 0045.

## Scope

1. As the person, the labels Carrier writes on an epic's issue are by default `carrier:status:running`, `carrier:status:ready-for-test` and `carrier:status:needs-human`, and `solve:epic` and `solve:epic:ready` stay as Solve writes them.
2. As the person, an issue that carries an old default name keeps it when Carrier is updated, Carrier removes only the labels it names now, and the CHANGELOG says so.
3. As the person, the documentation lists the stage and reason labels' proposed names and says they are off until I name them.
4. As the person, the app does not show `carrier:` labels as chips in an epic's header, as it does not show `solve:` ones.
5. As the person, I name the skill of each stage in `skills`, globally and per repo, a repo inheriting by key what it does not name.
6. As the person, a role's own `skills` wins over the repo's and the repo's over the global, and the global over Solve's defaults, and a role that names a stage it does not run is refused naming the key.
7. As the person, a skill name that is empty, blank, has a leading `/` or `$`, a path, a newline, a semicolon or a non-ASCII letter, or is longer than 64 characters, is refused when the config loads, naming it.
8. As the person, the prompts invoke the skill I named, spelled `/name` or `$name` by harness, and a review whose `publish` is `null` does not tell the agent to publish with another skill.
9. As the person, the sentences of the ship prompt that hold only for Solve's skills are said only with the default ship skill, and the contract sentences are said for every skill.
10. As the person, the skills of a running epic do not change with a reload, an epic restarted from ship takes the skills of that moment, and an epic saved before this version runs with Solve's defaults.
11. As the person, an epic does not start, resume or change option when a skill I named is absent for the harness and account of the role that invokes it: it stops in needs-human with the kind `skill_missing` naming the skill, the role and where it looked, with no agent run spent and no retry.
12. As the person, when the check cannot tell, or when the skill is Solve's default, the epic goes on.
13. As the person, `carrier doctor` shows for each role of each repo whether each skill is present, absent or cannot tell, with a warning for a default that is absent and for any that cannot tell.
14. As the person, `skill_missing` has its own optional reason label and shows in `carrier status` and in the replies the app reads like the other kinds of stop.
15. As the person, the user documentation of both parts is written: `configuration.md`, `troubleshooting.md`, the CHANGELOG, the glossary and the docs and specs that name the old labels or say the engine does not read a skill.

## Decisions

The shape of the config, as an example of the keys and not of values:

```json
{
  "skills": {
    "ship": "ship",
    "review": { "review": "code-review", "publish": "code-post" },
    "fix": "code-resolve"
  },
  "repos": [{ "name": "owner/repo", "skills": { "review": { "review": "my-review", "publish": null } } }],
  "agents": { "reviewer": { "profile": "reviewer-bot", "provider": "claude", "skills": { "review": { "review": "my-review" } } } }
}
```

A skill name matches `/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/`, tried against the empty string, blanks, a leading `/` or `$`, a path, a newline, a semicolon, non-ASCII letters and 65 characters, which it all refuses, and against `ship`, `solve:ship` and 64 characters, which it takes.
The blocks are strict, so an unknown key is refused; `publish` is a name or `null`, and omitted it is inherited; the merge is by key, one level inside `review`.
The defaults are in the config's defaults, like the others, so they reach the JSON schema and the settings.

The data. The effective configuration of an epic, saved in its JSON column when it is reserved, gains the resolved skills; there is no migration, because the column is JSON and the kind of stop is text.
`skill_missing` joins `needsHumanKinds`, and its reason label key follows from the enum.
The task the engine gives an agent carries the skills its stage invokes, and an old task with none reads Solve's defaults.
The engine asks about skills through a port with a fake, as it does for the other things it cannot do alone: `has(harness, configDir, folder, name)` answering `present`, `absent` or `cannot-tell`, where `folder` is the repo folder the role will work in, or the repo's clone while its worktree does not exist.
`carrier doctor` uses the same port and adds one check per repo whose name the app does not match, so the app ignores it as it ignores any check it does not know.

The control socket and the CLI. No new request or capability: the replies gain nothing, since the kind is a string the app already reads.
The config field follows the checklist of `src/config/AGENTS.md`: the schema, the defaults, the resolution, the JSON schema, the contract test and its fixtures, and the documentation table; the Swift parity of `EngineConfig.swift` is out of this epic, and the Swift contract tests read unknown keys without failing.
The macOS side that does move: the chip filter of an epic's header, the fixtures under `macos/Tests/Fixtures` regenerated for the new defaults, and the test that reads the skill names out of the prompts (`AgentsReadinessTests`), which has to follow the names now coming from the defaults.

Documentation is part of the epic: `docs/configuration.md` (the labels' defaults and the new `skills` section), `docs/troubleshooting.md` (the heading about `solve:epic:needs-human`, the `skill_missing` stop), `docs/preparing-a-repo.md`, `docs/macos/settings-carrier.md` (it says the engine reads no skill), `README.md`, the CHANGELOG, the glossary (Status label, Stage skill) and the specs that name the old labels; ADR 0043 and ADR 0045 are amended to say what this spec says.

Testing seams, per story, preferring the seams the repo has:

- Stories 1 and 2: the engine in `src/orchestration/engine.test.ts`, whose literals of the old names are replaced, with an issue that carries an old name and a status change; the config in `src/config/load.test.ts`; the snapshot contract test and the fixtures.
- Story 4: no test of its own beyond the macOS unit tests, which still pass with the filter.
- Stories 5 to 7: the config in `src/config/load.test.ts` and the resolution as a pure function in its own test, the contract in `src/config/engine-config-contract.test.ts`, and the name rule against the inputs listed above.
- Stories 8 and 9: the prompts in `src/prompts/build-prompt.test.ts`, whose snapshots are updated and show only what changed, and the macOS readiness test.
- Story 10: `engine.test.ts`, with an epic saved without skills, a reload while an epic runs, and a restart.
- Stories 11 and 12: `engine.test.ts` with a fake of the skills port answering each of the three values, at start, at resume, at failover and at `restart --author`.
- The finder of the port: its own unit test over a temporary folder and a fake of the process that lists plugins, for each harness, including the places it cannot read.
- Story 13: `src/doctor/doctor.test.ts`.
- Story 14: `engine.test.ts` for the reason label and `src/control/replies.test.ts` for the reply.
- Story 15: no test: the documentation is checked in review.

## Out of scope

The last epic, several reviewers with a lead, which adds the `lead` stage, `skills.lead` and the skills of extra reviewers, and is [its own spec](several-reviewers-and-a-lead.md).

Cleaning the old label names, a switch that turns on the stage and reason labels, and moving Solve's labels.

Pausing one epic while the others run (`hold`), the label orders `carrier:restart*` and a `carrier enqueue` command.

The macOS app beyond the chip filter: the labels page, the text of Empty states and the wizard that name `solve:epic:ready` when the person renames it, the Settings page that edits skills, and the parity of `EngineConfig.swift`.

Stopping an epic because a run reported an unknown skill, until a real run of each harness shows a signal; what such a run would need is in [the research](../research/skill-discovery-per-harness.md).

The snapshot carrying the resolved skills, until the app shows them.

The text of Solve's own README, which still names the old three labels as the orchestrator's.

The review of how Carrier treats text written by third parties that the agents read, and of updating the engine while epics are running.
