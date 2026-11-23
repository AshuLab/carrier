# Carrier engine improvements: never stuck, a review to trust, and labels and skills the person names

Status: sharpening

This was one epic of eight parts; it is cut in four epics that go one after another, each from `main` once the one before is merged, and each is specced again against the code of its turn (`to-spec`, after a `pre-check`).
The first, [the engine never leaves an epic stuck](engine-never-stuck.md), took the parts on never being stuck, on recovering and resuming from a stage, and on the wake-up on quota, which were stories 1 to 19 and 67 to 74 here; they are no longer in this file.
The numbers of the stories below are the ones of the original.
The Decisions and the testing seams below are the original's and are written again for each epic when its turn comes.
The order of the rest: a review to trust and intake in order; the labels' new defaults and the skills; several reviewers and a lead.

## Problem

An epic got stuck after a quota error, in a state that no supported action could move.
The way out was to run an external agent that edited SQLite by hand so that Carrier would take the epic again.
Nobody knows the exact state it was in, and that is part of the problem: when an epic stops advancing, the person has no safe first move and no way to see why.

A review of the engine ([the findings](../research/engine-review-2026-11.md)) found that this was not one bug.
An epic can sit in `running` with no agent alive and nothing scheduled to move it, and the only things that move it run when the engine starts.
One unexpected error can stop the engine, or freeze the poll of every epic, and the engine cannot start again while an epic keeps throwing the same error in its recovery.
A resumed epic carries the failures of its previous attempt and can stop again with no retries.
A review is not tied to the commit it was asked to judge, so a verdict can be recorded on a head the reviewer never saw.
Some agent failures are retried at once and blindly, a false authentication signal can stop every epic of a profile, and an exit with an error the tool printed counts as success.
A queued epic is not taken in order, an epic cancelled before it started ignores `ready` when it comes back, and one repo that GitHub answers slowly delays all the others.

Six smaller things hurt around it.
Resume restarts an epic from ship with the review rounds reset, so an epic that stopped on the review limit loses its round count and pays an agent run of `ship` that has nothing left to do.
The labels Carrier reads and writes are fixed names, all under `solve:epic:` although Solve writes two of them and Carrier three, so a person cannot use their own vocabulary and the name does not say who owns a label.
The issue on GitHub says only that an epic is running or stopped, not which stage it is in or why it stopped.
The review of an epic is one agent, so a person cannot ask another provider, another model or a reviewer with a different skill for an opinion, and the `leadReviewer` role the config accepts does nothing.
When an agent's quota runs out and no failover is left, the epic stays stopped until a person resumes it, even when the provider says the window comes back in minutes.
The skill each stage runs is written into Carrier's prompts (`ship`, then `code-review` and `code-post`, then `code-resolve`), so a person who builds or reviews another way has to edit Carrier's code.

It hurts whoever runs Carrier on real epics, today Diego, and we know because it happened and the recovery was manual.

## Solution

The parts still to do, each useful without the next.
The parts on never being stuck come first, because the review round with several reviewers and the automatic recovery both depend on retries and recovery working per execution and per attempt; the labels and the stage skills are independent of the rest and can go at any point, and the wake-up on quota needs the resume from a stage and the attempt rule of the first two.
The order of work: never stuck first, because the attempt rule is under the rest; the labels' first part, which commits what is already in the working tree and changes the defaults, can go beside it; then recover and resume from a stage; then a review to trust, intake and the skills, which do not depend on each other; then the wake-up on quota, which needs the resume from a stage; and the reviewers and the lead last, because they touch the most of the engine and need the attempt rule, the head rule and a state per role.

### A review to trust

A review is tied to the head it was given and a moved head is reviewed again, at most twice in a row and without counting a round ([ADR 0047](../adr/0047-a-review-is-tied-to-the-head-it-was-given-and-a-moved-head-is-reviewed-again.md)).
An authentication failure of an agent does not stop every epic of its profile on one signal: the engine first tries to get a token for that profile, treats the signal as a technical failure of that epic when the token comes, and stops them all only when it does not.
On `agy` the authentication signal counts only on stderr, because its text can appear in a tool's output.
The retries of an `api_error` wait 30 seconds, 2 minutes and 10 minutes, and those of a process that died do not wait; the Codex prefix `usage_not_included` is recognized as a usage limit; and an exit 0 with an error the tool printed is a failure and no longer a success.
No regular expression guesses at quotas, because a false positive would stop an epic as `usage_limit` over a passing error.
The epic records how many observations were left unanswered and why (the pass already taken, or the last round), and the panel and the replies the app reads carry it, with no change to what the engine does.
Smaller, with no decision needed: the blockers handed to a review are none when the latest review completed, the workspace of a fix is checked to exist before launching and its absence stops the epic with the kind `workspace`, the reviewer's checkout is reset and cleaned before each round, the ship prompt takes the head from `gh pr view` and says nothing that only holds for Solve's skills, and an error of `git worktree list` is retried and does not stop the epic.

### Intake in order

The queue is first in, first out: by `queuedAt` and then by `id`, asking GitHub for the oldest first, and an epic a person resumed goes to the end of the line (it starts at once when a slot is free, and waits only when there is competition).
An epic cancelled before it started, because its `ready` was taken off or its issue was closed, goes back to the queue when `ready` comes back, since no work was lost; one cancelled because its pull request was closed without a merge does not, and a person decides with a command.
A repo that fails with `GitHubUnavailable` is skipped for that cycle and shown with its reason, the others go on, and the longest wait GitHub asked for is kept for the next cycle.
Smaller, with no decision needed: `ready` comes off the issue in every status except queued, so a failed label write cannot make a stopped epic restart by itself; the labels already read from the issue decide which ones are removed, instead of one removal for each label the issue lacks; a rate limit ends the poll and waits what GitHub asked for; label writes for a repo that left the config are not made; the reasons of a timeout and of retries exhausted say the limit and the detail, the real message of an authentication error is kept with the epic and not only in `stderr.log`; and an epic whose cleanup kept something is marked as cleaned, with what was kept as an event so it shows.

### Labels the person names

Every label gets a name in the config (the `labels` block in `engine.json`), all distinct, with defaults that follow who writes them: `solve:epic` and `solve:epic:ready` stay as Solve writes them, and what Carrier writes becomes `carrier:status:running`, `carrier:status:ready-for-test` and `carrier:status:needs-human`.
Two optional groups, off until named, add a label per stage (`carrier:stage:building`, `carrier:stage:reviewing`, `carrier:stage:fixing-review`, `carrier:stage:lead-reviewing`) and per kind of stop (`carrier:reason:review-limit` and the others, `carrier:reason:skill-missing`, `carrier:reason:engine-error`, `carrier:reason:reviewers-failed` and `carrier:reason:lead-limit` among them).
The decision and the alternatives are in [ADR 0043](../adr/0043-labels-are-named-by-who-writes-them-and-every-one-is-configurable.md).
A reload applies the names to the next check, `carrier doctor` checks that each repo has the labels Carrier reads (`epic`, `ready`) and says the person creates one that is not a default, and the snapshot carries the names for the panel and the app.

### Skills the person names

A `skills` block in `engine.json` names the skill each stage invokes, with a repo's `skills` replacing what it names and inheriting the rest, as `agents` does, and a role's own `skills` (the author, the reviewer, each extra reviewer and the lead can carry one) winning over both: the role's own, then the repo's, then the global, then Solve's defaults.
The defaults are Solve's: `ship`, `code-review` with `code-post` to publish, and `code-resolve`; a review's `publish` may be `null` for a skill that publishes by itself.
A skill is only a name, checked when the config loads, and Carrier keeps the rest of the prompt and the result contract for every skill.
What a skill has to leave the engine, per stage, is the contract of [ADR 0045](../adr/0045-each-stage-runs-a-skill-the-config-names-and-carrier-keeps-the-contract.md): above all, a ship skill works in its own linked worktree and leaves an open pull request that closes the epic.
The skill is saved with the epic's configuration when it starts, so a reload does not change a running epic.
Before an epic starts, the engine checks that each skill of each of its roles exists for the harness and account of that role, and a missing one stops the epic in needs-human with a new kind, `skill_missing`, with no agent run spent and no retry; `carrier doctor` runs the same check.
The epic stops only when the check can tell the skill is absent: where it cannot, it lets the epic go on and `doctor` says so.
How a run that names a skill the tool does not have ends is an open question, and until it is answered only the check before the start stops the epic.

### Several reviewers and a lead

The decision is [ADR 0048](../adr/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md).
An epic has one mandatory reviewer and up to three more (`agents.extraReviewers`), each with its own profile, provider, model, effort, persona and, if it wants, skills, and a repo overrides them as it does the other roles, a list replacing the whole list.
A review round runs all of them in parallel on the same head, each in its own checkout, and ends when every one has settled; a reviewer that fails or cannot conclude does not stop the round, one verdict is enough for it to count, and with none the epic stops in needs-human with the kind `reviewers_failed`.
The epic records and shows how many reviewers gave a verdict out of how many were configured.
A reviewer with blockers still open that gives no verdict in a later round is not agreement: the round does not close as completed, and the epic stops in needs-human with `reviewers_failed` naming it.
Each extra reviewer and the lead keep their own option, failover and retry state, as the author and the reviewer do; the lead has its own failover steps and one that declares none takes the reviewer's, and a lead that runs out of retries stops the epic with `retries_exhausted` naming it.
An authentication failure of the profile of any role stops the epics that use it, not only those of the author's and the mandatory reviewer's.
The CLI names them `--reviewer`, `--reviewer-2` to `--reviewer-4` and `--lead` where `carrier restart` takes an option for a role.
Any request for changes sends the blockers of all reviewers to the author once, each blocker keeping the id of the reviewer that raised it (prefixed, `reviewer-2:B1`, so the ids of two reviewers never collide) and resolved only by that reviewer, and the fix gets one list built from the latest result of each reviewer; the observations of all go to the one pass; and a round counts once toward `maxReviews`.
A head that moves during a round repeats the whole round on the new head, under the rule of ADR 0047.
The optional `leadReviewer` runs once the reviewers agree, with its own skill (`skills.lead`, by default the review skill with a prompt for its role); its skill gives the formal approval of the pull request with its identity, and the engine records whether GitHub shows it without requiring it.
If the lead asks for changes, the exchange is between the author and the lead alone, up to `limits.maxLeadRounds` (3 by default), and then the epic stops in needs-human with the kind `lead_limit`.
The epic keeps the head the reviewers agreed on and the head the lead approved, and shows both when they differ.

### What was cut, and why

A command that sets any state lost, because it would let a person leave SQLite in combinations the engine never produces, which is what the manual edit did, now with a button; if `recover` cannot move a real case, that case tells us which verb is missing.
Labels as the first way to control an epic lost, because the poll sees a label up to five minutes later and anyone who can label issues in the repo could start agents that spend credits; the person works from the Mac, so the label orders go last.
Restarting the engine as the answer lost, because it interrupts every other epic's agents.
Letting the engine crash and rely on a supervisor lost, because nothing restarts a detached engine.
Stage and reason labels on by default lost, because each stage label is an extra write at every stage change.
Renaming Solve's two labels lost, because Solve puts `solve:epic:ready` at its hand-off and the epic would stop queueing without a sound.
A `labelPrefix` setting lost, because Solve's labels do not follow it and a person's own names would not fit one prefix.
Free text for a stage lost, because it would reach the prompt unchecked and the prompt's snapshots would stop pinning what an agent is told.
A list of skills per stage lost, because the review says different things about reviewing and about publishing.
Configuring the whole prompt lost, because the contract and the verify-first rule are what let the engine trust any skill.
Reviewers one after another lost, because the person wants them in parallel, though it would have kept the one-execution rule.
A `reviewers` list in place of `reviewer` lost, because it breaks every config and the app.
Repeating the whole round after the lead asks for changes lost, because the lead is the final reviewer and an exchange with the author alone is cheaper.
Stopping the epic when a reviewer fails lost, because an extra reviewer that is down would block reviews that worked.
A guess at quota texts by pattern lost, because a false positive would stop an epic over a passing error.
A timer from the text of the error lost, because Codex gives its time as a local-time string, Claude and `agy` give none, and the probe gives it exactly.
Resuming without looking at the probe again lost, because a reset that moved would spend the retries of the epic and stop it again.
A new status for the epic that waits lost, because it keeps no slot, the reason label already exists and the app needs one line more.
On by default lost, because it spends credits unattended and the person should choose it.

## Scope

20. As the person, a review whose result carries a head other than the one the reviewer was given is an invalid result and is retried.
21. As the person, when the head of the pull request moves while a review runs, the review is made again on the new head without counting a round, at most twice in a row, and then the epic stops in needs-human with `pr_invalid`.
22. As the person, one authentication signal from an agent makes the engine try to get a token for that profile first: if it gets one the epic has a technical failure and the profile's other epics go on, and if not every epic of the profile stops as today.
23. As the person, on `agy` the authentication signal counts only when it comes on stderr.
24. As the person, an `api_error` is retried after 30 seconds, then 2 minutes, then 10 minutes, and a process that died is retried at once.
25. As the person, the Codex message that starts with `usage_not_included` is a usage limit, and an exit 0 with an error the tool printed is a failure and not a success.
26. As the person, an epic that goes to ready for test with observations left unanswered says how many and why, in the panel and in the replies the app reads.
27. As the person, a review never receives the blockers of an earlier round when the latest review completed.
28. As the person, a fix whose saved workspace does not exist stops the epic in needs-human with the kind `workspace` and a clear reason, and does not burn its retries.
29. As the person, the reviewer's checkout is reset and cleaned before each round, so nothing from the last round is in it.
30. As the person, the ship prompt takes the head of the pull request from `gh pr view`, and says nothing that only holds for Solve's skills when another skill is configured.
31. As the person, an error of `git worktree list` after ship is retried and does not stop the epic.
32. As the person, queued epics start in the order they entered, and an epic I resumed goes to the end of the line.
33. As the person, an epic cancelled before it started because its `ready` was removed or its issue closed goes back to the queue when `ready` comes back, and one cancelled because its pull request was closed without a merge does not.
34. As the person, a repo that GitHub answers slowly or with an outage is skipped for that cycle with its reason, and the other repos are read, queued and launched as usual.
35. As the person, `ready` is taken off the issue in every status except queued, so a failed label write cannot restart a stopped epic by itself.
36. As the person, a status change writes only the labels that are present on the issue and not one removal per label that is missing.
37. As the person, a rate limit ends the poll and Carrier waits what GitHub asked for, instead of going on asking.
38. As the person, Carrier writes no label to a repo that left the config.
39. As the person, a timeout stop says the limit and what to do next, a retries-exhausted stop says the detail of the last failure, and the real message of an authentication error is kept with the epic.
40. As the person, an epic whose cleanup kept a worktree or a branch is marked as cleaned, and what was kept shows as an event.
41. As the person, I name each label of the five roles in `labels`, and a config where two roles, stages or kinds of stop share a label, whatever the case, is refused naming the second.
42. As the person, the defaults are `solve:epic` and `solve:epic:ready` for what Solve writes and `carrier:status:*` for what Carrier writes, and the stage and reason labels are off until I name them.
43. As the person, a reload applies the label names to the next check, `carrier doctor` reports a repo missing a label Carrier reads, and tells me to create it myself when its name is not a default.
44. As the person, I name the skill of each stage in `skills`, globally and per repo, a repo inheriting what it does not name, a role's own `skills` winning over both, and a name with anything but letters, digits, `:`, `.`, `_` and `-`, or longer than 64 characters, is refused when the config loads.
45. As the person, the prompts invoke the configured skill, spelled `/name` or `$name` by harness, and the skill of an epic that is running does not change with a reload.
46. As the person, an epic whose skill the check can tell is missing for its role's harness and account stops in needs-human with `skill_missing` before any agent run, and `carrier doctor` reports the same.
47. As the person, where the check cannot tell, the epic goes on and `carrier doctor` says so.
48. As the person, I configure up to three extra reviewers with `agents.extraReviewers`, each with its own profile, provider, model, effort, persona and skills, and a repo's list replaces the whole list.
49. As the person, a review round runs every reviewer in parallel on the same head, each in its own checkout, and ends when all of them have settled.
50. As the person, a reviewer that fails or cannot conclude does not stop the round, one verdict is enough, and with no verdict the epic stops in needs-human with `reviewers_failed` naming each reviewer and why.
51. As the person, the epic shows how many reviewers gave a verdict out of how many I configured.
52. As the person, when any reviewer asks for changes the author fixes once with the blockers of all of them, each blocker keeping its reviewer's id and resolved only by that reviewer, and the next round runs every reviewer on the new head.
53. As the person, the observations of all reviewers go to the author in the one pass the epic has, and a round counts once toward `maxReviews`.
54. As the person, with a lead reviewer configured, it runs once the reviewers agree, and when it completes the epic is ready for test, with its formal approval recorded if GitHub shows it and not required to go on.
55. As the person, when the lead asks for changes the author fixes and only the lead reviews again, up to `limits.maxLeadRounds`, and then the epic stops in needs-human with `lead_limit`.
56. As the person, the epic keeps and shows the head the reviewers agreed on and the head the lead approved when they differ, and the lead's stage has its own optional stage label.
57. As the person, a reviewer with blockers still open that gives no verdict in a later round does not let the round close as agreed: the epic stops in `reviewers_failed` naming it.
58. As the person, the id of each blocker carries its reviewer, so the ids of two reviewers never collide, and the fix gets the latest blockers of every reviewer.
59. As the person, each extra reviewer and the lead have their own option, failover and retry state; the lead's own failover steps, or the reviewer's when it declares none, apply, and a lead that runs out of retries stops the epic with `retries_exhausted` naming it.
60. As the person, an authentication failure of the profile of any role, an extra reviewer or the lead included, stops the epics that use it.
61. As the person, `carrier restart` takes an option for `--reviewer-2` to `--reviewer-4` and `--lead` as it does for `--author` and `--reviewer`.
62. As the person, a resume at a stage goes through the queue, remembers the stage and the rounds granted, takes a slot like any epic, and the cap of rounds is kept per epic.
63. As the person, a role's own `skills` wins over the repo's, the repo's over the global, and the global over Solve's defaults.
64. As the person, an epic that started before this version, whose saved configuration has no `skills` and no extra reviewers, goes on with Solve's defaults and one reviewer.
65. As the person with an app that does not know the stage `lead`, the snapshot reports it as `review` with an optional `lead` flag, so the app does not fail to read it.
66. As the person, each part leaves its user documentation written: `configuration.md`, `cli.md`, `troubleshooting.md`, the CHANGELOG and the glossary, and the specs it changes.

## Decisions

The engine's rules, in one table, for what changes in the stage loop; the rest of the stage loop is as in [the orchestrator spec](autonomous-orchestrator.md).

| After | Condition | Next |
| --- | --- | --- |
| `ship` | pull request valid | review round 1, every reviewer in parallel |
| review round | no reviewer gave a verdict | needs-human `reviewers_failed` |
| review round | any verdict asks for changes, round below `maxReviews` | `fix` with the blockers of all, then the next round |
| review round | any verdict asks for changes, round at `maxReviews` | needs-human `review_limit` |
| review round | the head is not the one the round started on | the round again on the new head, not counted, at most twice in a row, then needs-human `pr_invalid` |
| review round | every verdict completed, observations, pass not taken, round below `maxReviews` | `fix`, the observations pass |
| review round or pass | every verdict completed, head unchanged after the pass | agreed head: the lead if configured, else ready for test |
| pass | head changed | the next review round |
| lead | completed | ready for test, approval recorded |
| lead | asks for changes, lead rounds below `maxLeadRounds` | `fix`, then only the lead again |
| lead | asks for changes, at `maxLeadRounds` | needs-human `lead_limit` |
| lead | cannot conclude | needs-human `agent_needs_human`, naming the lead |
| lead | technical failure, retries out | needs-human `retries_exhausted`, naming the lead |

The shape of the config, as an example of the keys and not of values:

```json
{
  "labels": {
    "ready": "solve:epic:ready",
    "running": "carrier:status:running",
    "stages": { "review": "carrier:stage:reviewing", "lead": "carrier:stage:lead-reviewing" },
    "reasons": { "usage_limit": "carrier:reason:usage-limit" }
  },
  "skills": {
    "ship": "ship",
    "review": { "review": "code-review", "publish": "code-post" },
    "fix": "code-resolve",
    "lead": { "review": "code-review", "publish": null }
  },
  "agents": {
    "author": { "profile": "author-bot", "provider": "claude", "model": "<model>" },
    "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "<model>" },
    "extraReviewers": [{ "profile": "reviewer-bot", "provider": "claude", "model": "<model>", "skills": { "review": { "review": "my-review" } } }],
    "leadReviewer": { "profile": "reviewer-bot", "provider": "claude", "model": "<model>" }
  },
  "limits": { "maxLeadRounds": 3, "idleMinutes": 45, "autoResume": true, "autoResumeMaxHours": 12 }
}
```

A skill name matches `/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/`, tried against the empty string, blanks, a leading `/` or `$`, a path, a newline, a semicolon, non-ASCII letters and 65 characters, which it all refuses, and against `ship`, `solve:ship` and 64 characters, which it takes.
`skills.lead` has the shape of `skills.review` and takes its values when it names none.
`limits.idleMinutes` has no default: it is off until set.
`limits.autoResume` is false by default and `limits.autoResumeMaxHours` is 12.

The data. The kinds of stop `engine_error`, `skill_missing`, `reviewers_failed` and `lead_limit` join `needsHumanKinds`, and `lead` joins the stages, the stage label names and the executions' stage.
An execution carries the reviewer it belongs to (`reviewer`, `reviewer-2`, and so on, none for the author and for epics from before) and the round it ran in, which it already has.
The epic carries the head the reviewers agreed on, the head the lead approved, how many reviewers gave a verdict out of how many were configured, and how many observations were left unanswered with why; `reviewedSha` stays the head the last deciding reviewer approved.
The epic also carries `resumeAt` (epoch milliseconds, null) and the count of automatic resumes in a row, and the events `auto_resume_scheduled` and `auto_resumed`.
The attempt is not a new column: it is `executions.startedAt` at or after `epics.startedAt`, which the reserve sets and a restart clears.
The retry streak and the recovery read executions within that attempt, and for the reviewers within that attempt and that reviewer.
A migration comes with `pnpm db:generate`, and the epic's saved configuration gains the skills and the extra reviewers, so a reload changes nothing for an epic that runs.

The control socket and the CLI. `recoverEpic` is a new request and capability, and `resumeEpic` takes an optional `from` (`ship`, `review`, `fix`) and `extraRounds`, announced as the capability `resumeFromStage`, so an engine that lacks it is not asked and the app only sends them when the hello lists it.
`carrier recover` and `carrier restart --from` use them, and the replies the app reads gain the new fields as optional, per the checklist of `src/control/AGENTS.md`.
Every change to a reply or a config field follows the checklists of `src/control/AGENTS.md` and `src/config/AGENTS.md`, including the fixtures under `macos/Tests/Fixtures`.
The `labels` block, the stage and reason groups, the distinctness rule, the doctor check and the snapshot field already exist in the working tree as backend only and not committed, with the old defaults: the first slice commits them and changes the defaults.

Compatibility. The stage of the snapshot keeps the values `ship`, `review` and `fix` that the app's strict enum reads, and the stage `lead` is reported as `review` with an optional `lead` flag until the app knows it; the kinds of stop are strings in the app and need nothing.
An epic saved before this version has a configuration with no `skills`, no extra reviewers and no lead state, and it is read with the defaults.
Documentation is part of each part: `docs/configuration.md` (labels, skills, extra reviewers, lead, limits), `docs/cli.md` (`recover`, `restart --from`, the role options), `docs/troubleshooting.md` (a stuck epic, the new kinds), the CHANGELOG and the glossary, and the specs `resume-a-stopped-epic.md` (the rounds no longer always restart) and `autonomous-orchestrator.md` (the rule of one active execution) are amended.
Each extra reviewer and the lead have their own option and failover state in the saved configuration, and the columns `authorOption` and `reviewerOption` become a state per role.

The review round runs its executions together and waits for all of them to settle before it decides, and the decision is a function of the stored results of the round, so a restart or a retry sees the same thing.
The checkout of each reviewer is `reviews/<repo>/<epic>/<reviewer>`, separate from the others and from the author's worktree.
The engine's rule that an epic never has two active executions becomes: never two of the same role, and never the author and a reviewer at once.

Testing seams, per story, preferring the seams the repo has:

- Stories 1 to 10, 21, 32 to 40, 49 to 60, 62 and 64: the engine through its public interface in `src/orchestration/engine.test.ts`, with the fake `GitHub`, the fake `AgentRunner` that writes, fails, hangs or is cut, an injected clock and a real temporary SQLite; a restart of the engine on the same database covers recovery. The fake runner learns to run several reviewers at once.
- Stories 11 and 12: the process hygiene in `src/harnesses/host-runner.integration.test.ts`, gated as the others are, and the idle rule as a pure function of the clock and the time of the last output, in its own unit test.
- Stories 13 to 19 and 61: the request and its refusals in `src/control/server.test.ts`, the capabilities in `src/control/capabilities-contract.test.ts`, the replies as goldens in `src/control/replies.test.ts`, the commands in `src/terminal/cli/commands/restart.test.ts` and a new one for `recover`, and the engine side in `engine.test.ts`.
- Stories 20 and 22 to 25: the failure kinds and the exit rules in `src/harnesses/claude.test.ts`, `codex.test.ts` and `agy.test.ts`, and the retry waits, the token probe and the review head rule in `engine.test.ts`.
- Stories 26 to 31: `engine.test.ts` for the unanswered observations, the blockers, the workspace check and the `git worktree list` retry, `src/prompts/build-prompt.test.ts` for the ship prompt, and `src/execution/git-workspaces.integration.test.ts`, gated, for the reviewer's checkout.
- Stories 67 to 74: `engine.test.ts` with the injected clock and a fake quota port the engine reads (the probe's `QuotaSnapshot`, with `resetsAt` and a fresh read that can fail or be rate limited), plus the pure rule that takes the exhausted windows and the failover options to a `resumeAt` in its own unit test.
- Stories 41 to 48, 63 and 65 (the snapshot, with its contract test): the config in `src/config/load.test.ts`, the label check and the skill check in `src/doctor/doctor.test.ts`, the snapshot in `src/status/snapshot.test.ts` and `snapshot-contract.test.ts`, the prompts in `build-prompt.test.ts`, and the contract with the app in `src/config/engine-config-contract.test.ts`.
- Story 66 has no test: the documentation is checked in review.
- The macOS side of the contract fixtures and the app's own views are out of this epic, and the Swift contract tests fail until `EngineConfig.swift` carries the new fields.

## Out of scope

Pausing one epic while the others run (`hold`): its own epic after this one, with a status `held` shown by the label `carrier:status:hold`, set by a person on GitHub or by a command, and resumed from where it was.
It was not asked for by what happened and carries its own races between the label and the engine.

The label orders `carrier:restart`, `carrier:restart:review` and `carrier:restart:fix`, and a `carrier enqueue <repo>#<issue>` command, until the parts above exist and someone needs to act from GitHub.

The macOS app (the labels page, the recover action, the resume-from-stage choice, the card for unanswered observations, the reviewers and the lead) and a CLI setter for the labels: this epic is backend first.

Waking up by itself for any kind of stop other than `usage_limit`, and the app's view of the wait.

A different skill per round, and a skill per harness.

More than four reviewers, reviewers one after another as an option, and a limit on the agents running at once on the machine.

Skipping the observations pass on resume, any command that sets a state, a migration of the labels on epics already in flight, and the findings of the engine review that are only suspected: child processes that outlive their agent, a clone whose base is stale, and the environment a child inherits, until there is evidence.

The review of how Carrier treats text written by third parties that the agents read, and of updating the engine while epics are running.

## Open questions

Which quota messages the recognizers miss.
Each harness decides `usage_limit` from a short fixed list of texts (Claude only the 429 `usage_limit_reached`, Codex four starts plus the one now added, `agy` three), and anything else is an `api_error`.
It needs real error outputs from each CLI to see which variants fall through, since no pattern will guess them.

How to tell that a skill exists, for each harness.
Claude, Codex and Antigravity look in different places (the account's folder, the user's, the repo's), and the check has to read those for the account a role runs on.
It needs a look at each CLI's real layout, and a run with a skill that is not installed to see what each one does with an unknown `/name` or `$name`.
That run also decides whether a first run that reports an unknown skill can stop the epic in `skill_missing`, which stays out of this epic until then.
