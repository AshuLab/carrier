# 0045 - Each stage runs a skill the config names, and Carrier keeps the contract

- Status: accepted; amended on 2026-11-23 by the research on where each harness looks
- Date: 2026-11-22

## Context

The skill each stage invokes is written into the prompt files: `ship` for the author's first stage, `code-review` and then `code-post` for the review, `code-resolve` for a fix.
A person who reviews differently, or builds an epic another way, has to edit Carrier's code.
The engine does not read what a skill does inside: it reads the JSON the agent writes and checks the pull request against GitHub.
That is what lets it be free about the skill, and also what a skill must give it.

## Decision

A `skills` block in `engine.json` names the skill of each stage, with a repo's `skills` replacing what it names and inheriting the rest, as `agents` does.
A reviewer, an extra one included ([0048](../review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md)), may declare its own `skills` for the review, and the lead reviewer has the stage `lead`, with `skills.lead`.
The defaults are Solve's: `ship` for ship, `code-review` and `code-post` for review (`review` and `publish`), `code-resolve` for fix.
`lead` defaults to the review skill and `publish` to the publish skill, with a prompt that tells the lead its role.
`publish` can be `null`, for a review skill that publishes by itself.

A skill is only a name, one word of letters, digits, `:`, `.`, `_` and `-`, checked when the config loads.
We do not take free text for a stage, because the text would go into the prompt unchecked and the prompt's snapshots would stop pinning what an agent is told.
The harness spells the invocation (`/name`, or `$name` for Codex), as it does now.

Carrier keeps the rest of the prompt for every skill: who the agent is, the rules, the summaries of earlier turns, and the result contract.
A skill has to leave the engine what it checks:
- ship: an open final pull request whose body closes the epic (`Closes #N`), made in its own linked worktree, because the engine finds that worktree with `git worktree list` after ship and a fix runs in it; with none, the epic stops with the kind `workspace`.
- review: blockers and observations, which the prompt asks the agent to put in the result with stable ids.
- fix: an answer to each finding on the pull request, leaving the threads open.

Before an epic starts, resumes or changes the option of a role, the engine checks that each skill the role invokes exists for the harness and the account of that role, with three answers: present, absent, or cannot tell.
A skill the person named in their configuration that is absent stops the epic in needs-human with the kind `skill_missing`, naming the skill, the role and where it looked, and no agent run is spent and nothing is retried.
A skill that is Solve's default never stops an epic, whatever the answer, because the person has not asked for it and a role that runs today must keep running.
`carrier doctor` runs the same check for the roles of each repo, so the person sees it before an epic is queued.
The epic stops only when the check can tell that the skill is absent: where it cannot read where a harness looks, it lets the epic go on and `carrier doctor` says so.
A run that ends with the harness reporting an unknown skill does not stop the epic in `skill_missing`: [the research](../../research/skill-discovery-per-harness.md) found that no harness reports it as an error for the prompts Carrier sends, so only the check before the start is a signal to rely on.

The skill of each stage is saved with the epic's effective configuration when it starts, so a reload does not change the skill of an epic that is running ([0023](0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)).

## Alternatives considered

Free text per stage lost, for the prompt reason above, and because a skill that needs more words can carry them itself.
A list of skills per stage lost, because the review prompt says different things about reviewing and about publishing, and a list would flatten them.
Configuring the whole prompt lost, because the result contract and the verify-first rule are what let the engine trust any skill.
Global only lost, because how a repo is reviewed belongs to the repo.
Stopping also when the check cannot tell lost, because a valid install in a place the check does not know would be blocked with no way out.
Leaving a missing skill to fail inside the run lost, because the agent may treat an unknown `/name` as plain text and spend a whole run before the engine sees a missing result, and the retries would repeat it.
Stopping for a default skill that is absent lost, because a role on Codex with no Solve skills runs today.

## Consequences

A skill that does not meet the contract fails in ways the engine already knows: a missing result is an invalid result and is retried, a wrong pull request or no worktree stops the epic with its kind.
The sentences of the prompts that name Solve's own files (the `solve.md` worktree mode) are said only with the default ship skill, and the contract sentences are said for every skill.
Where each harness looks for a skill (the account's own folder, the user's, the repo's) differs, so the check has to read those places for the account the role runs on, and it is only as good as that reading: it answers absent only when it read every place the harness reads, and cannot tell where something it cannot read could hold the skill.
`skill_missing` is a new kind of stop, so it gets a reason label and a line in the app's resume card like the others.
Each stage's contract becomes documented behavior that a skill author can rely on, so changing it later is a breaking change for them.
