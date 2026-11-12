# The engine starts without waiting for GitHub

Status: spec

## Problem

Starting Carrier opens its control socket only after the engine's start-up steps end, and one of them, `ensureLabels`, asks GitHub once for every watched repo, one after the other, each call through a token that is minted for it. On 0.3.0 with six repos the log says "carrier started" at 14:04:23 and the socket answers at 14:04:51, about 28 seconds, near 4.7 seconds per repo. The Mac app waits 15 seconds for the socket (`startTimeout`) and `carrier start` waits the same, so the person who pressed Start Carrier was told that it did not start while it was still starting, with an empty log.

The cost grows with the number of repos watched: a hundred repos would be about eight minutes before the socket opens, and no fixed wait is right for that. It is felt first by whoever starts Carrier from the app after the settings grew to several repos, and by anyone who watches many.

We know it is solved when the time Carrier takes to answer on its socket does not depend on how many repos it watches, and Start Carrier on the six repos of this Mac answers in a few seconds.

What start-up has to do and what it does not: the owned labels (`solve:epic:running`, `solve:epic:ready-for-test`, `solve:epic:needs-human`) are needed only when the engine writes a status label on an epic's issue, which happens when it takes an epic, when a stage ends and when it puts back a label that differs. Nothing reads them at start. The other start-up step, `recover`, is the safe restart after a cut (orphan agents, interrupted executions, running epics relaunched, labels put back) and costs by the epics in flight, not by the repos: on this Mac, 13 epics and one call to GitHub.

## Solution

A repo's owned labels are ensured lazily: right before the first label write on that repo, once per process for each repo (the `labelledRepos` memory that exists), and not in `start()` nor at the head of every `poll()`. Start-up then runs `recover` only. A repo with nothing to write never costs a call, so a hundred watched repos cost what the few with an epic taken cost, spread over the cycles that take them.

Every label write of the engine goes through one function, `applyLabels` (called when an epic begins, when its workspace could not be prepared, and by the reconcile of `recover`), so that is the one place that ensures. What it ensures does not change: Carrier creates only its three owned labels that the repo lacks, with their colour and description from `labelStyles`, never touches existing ones and never creates `ready`, which is Solve's.

A failure to ensure the labels is a failure of that write, as if `setLabels` had failed: the exception goes up the same way, the epic's `labelPending` stays true, nothing is launched for it, and the next cycle tries again, as it already does when GitHub is down. The ensure stays whether or not GitHub creates by itself a label that is added to an issue and does not exist (in `AshuLab/carrier` the three labels have GitHub's default grey and no description, which suggests it does, and this was not tested): the ensure is what gives them their colour and description, and nothing depends on the other behaviour.

What was cut: raising the app's wait from 15 to about 60 seconds, because it is a number that breaks again with more repos and fixes only the app, not `carrier start`; opening the control socket before the start-up steps, because it changes what a socket that answers means (running or starting) for the app and for `carrier status`, which is a question of what the person sees and is left for after this; running `ensureLabels` for the repos in parallel, because it still makes one call per repo at start and only shortens the wait, where lazy makes the calls disappear.

## Scope

1. Carrier answers on its control socket without a call to GitHub when no epic is in flight: the engine's start-up asks GitHub nothing for the repos it watches, and so its length does not depend on how many.
2. The first time the engine writes a label on a repo, it creates the owned labels that repo lacks, with their colour and description, never `ready` and never one that exists; it creates them for that repo only, and the next write on the same repo asks nothing more.
3. A repo where an epic never gets a label is never asked for its labels.
4. When creating the labels fails (GitHub down or refusing), the epic keeps `labelPending`, is not launched, and the next poll tries again and goes on when it works.
5. The docs and the changelog say that the labels are created when an epic is first labelled in a repo, no longer at start.

## Decisions

- One place: `applyLabels` ensures the repo's labels before it writes; the `ensureLabels()` loop and its two callers (`start()` and the head of `poll()`) are removed, and the `labelledRepos` memory is kept. No new option and no new state: the failure path is the one a failing `setLabels` already has.
- `recover` is left as it is, label check included; the polling cycle and what the app shows while Carrier starts are out of scope (below).
- Testing seams, all in `src/orchestration/engine.test.ts`, which drives the engine with `FakeGitHub` (its `created`, `styles`, `repoLabels` and the call counter) and a fake clock. The test that says "startup creates only the missing owned labels" is rewritten around stories 1 to 3: a start with nothing in flight records no call to `listLabels` or `createLabel`; taking an epic in `AshuLab/a` creates that repo's missing owned labels with their style and not `ready`, and none for `AshuLab/b`; a second epic in `AshuLab/a` creates nothing more. Story 4 is one test: `createLabel` made to throw `GitHubUnavailable` leaves the epic `labelPending` with no launch, and after the next poll with GitHub back its labels exist and it launches. The tests that count the fake's calls after a start are adjusted to the ones that remain. Story 5: no test; `docs/specs/autonomous-orchestrator.md` (step 8 of the flow) and the changelog line are read in review. No Swift change and no test in `macos`.
- To check by hand once, on the real Mac: Start Carrier answers in a few seconds with the six repos. It cannot be a test, because the time is GitHub's.

## Out of scope

The polling cycle: what it reads for every repo, which of that is only for display (progress, slices, pull request blocks, [ADR 0008](../adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)), and reading repos in parallel with a limit. It scales with the repos too, but it runs in the background after start and has its own ticket and its own measurements.

What the app and `carrier start` show while Carrier is starting: the 15-second cap, a "starting" state, the text of the failure. It waits until the engine side is done and the start time is known again.

The label check at the end of `recover` (labels that differ on GitHub are put back), which stays as it is.
