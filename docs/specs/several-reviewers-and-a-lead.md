# Several reviewers and a lead

Status: spec

## Problem

The review of an epic is one agent.
Each round the engine launches a single `review` execution from the `reviewer` role and takes its one result as the verdict, so a person who wants the opinion of another provider, another model or a reviewer with a different skill has no way to get it.
The config already accepts a `leadReviewer` role, the setup asks for it, the doctor checks it and the Settings page of the app has a switch for it, but the engine never reads it: a person who turns it on gets nothing, and the app says so.

It hurts whoever runs Carrier on real epics, today Diego, and a review is what decides whether an epic reaches the person's hands as something to trust.
This is the last of four epics that come out of the review of the engine ([the findings](../research/engine-review-2026-11.md)); the first three, [the engine never leaves an epic stuck](engine-never-stuck.md), [a review to trust and an intake in order](review-to-trust-and-intake.md) and [labels and skills the person names](labels-and-skills-the-person-names.md), are merged, and this one is built on what they left: the attempt rule, the head rule, the resume from a stage, the `skills` block and the check of skills.
It is the epic that touches the most of the engine, because the engine is built on one review execution per epic: the retry streak, the recovery, the reviewer's checkout, the blockers the author fixes, the snapshot the app reads and the stop of a profile all assume it.

## Solution

One epic in two parts, in this order: several reviewers in a round, then the lead reviewer after them.
The decision is [ADR 0048](../adr/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md), amended by what this spec settles.

### Several reviewers

An epic has one mandatory reviewer, `agents.reviewer`, and up to three more in `agents.extraReviewers`, each with its own profile, provider, model, effort, persona and, if it wants, its own review skill and its own failover steps.
A repo overrides the list as it overrides the other roles, and a list replaces the whole list, so a repo can also set it to empty.
In the engine, in the options of `carrier restart` and in the stored executions a reviewer is named by its slot: `reviewer`, `reviewer-2`, `reviewer-3`, `reviewer-4`, and `lead` for the lead.

A review round runs every reviewer on the same head, in parallel, each in its own detached checkout of that head, and ends when every reviewer has settled.
A reviewer settles with a verdict (it completed, or it asked for changes), with an answer that it cannot conclude, with a technical failure it could not recover from (its retries and failover steps are out), or, for an extra reviewer, with a skill the person named that does not exist for its harness and account.
The last three are no verdict, and they do not stop the round: one verdict is enough for the round to count, and with none the epic stops in needs-human with the kind `reviewers_failed`, naming each reviewer and why.
The epic records and shows how many reviewers gave a verdict out of how many were configured, and for each one that gave none, why, in `carrier status` and `carrier watch`, in the reply of the epic and as an event of the epic; no new status and no label of GitHub says it, because an epic that reached ready for test with fewer verdicts than reviewers is ready for test all the same.
A reviewer that is slow holds the round for as long as an execution may last (`limits.maxExecutionHours`, 4 by default, and `limits.idleMinutes`, off until set, which the documentation recommends for this); the epic has no limit of its own for a round.

An epic with one reviewer configured behaves exactly as it does today, with the same kinds of stop: `reviewers_failed` exists only for a round with several, so no epic that runs today changes its stops.
The mandatory reviewer does stop the epic with `skill_missing` when a skill the person named is absent for it, as it does now, and it is checked before any reviewer of the round is launched, so no run is spent.

The verdicts combine in one way.
If any reviewer asks for changes the author fixes once, with the latest open blockers of every reviewer, each blocker keeping its reviewer's id, and the next round runs every reviewer on the new head.
A blocker is shown to the author with its reviewer as a prefix (`reviewer-2:B1`), so the ids of two reviewers never collide, and each reviewer is given in the next round only its own blockers, with its own ids, and is the only one that can resolve them.
The prefix is added when the epic has several reviewers, and it is only how a blocker is shown and told to the author: a blocker's `id` is optional in a result, and one that has none is matched by its title, as it is today; with one reviewer the ids are the reviewer's own.
When two reviewers' blockers contradict each other the author decides, and says in its summary which blocker it did not follow and why; the reviewers read the summaries of the round before in their next one, and the epic has no stop for a contradiction.
If every verdict is a completed review the observations of all go to the author in the one pass the epic has, each with its reviewer, and the head that does not change after it is the head the reviewers agreed on.
A round counts once toward `maxReviews`, however many reviewers it has.
A reviewer whose blockers are still open and who gives no verdict in a later round is not agreement: if every verdict that came is a completed review, the round does not close, and the epic stops with `reviewers_failed` naming that reviewer; if some other reviewer asks for changes, the fix goes ahead, because it also answers the blockers still open.
A head that moves during a round, whichever reviewer reports it, repeats the whole round on the new head, not counted, under the rule of [ADR 0047](../adr/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md): the first result that finds the head moved stops the round's other running executions, because their verdicts would be set aside, and launches the round again.
The two repeats in a row before the epic stops with `pr_invalid` count rounds and not executions, so four reviewers that find the same moved head are one repeat, and the count goes back to zero only when a round decides on its own head.

Each extra reviewer keeps its own option, failover and retry state, as the author and the mandatory reviewer do.
A failover step list is its own `failover` when it declares one and `failover.roles.reviewer` when it does not; the retries are counted per reviewer, so one reviewer's failures never break another's streak, and an extra reviewer that runs out of retries or of failover steps is a reviewer with no verdict.
When a round ends with no verdict and every failure was `usage_limit` (reviewers that share a provider account run out together), the epic stops with `usage_limit` and not with `reviewers_failed`, so the wake-up on quota applies, and it resumes at the time the last of the exhausted windows comes back.
An authentication signal of the profile of any role, an extra reviewer or the lead included, counts as the rule of [ADR 0050](../adr/0050-one-authentication-signal-is-a-technical-failure-of-its-epic-and-a-profile-stops-when-it-repeats.md) says (the first is a technical failure of that execution, the second stops the profile), and stopping a profile stops the epics that use it in any role.
`carrier restart` takes an option for each reviewer with `--reviewer-2` to `--reviewer-4` where it takes `--author` and `--reviewer`.

Every reviewer publishes its own comments on the pull request with its review skill, by default `code-review` and `code-post`, and a profile may be shared between roles; what tells two reviewers apart is the prefix of the blocker's id, not the account that wrote the comment.
A reviewer whose profile is the author's has the prompt of a shared identity, as the reviewer has today; it is a property of each task, not of the epic.
With a shared account a reviewer's re-review could take the open threads of another reviewer for its own, so its prompt tells it to judge only the blockers it is given by id and to leave the threads it did not open, and the documentation recommends a profile for each reviewer.

### The lead reviewer

The optional `leadReviewer` runs once, after the reviewers agree, on the head they agreed on, with the summaries of their results, in its own checkout.
Its skill is `skills.lead`, with the shape of `skills.review` (`review` and `publish`), resolved like the others (the lead's own `skills.lead`, then the repo's, then the global); when none of them names it, it takes the values of the repo's or the global `skills.review`, and then Solve's defaults, and a value taken from a `skills.review` the person named is a named skill.
The lead's prompt tells it that it is the final reviewer and that, when it finds no blocker, it gives the pull request its formal approval with its identity.
The engine does not require the approval: the lead's result carries an optional `approval` (whether it submitted one, and its url), which the engine records and shows, and a lead that cannot approve does not block the flow.

If the lead completes, the epic is ready for test, and it keeps the head the reviewers agreed on and the head the lead approved, and shows both when they differ.
If the lead asks for changes the exchange is between the author and the lead alone: the author fixes with the lead's blockers and only the lead reviews again, on the head after the fix, up to `limits.maxLeadRounds` (3 by default), and then the epic stops in needs-human with the kind `lead_limit`.
The lead's exchange does not count toward `maxReviews`, the other reviewers do not look at the commits it makes, and the lead's observations are kept with its result and shown, but do not go to the author and are not counted as left unanswered.
A lead that answers that it cannot conclude stops the epic with `agent_needs_human`, and a lead that runs out of retries or of failover steps stops it with `retries_exhausted` or `usage_limit`, all naming the lead, and the wake-up on quota reads the lead's role like any other.
A named skill of the lead that does not exist stops the epic with `skill_missing`, as the mandatory reviewer's does.
A head that moves while the lead reviews repeats the lead's review on the new head, not counted, with the same two repeats in a row as a round.
A resume at a stage starts the lead's exchange over: the fix goes back to the reviewers' round, and the lead gets its `maxLeadRounds` again once the reviewers agree.

The `lead` stage has its own optional stage label (`labels.stages.lead`, which the documentation proposes as `carrier:stage:lead-reviewing`), and `reviewers_failed` and `lead_limit` have their optional reason labels like the other kinds.

### What the app reads

The app is not changed in this epic beyond what keeps it reading what it read, and the snapshot is where that is decided.
The `Stage` of the snapshot is a strict enum of `ship`, `review` and `fix` in the app, so the stage `lead` is reported there as `review` with an optional `lead` flag, until the app knows it; the replies that carry the stage as a string report `lead`.
The snapshot lists one session per running execution, and with reviewers in parallel an epic has several: each carries the agent that execution ran with and its reviewer slot, and the app already draws a row for each session of an epic.
The epic carries, as optional fields, how many reviewers gave a verdict out of how many were configured, the head they agreed on, the head the lead approved and whether the lead's result says it submitted an approval, and the agents of the extra reviewers and the lead.
The replies of an epic's rounds keep the mandatory reviewer in the place the app reads and add the other reviews of the round as an optional list.

### What was cut, and why

Reviewers one after another lost, because the person chose parallel and the wait for several reviews adds up; it would have kept the one-execution rule and the simpler recovery.
A `reviewers` list in place of `reviewer` lost, because it breaks every config and the app, which read `agents.reviewer`.
Repeating the whole round, reviewers and lead, after the lead asks for changes lost, because the lead is the final reviewer and an exchange with the author alone is cheaper.
Stopping the epic when a reviewer fails lost, because an extra reviewer that is down would block reviews that worked; for the same reason a named skill that an extra reviewer lacks makes that reviewer a reviewer with no verdict and does not stop the epic.
`reviewers_failed` for an epic with one reviewer lost, because it would change the stops of every epic that runs today.
Requiring the formal approval on GitHub lost, because GitHub does not let a pull request's author approve it and an app may lack the permission.
A column per role for the options (`authorOption`, `reviewerOption` and one for each more) lost, because the options of the extra reviewers and the lead live in the epic's saved configuration, which an epic already carries and a reload does not touch.
Reading the approval from GitHub lost, because the engine does not know the login behind a profile, and the review decision of the pull request is empty in a repo that requires no review, which is the common one; the lead says in its result whether it approved.
Waiting for every reviewer of a round after the head moved lost, because their verdicts would be set aside and each run costs a model's time and credits.
A limit of its own on how long a round waits for a slow reviewer lost, because the limits of an execution already bound it, and one more knob would be for a case that `limits.idleMinutes` covers.
A stop when two reviewers contradict each other lost, because the author is the one who answers the blockers, and what it did not follow is in its summary for the reviewers to read.
A timer to wake an epic that stopped in `reviewers_failed` lost, because the stop has several causes and only a quota one comes back by itself, which is why a round whose every failure was a quota one stops in `usage_limit`.

## Scope

1. As the person, I configure up to three extra reviewers with `agents.extraReviewers`, each with its own profile, provider, model, effort, persona, review skill and failover steps, a repo's list replaces the whole list, and a fourth extra reviewer is refused when the config loads.
2. As the person, I name the lead's skill in `skills.lead` globally, per repo and in the lead's own role, and an extra reviewer's review skill in its own entry, with the same name rule and precedence as the other skills, and a role that names a stage it does not run is refused.
3. As the person, I set `limits.maxLeadRounds`, and I name the lead's stage label and the reasons of the two new kinds of stop like the other labels.
4. As the person, a review round runs every reviewer in parallel on the same head, each in its own checkout, and ends when all of them have settled.
5. As the person, a reviewer that fails, cannot conclude or lacks a skill I named does not stop the round, one verdict is enough, and with none the epic stops in needs-human with `reviewers_failed` naming each reviewer and why, or with `usage_limit`, and so woken by the quota, when every failure was a quota one; an epic with one reviewer stops as it does today.
6. As the person, the epic shows how many reviewers gave a verdict out of how many I configured, and why each of the others gave none, in `carrier status`, `carrier watch`, the reply of the epic and an event, and an epic that reached ready for test with fewer verdicts is still ready for test.
7. As the person, when any reviewer asks for changes the author fixes once with the blockers of all of them, each blocker keeping its reviewer's id and resolved only by that reviewer, and the next round runs every reviewer on the new head; when two of them contradict each other the author decides and says in its summary what it did not follow.
8. As the person, the observations of all reviewers go to the author in the one pass the epic has, and a round counts once toward `maxReviews`.
9. As the person, a reviewer with blockers still open that gives no verdict in a later round does not let the round close as agreed: the epic stops in `reviewers_failed` naming it, unless another reviewer asks for changes.
10. As the person, a head that moves during a round stops the round's other running reviewers and repeats the round on the new head without counting it, and after two repeats in a row, counted by round and not by reviewer, the epic stops in `pr_invalid`.
11. As the person, each extra reviewer and the lead have their own option, failover and retry state, an extra reviewer that runs out of retries is a reviewer with no verdict, and the lead running out stops the epic naming it.
12. As the person, an authentication failure of the profile of any role stops the epics that use it, as ADR 0050 says, an extra reviewer or the lead included.
13. As the person, `carrier restart` takes an option for `--reviewer-2` to `--reviewer-4` and `--lead` as it does for `--author` and `--reviewer`, and a restart or a resume keeps the extra reviewers and the lead of the epic.
14. As the person, with a lead reviewer configured it runs once after the reviewers agree, and when it completes the epic is ready for test, with the approval its result says it submitted shown, and not required to go on.
15. As the person, when the lead asks for changes the author fixes and only the lead reviews again, up to `limits.maxLeadRounds`, and then the epic stops in needs-human with `lead_limit`.
16. As the person, a lead that cannot conclude, runs out of retries or lacks a skill I named stops the epic with `agent_needs_human`, `retries_exhausted` or `skill_missing`, naming the lead.
17. As the person, the epic keeps and shows the head the reviewers agreed on and the head the lead approved when they differ, and the lead's stage has its own optional stage label.
18. As the person, a named skill of an extra reviewer or the lead that does not exist is shown by `carrier doctor` as it is for the author and the reviewer, and the doctor checks the profile and the provider of each extra reviewer.
19. As the person with an app that does not know the stage `lead` or several sessions of one epic, the snapshot reports the lead as `review` with an optional `lead` flag and lists a session for each running execution, so the app reads it and draws each one.
20. As the person, a resume at a stage after the lead stopped the epic starts the lead's exchange over, with its rounds granted again.
21. As the person, the user documentation of the epic is written: `configuration.md`, `cli.md`, `troubleshooting.md`, the CHANGELOG, the glossary, and the specs that say an epic never has two active executions or that the lead is not built.

## Decisions

The engine's rules, in one table, for what changes in the stage loop; the rest of the stage loop is as in [the orchestrator spec](autonomous-orchestrator.md).

| After | Condition | Next |
| --- | --- | --- |
| `ship` | pull request valid | review round 1, every reviewer in parallel |
| review round | one reviewer configured | as today, with the same kinds of stop |
| review round | several configured, a reviewer not settled | wait for it |
| round settled | no verdict at all | needs-human `reviewers_failed`, or `usage_limit` when every failure was a quota one |
| a result of the round | the head is not the one the round started on | the other running reviewers stop and the round again on the new head, not counted, at most twice in a row counted by round, then needs-human `pr_invalid` |
| round settled | any verdict asks for changes, round below `maxReviews` | `fix` with the latest open blockers of every reviewer, then the next round |
| round settled | any verdict asks for changes, round at `maxReviews` | needs-human `review_limit` |
| round settled | every verdict completed, a reviewer with open blockers gave none | needs-human `reviewers_failed` naming it |
| round settled | every verdict completed, observations, pass not taken, round below `maxReviews` | `fix`, the observations pass of all |
| round or pass | every verdict completed, head unchanged after the pass | agreed head: the lead if configured, else ready for test |
| pass | head changed | the next review round |
| lead | completed | ready for test, the approved head recorded |
| lead | asks for changes, lead round below `maxLeadRounds` | `fix` with the lead's blockers, then only the lead again |
| lead | asks for changes, at `maxLeadRounds` | needs-human `lead_limit` |
| lead | cannot conclude | needs-human `agent_needs_human`, naming the lead |
| lead | retries or failover out | needs-human `retries_exhausted` or `usage_limit`, naming the lead |
| lead | a skill the person named is absent | needs-human `skill_missing` |
| lead | the head moved | the lead's review again on the new head, not counted, with the repeats of a round |

The shape of the config, as an example of the keys and not of values:

```json
{
  "skills": {
    "review": { "review": "code-review", "publish": "code-post" },
    "lead": { "review": "code-review", "publish": null }
  },
  "labels": {
    "stages": { "review": "carrier:stage:reviewing", "lead": "carrier:stage:lead-reviewing" },
    "reasons": { "reviewers_failed": "carrier:reason:reviewers-failed", "lead_limit": "carrier:reason:lead-limit" }
  },
  "agents": {
    "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "<model>" },
    "extraReviewers": [
      { "profile": "reviewer-bot", "provider": "claude", "model": "<model>", "skills": { "review": { "review": "my-review" } }, "failover": [{ "provider": "claude", "model": "<model>" }] }
    ],
    "leadReviewer": { "profile": "reviewer-bot", "provider": "claude", "model": "<model>", "skills": { "lead": { "review": "my-lead-review" } } }
  },
  "limits": { "maxLeadRounds": 3 }
}
```

The blocks are strict, so an unknown key is refused naming it.
`agents.extraReviewers` takes zero to three entries with the fields of any agent plus `skills` (only `review`) and `failover` (the steps of `failover.roles`); a fourth is refused naming the list.
A repo's `agents.extraReviewers` entry has to carry the profile, provider and model, as a repo's `leadReviewer` does when no global one exists, because the list replaces and does not merge.
The lead's role takes `skills` with only `lead`.
`skills.lead` has the shape of `skills.review`, a name or `null` for `publish`, with the name rule of [ADR 0045](../adr/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md), and it is resolved as that ADR says (merged by key, role over repo over global) with one more step: what no level names for the lead is taken from the repo's or the global `skills.review`, never from another role's own skills, and then from Solve's defaults.
An extra reviewer's `review` skill resolves the same way, from its own entry, the repo's `skills.review`, the global and Solve's defaults.
`limits.maxLeadRounds` is a positive whole number, 3 by default, and reaches the JSON schema and the settings like the other defaults.

The data. The kinds of stop `reviewers_failed` and `lead_limit` join `needsHumanKinds`, with their reason labels, and `lead` joins the stages of an epic and of an execution and the stage label names; `resumeStage` gains `lead`, which only the wake-up sets so that a quota stop of the lead resumes at the lead's stage, and `--from` stays `ship`, `review` or `fix`.
A migration, with `pnpm db:generate`, adds `executions.reviewer` (the slot, null for `ship` and `fix` and on rows from before, and a review row with none reads as `reviewer`), and `epics.leadRound` (null until the lead runs, then the number of the lead's review in this attempt) and `epics.approvedSha` (the head the lead approved, null without a lead); `reviewedSha` keeps its name and means the head the reviewers agreed on, which is what it means today with one reviewer.
How many reviewers gave a verdict out of how many were configured is not stored: it is read from the executions of the epic's latest round and the configuration the epic saved.
The lead's result gains an optional `approval` (`submitted`, and `url` when it has one), which the prompt asks for and the engine records in an event of the epic when the lead completes; whether the approval is shown is read from that event, and nothing is read from GitHub for it.
A restart and a resume clear `leadRound` and `approvedSha` where they clear the rounds, and the places that rebuild an epic row field by field are updated with them.
The options of the extra reviewers and the lead live in the epic's saved configuration, where `agents.<role>.option` already lives for the author and the reviewer, and the columns `authorOption` and `reviewerOption` stay as they are; the saved configuration gains the extra reviewers, the lead's state and the resolved skills of each, so a reload changes nothing for an epic that runs, and an epic saved before this version has none and is read with one reviewer.
The attempt rule is as ADR 0047 and epic 1 left it, and the retry streak, the recovery and the wake-up read executions within the attempt and, for the reviewers, within the attempt and the slot.
A reviewer that settled without an execution (a named skill absent for an extra reviewer) is stored so that a restart reaches the same decision, naming the slot and the skill, and without spending a run.

A round is its round number and the head its executions were given (`executions.round` and `executions.headSha`, which exist): it is settled when every configured slot has, on that head, a result that was not set aside, a failure it could not recover from, or the record of an absent skill, and every slot that has none and no live execution is launched, so a restart finds what to launch from the stored rows alone.
The decision of a round is a function of those stored results, and it is made inside the transaction that imports the last result, so two reviewers that end together never decide it twice.
Several reads of the engine are today of the epic and become of the slot, and each is a place to change: the retry streak and its timers, the failover's read of the options that ran out and the quota probe, the last execution the wake-up and the recovery start from, the counters of recoveries, automatic resumes and the last error that every ended execution resets (a success of one reviewer must not reset another's), the due time of a retry, the result of a reviewer that answers `needs_human`, which stops the epic at once today, and the execution the snapshot names for an epic, which is the newest of the author or of the mandatory reviewer and never depends on which reviewer ended last.
An execution carries its slot in the task it is given, so the prompt can name it and a test can tell two reviewers of one epic apart.
The checkout of each slot is its own detached checkout at the same commit, never inside another checkout, and the cleanup of an epic removes all of them and the one the single reviewer has today.
The engine's rule that an epic never has two active executions becomes: never two of the same slot, and never the author and a reviewer at once.
An epic still takes one slot of `limits.maxConcurrentEpics`, whatever its reviewers, and a limit on the agents running at once is out of scope.
`failover.roles.leadReviewer` is the lead's steps, and it takes `failover.roles.reviewer` when it declares none.

The control socket and the CLI. `resumeEpic` takes an option for each extra reviewer and the lead (`reviewer2`, `reviewer3`, `reviewer4`, `lead`), announced as a new capability that the CLI checks before it sends them, so an engine that lacks it is not asked and the replies the app reads gain nothing the app must know.
`carrier restart` and its prompt for options (`--reviewer-2` to `--reviewer-4` and `--lead`) use it.
The restart of an option today rebuilds the roles from the author and the reviewer only, and drops the lead: it keeps every role, the extra reviewers and the lead, whichever is changed.
Every change to a reply or a config field follows the checklists of `src/control/AGENTS.md` and `src/config/AGENTS.md`: the schema, the defaults, the resolution, the JSON schema, the settings, the contract test and the fixtures under `macos/Tests/Fixtures`; the macOS tests pass without `EngineConfig.swift` carrying the fields.

The snapshot and the replies. The snapshot's `sessions` lists every running execution of an epic and not the newest one, and takes each session's harness and model from the execution's own record and not from the role's saved agent; `PanelEpic.stage` and `PanelSession.stage` never carry `lead`, and carry an optional `lead` flag instead; the optional fields of the epic are `reviewers` (`given`, `of`), `reviewedSha`, `approvedSha`, `leadApproval` and the agents of the extra reviewers and the lead.
In the replies the app reads, `EpicReply.rounds` is built by round and not by review execution, so one round of several reviewers is one round whose `reviewer`, `verdict`, `blockers` and `observations` are the mandatory reviewer's, and an optional list holds the other reviewers' with their slot; `stages` and the session replies carry `lead` as a string.
The text the app shows for a kind of stop learns the two new kinds, and `docs/macos/settings-carrier.md` says what the app does with the Lead reviewer once the engine runs it.

The prompts. The review prompt names the reviewer's slot, gives it only its own earlier blockers, and keeps the contract of the result for every skill; the fix prompt lists blockers with their prefixed ids when the epic has several reviewers; the lead's prompt carries the summaries of the reviewers and the instruction of the formal approval; the intro and the signature that say "reviewer" or "author" from the stage tell the lead apart.

The doctor. The roles of a repo include the extra reviewers for the profile, the provider, the harness, the local model and the token checks, and the skills check asks about each skill each of them invokes, the lead's `lead` skills included.

Documentation is part of each slice, so it never says what the code does not do: `docs/configuration.md` (extra reviewers, `skills.lead`, `maxLeadRounds`, the stage and reason labels, `limits.idleMinutes` as the bound of a slow reviewer, a profile for each reviewer), `docs/cli.md` (the role options of `restart`), `docs/troubleshooting.md` (the two kinds of stop, a round with no verdict), the CHANGELOG, the glossary (Review round, Lead reviewer and Lead round stop being planned), and the specs `autonomous-orchestrator.md` (the rule of one active execution) and `resume-a-stopped-epic.md` (the lead's exchange on a resume); [ADR 0048](../adr/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md) is amended to say what this spec settles.

Testing seams, per story, preferring the seams the repo has:

- Stories 4 to 11, 14 to 17 and 20: the engine through its public interface in `src/orchestration/engine.test.ts`, with the fake `GitHub`, the fake `AgentRunner` that writes, fails, hangs or is cut, an injected clock and a real temporary SQLite; a restart of the engine on the same database covers recovery.
  The fake runner already runs executions together and tells them apart by the task, which now carries the slot.
- The decision of a round and the retry streak per slot as pure functions in their own unit tests, because they are where the cases multiply.
- Story 12: `engine.test.ts` with the profiles of an extra reviewer and the lead and the signals of ADR 0050.
- Stories 1 to 3: `src/config/load.test.ts`, the resolution of skills in its own test, and `src/config/engine-config-contract.test.ts`.
- Story 13: the request and its refusals in `src/control/server.test.ts`, the capability in `src/control/capabilities-contract.test.ts`, the command in `src/terminal/cli/commands/restart.test.ts`, and the engine side in `engine.test.ts`.
- Story 18: `src/doctor/doctor.test.ts`.
- Story 19: `src/status/snapshot.test.ts` and `src/status/snapshot-contract.test.ts` with the fixtures, `src/control/replies.test.ts` for the goldens of the epic's rounds and sessions, and the macOS unit tests, which keep passing.
- The workspaces of the slots: `src/execution/git-workspaces.integration.test.ts` over a temporary repository, for two checkouts at once and the cleanup.
- Story 21: no test: the documentation is checked in review.

## Out of scope

Pausing one epic while the others run (`hold`): its own epic after this one, with a status `held` shown by the label `carrier:status:hold`, set by a person on GitHub or by a command, and resumed from where it was.
It was not asked for by what happened and carries its own races between the label and the engine.

The label orders `carrier:restart`, `carrier:restart:review` and `carrier:restart:fix`, and a `carrier enqueue <repo>#<issue>` command, until someone needs to act from GitHub.

The macOS app beyond keeping it reading: the reviewers and the lead in Settings and in the epic's view, the card for the verdicts and the heads, the labels page, the recover action, the resume-from-stage choice, the card for unanswered observations, and the parity of `EngineConfig.swift`.

Waking up by itself for any kind of stop other than `usage_limit`, `reviewers_failed` included.

A different skill per round, and a skill per harness.

More than four reviewers, reviewers one after another as an option, a limit on the agents running at once on the machine, and a way for a reviewer to look at the lead's commits or the other way round.

Reading from GitHub which account approved, and requiring the approval; the lead's result says whether it submitted one.

Skipping the observations pass on resume, any command that sets a state, a migration of the labels on epics already in flight, and the findings of the engine review that are only suspected: child processes that outlive their agent, a clone whose base is stale, and the environment a child inherits, until there is evidence.

The review of how Carrier treats text written by third parties that the agents read, and of updating the engine while epics are running.
