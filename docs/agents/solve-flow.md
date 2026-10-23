# solve skills - the flow

This repo uses the **solve** skill set to take an idea from raw to shipped. Each step is a skill - invoke it however this agent invokes skills. The commands each step runs (tracker, branching, worktrees) are in `solve.md`.

## Where to enter
The entry point is what you already know, not whether it's a feature or a bug:
- the problem isn't clear (can't yet say what hurts, for whom, how you'd know it's fixed) -> `sharpen`; a fuzzy bug enters here too
- the problem is clear, the cause isn't (it misbehaves and you don't know why) -> `diagnose`
- both are clear, it's just work to cut -> `to-tickets`, or straight to `ship` if it's already one startable slice; if it came from outside (someone else's issue, a handed-down ticket) run `pre-check` first
- first time in this repo and you want worktree isolation -> `setup` (optional: without it github is inferred and there's one working tree; the repo needs a GitHub remote either way)

## The flow
Each step consumes what the previous one left, so they run in order.

- `sharpen` - take a raw idea, doc or issue to a brief: reality-check + capture the thinking (grill it first with the follow skill `pushback` if it's raw)
- `to-spec` - turn the brief into a PRD, deciding where each story gets tested
- `to-tickets` - break the PRD into vertical, agent-ready slices
- `ship` - take a startable ticket to done: claim, build, close the loop (a PR). Handed the epic instead, it drains every slice in dependency order. It works in the shared tree by default; with worktree isolation (`solve.md` -> Worktrees) each epic drains in its own git worktree, so concurrent epics don't collide, and `land` removes it
- `land` - once you've read the integration PR and accept it: merge it, then close out the epic branch, its worktree and the epic issue. The step a human starts

## Reviewing
`ship` ends at a draft integration PR; a review pass sits between it and `land`. Nothing starts the review of the integration PR automatically: whoever is driving, a person or an agent, runs `code-review` on that PR.
Two sides, which may be different people or agents:
- reviewer - `code-review` reads the PR and returns findings (it never publishes); `code-post` delivers them as PR comments once approved
- author - `code-resolve` judges each comment on your own PR, fixes what applies, pushes, replies on each thread and leaves a summary on the PR - unattended

Suggested loop: repeat until a review pass has no blockers, then the PR is ready for `land` (`land` has its own gates - no conflicts, every slice closed, a green suite, a clean mergeable PR and a human yes - so a repo that requires reviews stops at BLOCKED until they are in; on your own PR GitHub won't let you approve, so a solo review is comments only). No round limit is enforced - if it isn't converging, bring a person in.

## Where a person is needed
- `sharpen` - a conversation; the product calls are the user's
- `to-spec` - the open questions that are about what the product should do, and the milestone
- `to-tickets`, `code-post`, `file-issue` - the text is approved before it's published (`file-issue` publishes without waiting when `code-resolve` invokes it)
- `diagnose` - the diagnosis is shown and a person picks a fix before any code changes
- `land` - a person read the integration PR and accepts it
- `ship` - an epic drain runs unattended and stops at the draft integration PR; it also stops on a dirty tree, a failed slice or a merge conflict
- `setup` - a few questions, optional

When nobody can answer: `code-post`, `file-issue`, `land` and `diagnose` stop and hand over (or show) what they prepared instead of acting; `sharpen`, `to-spec` and `to-tickets` wait for the answer. An agent running unattended stops at those points - it doesn't answer for the person.

## Reach for these any time
- the follow skill `pushback` - stress-test an idea, plan or decision, nothing written (`sharpen` invokes it for a raw idea)
- `research` - external facts before you can decide; primary sources, findings saved in the repo
- `prototype` - a design question only code can answer; throwaway, the output is a decision
- `vocab` - pin down a term or record a hard-to-reverse decision (glossary + ADRs)
- `tdd` - the behavior is clear and a seam exists; also turns a `diagnose`-reproduced bug into a regression test
- `pre-check` - revalidate a spec or ticket that sat a while or came from outside, before it advances
- `file-issue` - you ran into something that isn't this task's job; write it up as one GitHub issue (labelled `solve:raw`) and keep working
- `guide` - not sure which skill fits; it points, it doesn't do the work

## Where things live
- PRDs / specs -> `docs/specs/`
- Glossary + ADRs -> `docs/glossary.md`, `docs/adr/` (always files)
- Tickets -> GitHub Issues

What each step leaves for the next: `sharpen` a brief in `docs/specs/` -> `to-spec` the PRD, published as the epic issue -> `to-tickets` one sub-issue per slice -> `ship` a PR per slice, then one draft integration PR -> `land` the merge.

