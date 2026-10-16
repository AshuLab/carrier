# End-to-end integration with the test repo (slice #33)

Date: 2026-10-16. Environment: macOS, Node 26.12.0, pnpm, `agent-forge`, Claude Code (`~/.local/bin/claude`), Codex CLI, `gh` logged in as Diego (only to seed and count). Test repo: `AshuLab/carrier-sandbox` ([sandbox-repo.md](sandbox-repo.md)).

Result: the five scenarios in the Definition of done ran with the real Carrier (the CLI, as a process), Claude, Codex, Forge and Solve. **Two real Carrier bugs** were found and fixed, plus several harness ones; one minor risk remains open (§4). The evidence for each scenario came from different runs, because the first pass was cut short by a harness error and by the first bug (§3); see the traceability in §2. There are no deviations from the spec.

## 1. Setup

Code: `src/e2e/harness.ts` and `src/e2e/carrier.integration.test.ts`. It runs with `pnpm test:integration` and **skips itself** if the variables are missing, so it does not run in `pnpm test`. It takes minutes per scenario and costs money.

| Variable | Value used | Purpose |
| --- | --- | --- |
| `CARRIER_E2E_REPO` | `AshuLab/carrier-sandbox` | disposable repo; the name must end in `sandbox` (the harness rejects it otherwise) |
| `CARRIER_E2E_AUTHOR_AGENT` | `artanis-agent` | the author's Forge agent (also the orchestrator) |
| `CARRIER_E2E_REVIEWER_AGENT` | `tassadar-agent` | the reviewer's Forge agent; it has to be a different one |
| `CARRIER_E2E_AUTHOR` | `claude:sonnet` (default) | `<claude\|codex>:<model>` |
| `CARRIER_E2E_REVIEWER` | `codex:gpt-5.6-luna` (default) | same |
| `CARRIER_E2E_SCENARIOS` | `a,b,c,d,e` (default) | which scenarios to run |
| `CARRIER_E2E_SKILLS_DIR` | unused | copies `code-review` and `code-post` to the sandbox's `.agents/skills`; they are already on its `main` |
| `CARRIER_E2E_KEEP` | optional | do not delete the temporary root when finished |

```sh
CARRIER_E2E_REPO=AshuLab/carrier-sandbox CARRIER_E2E_AUTHOR_AGENT=artanis-agent CARRIER_E2E_REVIEWER_AGENT=tassadar-agent \
  CARRIER_E2E_SCENARIOS=c pnpm test:integration
```

Before running: no sandbox epic with `solve:epic:ready` (the harness stops if there is one, because Carrier would import it). Profiles: `author` = Forge `artanis-agent` (Claude `sonnet`), `reviewer` = Forge `tassadar-agent` (Codex `gpt-5.6-luna`). Generated config: `pollIntervalMinutes: 0.2` (12 s, to avoid waiting 5 min between polls), `maxConcurrentEpics: 2`, `maxReviews: 2`, `maxExecutionRetries: 2`, `maxExecutionHours: 1`. Carrier's `cwd` is a temporary folder outside any clone, on purpose.

Each scenario seeds its own epic (spec committed to the sandbox's `main` before setting it `ready`, epic issue, slices with `--parent` and `--blocked-by`), marks it `solve:epic:ready` by hand, starts `carrier --config` as a child process and counts on GitHub **before and after** with `gh api` (PRs by branch, epic comments, PR comments and reviews, unique commits by SHA on the epic's branches). It reads SQLite in read-only mode for epic and execution states. It leaves `e2e-evidence.log`, `carrier.stdout.log` (the panel) and `carrier.config.json` in the temporary root.

## 2. Results by scenario

Each row says which run it comes from. The temporary roots (`/var/folders/.../T/carrier-e2e-<id>/`) are disposable; what follows is copied from their `e2e-evidence.log` and from GitHub.

### a. Two-slice epic, `ready` by hand, ends in `ready-for-test`

Runs: the initial pass (epic `#21 Reverse x0l7`; its `e2e-evidence.log` no longer exists, the trail remains on GitHub) and, again with two slices, that of scenario c (`#71 Initials nv27`), which was also cut with `kill -9`. `a` was not run alone again because of cost: what `a` asserts is in the GitHub trail of both.

`#71` (issue events, `gh api repos/AshuLab/carrier-sandbox/issues/71/events`):

```
21:37:55Z labeled   solve:epic:ready            vemec           (by hand)
21:38:14Z labeled   solve:epic:running          artanis-agent[bot]
21:38:19Z unlabeled solve:epic:ready            artanis-agent[bot]
21:41:55Z labeled   solve:epic:ready-for-test   artanis-agent[bot]
21:41:57Z unlabeled solve:epic:running          artanis-agent[bot]
```

- Final labels `["solve:epic","solve:epic:ready-for-test"]`; `ship` and `review` executions finished; workspace under `<root>/worktrees/carrier-sandbox/initials-nv27`.
- 3 PRs: slice 1 (`#74`), slice 2 (`#75`), integration `#76` (`feat/initials-nv27/epic -> main`, draft, `Closes #71`), only one with `Closes #71`. Author of the PRs and of all commits: `artanis-agent[bot]`; the review of `#76`: `tassadar-agent`, `COMMENTED`. Different profiles, neither is Diego.
- `#21` (initial pass): `#26` integration, draft, by `artanis-agent`, 2 reviews by `tassadar-agent`; `ready` 20:49:04Z, `ready-for-test` 20:53:43Z (4 min 39 s).

### b. Concurrency 2, two epics of the same repo

Run `carrier-e2e-pxhvs7` (`#47 Double lnsx`, `#49 Negate lnsx`, one slice each):

```
21:08:21Z carrier started pid=15215
21:08:57Z b: both epics running at once; running executions per epic 1 and 1; agent processes [17043,18960]
21:12:18Z b: #47 {"status":"ready_for_test","prNumber":54,"workspace":".../worktrees/carrier-sandbox/double-lnsx"}
21:12:18Z b: #49 {"status":"ready_for_test","prNumber":53,"workspace":".../worktrees/carrier-sandbox/negate-lnsx"}
21:12:20Z b: files of the integration PRs: #54 ["README.md","double.js","double.test.js"] #53 ["README.md","negate.js","negate.test.js"]
```

Two agents alive at the same time (one per epic), separate workspaces and review folders (`reviews/carrier-sandbox/<epic>`), each integration PR touches only its own function, with its own branches, comments and commits and no duplicates. The panel shows `slots 2/2 cola 0` from 21:08:47Z. Both finished in about 4 minutes. The scenario passed entirely.

### c. `kill -9` in the middle of `ship`, restart without duplicates

Run `carrier-e2e-gVWkVE` (`#71 Initials nv27`, two slices, a single time; scenario passed):

```
21:39:27Z c: GitHub before kill -9: {"prs":1,"prHeads":["feat/initials-nv27/072-add-initials"],"integrationPrs":[],"epicComments":1,"prComments":0,"reviewComments":0,"reviews":0,"commits":1,"branches":[".../072-add-initials",".../epic"]}
21:39:27Z c: kill -9 carrier pid=39491; exit={"code":null,"signal":"SIGKILL"}
21:39:27Z c: agent processes left running by the dead carrier: [{"pid":44116,"command":".../claude -p You are the author of the final integration PR of epic #71 ..."}]
21:39:27Z carrier started pid=51232
21:42:05Z c: executions [{"id":"4c4b6f76","stage":"ship","status":"interrupted","session":"1a5d7943"},
                         {"id":"7919b2f4","stage":"ship","status":"finished","session":"1a5d7943"},
                         {"id":"4b420392","stage":"review","status":"finished","session":"01a146a9"}]
21:42:05Z c: GitHub after: {"prs":3,"prHeads":[".../072-add-initials",".../073-list-initials-in-the-readme",".../epic"],"integrationPrs":[76],"epicComments":1,"reviews":1,"commits":4,"commitMessages":["Merge pull request #74 ...","Merge pull request #75 ...","docs: list initials in the README","feat: add initials()"]}
```

Before: 1 PR, 1 comment, 1 commit. After: 3 PRs (2 slices + 1 integration), the same single comment, 4 unique commits (2 of content + 2 merges), 1 review. Zero duplicates by branch, by comment body and by commit message. The resumed session is the same one (`1a5d7943`). The `orchestrator.log` shows the recovery: on restart Carrier found the orphaned agent (the `claude` was still alive after the `kill -9`), stopped it (`[engine] stopping orphan execution`, +1.3 s) and only then relaunched `ship` in the same session (`recovering epic ... lastStatus interrupted`). In the end no agent process was left.

### d. `kill -9` with the JSON written and before importing; truncated JSON

First half (kill -9 between the JSON and its import), observed in all three runs. Always: JSON on disk, 0 results imported, `ship` in `running`, restart, 1 import, `ship` is not relaunched:

```
pxhvs7  21:14:45Z d: kill -9 with the JSON on disk (1176 bytes) and 0 imported results; ship execution status running
        21:14:54Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
myD0QA  21:22:21Z d: kill -9 with the JSON on disk (1144 bytes) and 0 imported results; ship execution status running
        21:22:30Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
iWapYE  21:32:42Z d: kill -9 with the JSON on disk (953 bytes) and 0 imported results; ship execution status running
        21:32:51Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
```

GitHub before the restart in `iWapYE` (`#67 Clamp eb4m`): `prs 2, epicComments 2, commits 2, reviews 0`; at the end `prs 2, epicComments 2, commits 2, reviews 1`. Nothing duplicated. The `orchestrator.log` also records `result imported ... "duplicate":false` and, when a second attempt is made, `"duplicate":true` (ignored): idempotency by `executionId` works.

Second half (truncated reviewer JSON), run `iWapYE`: the harness cut the reviewer's JSON in half 38 times while its agent ran, and what Carrier found when the agent exited was an 85-byte file:

```
21:36:25Z d: cut the review JSON 38 time(s) while its agent ran; what carrier found: 85 bytes
21:37:11Z d: ended {"status":"ready_for_test","round":1,"prNumber":70}
21:37:11Z d: executions [{"id":"07ca55e8","stage":"ship","status":"finished","session":"2a6cafb6"},
                         {"id":"a11ed2fc","stage":"review","status":"invalid_result","session":"01a146a1","error":"result is not valid JSON"},
                         {"id":"418046ea","stage":"review","status":"finished","session":"01a146a1"}]; events ["execution_retried"]
[warn] [engine] invalid caller result ... "reason":"result is not valid JSON"
```

A truncated JSON is a technical failure (`invalid_result`, without spending a round: `round` stays at 1), it is retried in the same session (`execution_retried`) and the epic reaches `ready-for-test` with 1 integration PR and 1 review on GitHub. That run failed on the scenario's last assertion because of a **harness** error, not a Carrier one: it compared the retry's session against the session read when the execution had just started (Codex had not reported it yet, `null`). It was fixed by reading it from the final row and hardened (it now requires `error = "result is not valid JSON"` and a non-null session); the run's data satisfy the corrected assertion (`01a146a1` in both executions). The fix was not run again in full because of cost.

### e. `Ctrl+C` in the middle of an execution, restart resumes the session

Run `carrier-e2e-myD0QA` (`#63 Square 0wov`, passed entirely):

```
21:24:25Z e: Ctrl+C (SIGINT) to carrier pid=31503; session 72aa086f-604f-4996-bd1f-c0d96f26aa81 ... 260368 bytes; GitHub before: {"prs":0,...,"commits":0,"branches":[]}
21:24:27Z e: carrier exit={"code":0,"signal":null}; epic running/ship; executions [{"stage":"ship","status":"interrupted"}]; agent processes left: []; others under the root: []
21:27:37Z e: ended {"status":"ready_for_test","prNumber":66}
21:27:37Z e: executions [{"id":"d868f0d6","stage":"ship","status":"interrupted","session":"72aa086f"},{"id":"4b2a42e6","stage":"ship","status":"finished","session":"72aa086f"},{"id":"84cf6d74","stage":"review","status":"finished","session":"01a1469c"}]; session file grew 260368 -> 487062 bytes
21:27:37Z e: GitHub after: {"prs":2,"integrationPrs":[66],"epicComments":1,"reviews":2,"commits":2}
```

Clean exit (code 0), epic still `running`/`ship`, execution `interrupted`, no agent process alive, the Claude session survived. The restart resumed **the same** session (`72aa086f`) and the session file grew (appended to the same history), 2 PRs (slice + integration), no duplicates. The `Ctrl+C` arrived 8 s after `ship` started, when there was still nothing on GitHub; the "no duplicates with already published work" test is the one in scenario c.

## 3. Bugs found and fixed in this slice

**1. Git used the person's credential, not the execution's token (`0039ad0`).** `gh` honors `GH_TOKEN`, but `git` over HTTPS asks the user's credential helpers (on macOS, the keychain, i.e. Diego's login). As a result every push and every branch operation by a bot would be made as the person. `childEnv` now empties the helper list and adds one that answers with the execution's token (read from the environment when git asks for it, so the token is not left in the value) via `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`, respecting any entries the environment already had. Verified on GitHub: the commits of PRs `#74`, `#75`, `#76` have author and committer `artanis-agent[bot]`, and the PRs are `app/artanis-agent`. Unit test in `src/providers/claude.test.ts`.

**2. A Codex reviewer wrote its JSON to a path with one segment missing and every retry repeated it (`4d043db`).** In run `pxhvs7` epic `#55 Clamp lnsx` ended in `needs-human` (it still is in the sandbox): the reviewer wrote the JSON to `.../T/orchestrator/results/<id>.json` instead of `.../T/carrier-e2e-pxhvs7/orchestrator/results/<id>.json` (it swallowed the root segment), Carrier did not find it (`invalid caller result ... "reason":"result file is missing"`) and the three attempts (`maxExecutionRetries: 2`) repeated the wrongly copied path, until `se agotaron los reintentos de review (3 intentos)`. It was a real bug, not a scenario failure: Carrier's behavior was correct (technical failure, retries, `needs-human`); the cause was the prompt, which gave a long path for the model to retype. Fix: the path is also in the environment variable `CARRIER_RESULT_PATH` (in Claude and in Codex) and the prompt tells it to write to `"$CARRIER_RESULT_PATH"` instead of retyping it. With the fix, the following runs (`myD0QA`, `iWapYE`, `gVWkVE`) did not repeat the failure in the normal flow. `#55` was left as it was, as evidence: it is not an open Carrier problem.

**Harness** (not Carrier bugs): the carriers of a failed scenario are killed so as not to leave the lock held for the next one (`a034932`); the reviewer's JSON is cut until its process ends and `b` waits for both agents; in `d` the harness now tolerates the agent deleting the JSON to rewrite it (before, `readFileSync` threw `ENOENT`; it is the most likely cause of `d` being cut in `myD0QA`: the Codex reviewer had deleted the file, see its `stderr.log`); the session assertion in `d` (above); and without the variables the body of the skipped `describe` still runs when collecting the tests and threw `TypeError`, so `pnpm test:integration` failed without credentials instead of skipping (it now uses an empty environment).

## 4. Open or to watch

- **Paths retyped wrongly by Codex, residual risk.** With `CARRIER_RESULT_PATH` the normal flow works, but in `iWapYE`, fighting the harness that truncated its file, the reviewer wrote twice to badly built paths (`.../T/orchestrator/results/...` and `.../gn/orchestrator/results/...`, without the root and without `T`) before getting it right. It is absorbed as a technical failure, but each retry repeats the same prompt: if the model insists, it ends in `needs-human` (the intended behavior). The design was not touched; if it shows up in real use, the retry could prepend to the prompt the path already tried that failed.
- **Cost of a reviewer that fights.** In that run the reviewer spent 3.5 M input tokens (versus 0.24 to 0.52 M normally) until its process ended. It is a harness artifact (it cuts the file 38 times), not real use.
- **`Lane 1 worktree` comments.** Some epics have two Solve comments (`Epic worktree` and `Lane 1 worktree`) with different bodies: that is what `ship` writes, not a Carrier duplicate (the checks compare bodies).
- **Orphans.** After `kill -9`, the agent stays alive until the restart stops it (≈1.3 s after starting). Anticipated by [ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md). With `Ctrl+C` nothing was left. The harness kills whatever hangs from the root anyway in case Codex orphans its command process.
- **Scenario `a` on its own.** There is no harness log for `a`; its evidence is the GitHub one (§2.a) and that of c.

## 5. Observed cost and time

- Per run: `c` 4 min 29 s, `d` 7 min, `e` ≈ 4 min, `b` ≈ 4 min per epic in parallel; `a` ≈ 4.7 min.
- `ship` with Sonnet: USD 0.38 to 0.54 per epic (the `total_cost_usd` field of Claude's stream; the highest, 2 slices). A `ship` cut with `kill -9` costs what it managed to do plus the same again when resumed. Codex does not report USD: 0.24 to 0.52 M input tokens per normal review.
- Total spent in this slice: the initial run created about 12 epics (USD 10 to 13 estimated, from the previous session); this consolidation pass added 2 more epics (`d` and `c`, estimated USD 2 to 3). Without the entire suite.

## 6. What was left in the sandbox

Everything stays as evidence, nothing deleted or closed, and no epic was left with `solve:epic:ready`:

- 14 Carrier epics (`#15`, `#21`, `#27`, `#29`, `#35`, `#41`, `#45`, `#47`, `#49`, `#55`, `#59`, `#63`, `#67`, `#71`), their slices and PRs (slices merged into the epic branch, draft integration PRs not merged), and the `feat/<feature>/epic` branches.
- `#55 Clamp lnsx` in `solve:epic:needs-human` (bug 2); `#15 Reverse r1qe` (first attempt, with its integration PR `#20` closed) and `#45 Square 40vx` (closed, one slice open) are leftovers from the first pass.
- `main` with one spec commit per epic and one `chore: point the solve worktrees at the e2e root` per run; the `path` in `docs/agents/solve.md` points at the last temporary root, already deleted: the next scenario rewrites it (`Sandbox.prepare`). To clean everything up, see "Resetting it" in [sandbox-repo.md](sandbox-repo.md).
