# Shared root with Solve (spike #8)

Date: 2026-10-15 (§1 to §5) and 2026-10-16 (§6). Environment: macOS, git 2.54.0 (Apple Git-157), gh 2.102.0, Node 26.12.0, pnpm 12.11.2, Claude Code 2.1.301, `solve` plugin 0.24.0 (the most recent in `~/.claude-ashu-lab/plugins/cache/ashulab/solve/`). §1 to §5 ran in disposable repos inside `mktemp -d` with a local bare remote (no GitHub); §6 ran against the disposable GitHub repo `AshuLab/carrier-sandbox` (see [sandbox-repo.md](sandbox-repo.md)). The temporary directories were deleted at the end.

Result: all six criteria have evidence. Criterion 2 (two epics drained by `ship` from a clone in `<root>/repos/<org>/<repo>/`) was closed on 2026-10-16 with real `ship` runs (§6) and **confirms what was read from the sources**; only one detail of the lane order changes (see §6). The spec was updated in this same PR.

## 1. How the root is communicated to Solve

**It is not communicated: Solve has no concept of a root.** Its real sources were read (`skills/ship/SKILL.md`, `skills/ship/WORKTREES.md`, `skills/setup/SKILL.md`, `skills/setup/REFERENCE.md`, `skills/land/SKILL.md`, `skills/ship/scripts/solve-next-startable`, `README.md`):

- `grep -rnE "process\.env|SOLVE_|getenv|environment variable|\$HOME|XDG"` over the whole plugin, not counting `code-*`: **zero results**. There is no environment variable, flag or configuration key for a root.
- The only thing that decides where a worktree goes is the **Worktrees → path** line of `docs/agents/solve.md` in *each repo* (written by `setup`, versioned with the repo), with the tokens `<repo>` and `<feature>` that `ship` fills in on each run. Without the file or without a path: `~/.solve/worktrees/<repo>/<feature>/` (`WORKTREES.md`: "From **Worktrees** in `docs/agents/solve.md` - default `~/.solve/worktrees/<repo>/<feature>/`"). This repo has exactly that value (`docs/agents/solve.md`, Worktrees section, mode off).
- `<repo>` is "the repository directory's name", that is, the name of the clone folder where `ship` runs. Solve **does not create, find or manage clones**: it works in the tree where it is invoked (the "shared tree"). `~/.solve/repos/` and `~/.solve/orchestrator/` do not exist in Solve; they are a Carrier convention. Today `~/.solve/` has `worktrees/` and `local-marketplace/` (the latter is not used by `ship`).
- The `ship` invocation can only ask to **isolate the epic** ("worktree this epic"); that is honored in any mode, but the path still comes from `solve.md`. The path cannot be passed per run.

Consequences for Carrier:

1. **The worktree root is the one in each repo's `solve.md`, not Carrier's.** With the default root (`~/.solve/`) everything matches without configuring anything. With another root, Carrier cannot push it to Solve per run: the `path` would have to be changed in the `solve.md` of every configured repo (versioned config, valid for all machines and people). That is why Carrier must not **assume** the workspace path: it derives it, verifies it with `git worktree list` and stores the real one in SQLite.
2. **With Worktrees `off` (like this repo) `ship` works in the clone itself** and only isolates the epic if asked. Two epics from the same managed clone would collide in the pre-flight (a dirty `git status` caused by the other epic stops the run). The `ship` task must always ask for "worktree this epic", or the repo must have Worktrees `on`. The orchestrator must not depend on what `solve.md` says.
3. **Collision between organizations.** The worktree is `worktrees/<repo>/<feature>/`, without the organization. `AshuLab/demo` and `other/demo` with the same `<feature>` point to the same path (see §4). Carrier's configuration must reject two repos with the same folder name, or let the second one wait.
4. **The lanes** (up to 3 slices in parallel) are `<root>/worktrees/<repo>/<feature>--lane-<N>/`, siblings of the epic worktree, and always so, whether Worktrees is `on` or `off`. Real example from this same `ship` run on this machine (`git worktree list` from this repo's clone):

```
/Users/vemec/DG-Projects/AshuLab/carrier                                              f254c27 [feat/carrier-orquestador-de-epicas-autonomas/epic]
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-1 f254c27 [feat/carrier-orquestador-de-epicas-autonomas/008-spike-shared-root]
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-2 f254c27 (detached HEAD)
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-3 476380e [feat/carrier-orquestador-de-epicas-autonomas/032-codex-runner]
```

   The epic stayed in the shared tree (mode off, without asking for isolation) and the lanes under `~/.solve/worktrees/carrier/`. It is real evidence of Solve paths, but it is **not** the case for criterion 2 (there is no clone under `repos/` and no two epics).
5. **Reuse:** `ship` derives the path, looks at `git worktree list` and if it is already "it's yours"; it reuses it without recreating it, and `<feature>` is read from the epic branch, never recomputed. `ship` also comments on the epic issue with the path, machine and branch of each worktree it creates. `land` only deletes what `git worktree list` shows (a path from another machine is reported and not touched) and runs from the main tree.

## 2. Reviewer checkout path

**`<root>/reviews/<repo>/<feature>/`**, a `git worktree add --detach <path> <SHA>` from the same managed clone.

- **Outside `worktrees/`**: Solve only writes `<feature>` and `<feature>--lane-N` there. A name like `<feature>--review` inside `worktrees/<repo>/` could overwrite an epic with the same name; `reviews/` is never Solve's, so no collision is possible.
- **Separated by `<repo>/<feature>`**, like the author, so two epics can be reviewed at the same time. Same repo-name limit as in §1.
- **Detached at the reviewed SHA**, not on the epic branch: git does not allow checking out a branch already checked out in another worktree, and the author has it.
- **Not nested** in the author's worktree: it would be untracked content in its `git status`, exactly what `ship`'s dirty-tree checks would treat as someone else's work.
- **Each round reuses the same path**: `git fetch` and `git switch --detach <new SHA>`.
- It is removed with `git worktree remove` when the epic finishes. Since it shares `.git` with the clone it appears in `git worktree list`; `land` acts on what that command lists, so it could remove it if it is clean: harmless, the epic is already finished.

Demonstration (disposable repo `demo`, clone in `<root>/repos/AshuLab/demo`, local bare remote, two epics `alpha` and `beta` with one lane each; `<root>` is the `mktemp -d`):

```
$ git worktree list    # before the reviewer
<root>/repos/AshuLab/demo           303ec11 [main]
<root>/worktrees/demo/alpha         303ec11 [feat/alpha/epic]
<root>/worktrees/demo/alpha--lane-1 303ec11 [feat/alpha/001-x]
<root>/worktrees/demo/beta          303ec11 [feat/beta/epic]
<root>/worktrees/demo/beta--lane-1  303ec11 [feat/beta/001-x]

$ git worktree add <root>/reviews/demo/alpha feat/alpha/epic     # the naive checkout
fatal: 'feat/alpha/epic' is already used by worktree at '<root>/worktrees/demo/alpha'

$ git worktree add --detach <root>/reviews/demo/alpha <SHA>      # the proposed one
<root>/reviews/demo/alpha           303ec11 (detached HEAD)
$ git -C <root>/worktrees/demo/alpha status --porcelain          # author: clean (empty output)

$ git worktree add --detach <root>/worktrees/demo/beta/review <SHA>   # contrast: nested
$ git -C <root>/worktrees/demo/beta status --porcelain
?? review/

# round 2: the author commits and pushes; the reviewer repoints the SAME path
$ git -C <root>/reviews/demo/alpha fetch && git -C <root>/reviews/demo/alpha switch --detach <new SHA>
reviewer HEAD == author HEAD: yes
```

Path check: the reviewer's is neither equal to, nor a prefix of, nor a descendant of any of `worktrees/demo/alpha`, `alpha--lane-1`, `beta`, `beta--lane-1` or the clone (`ok` for all five).

## 3. Spec and tickets prepared before `ready`

What each thing is, according to `to-spec`, `to-tickets` and `ship`:

- **Epic (the PRD) and tickets** are GitHub issues (the epic with `solve:epic`, each slice a sub-issue with `solve:ticket`). They do not depend on any path: the caller reads them with `gh` from any clone or worktree (`gh issue view <n>`, `gh issue list --label solve:refined` with the epic filter).
- **The brief/spec as a file** (`docs/specs/<feature>.md`), the ADRs (`docs/adr/`) and the glossary edit (`docs/glossary.md`) are the "hand-off artifacts" of `sharpen`, `to-spec` and `vocab`: files that are **untracked in the tree where they were written** (Diego's). `ship` only sees them and commits them to the epic branch if it runs in that same tree (`SKILL.md`, *Pick the tree* and *Clean the tree, cut the epic branch*).

A managed clone under `<root>/repos/` **does not have those files** if nobody commits and pushes them before `ready`. Demonstration:

```
# author's checkout, untracked files
$ git -C author/demo status --porcelain
?? docs/

# new managed clone and epic worktree: docs/ does not exist
ls: <root>/repos/AshuLab/demo/docs: No such file or directory
ls: <root>/worktrees/demo/gamma/docs: No such file or directory

# the author commits them to the epic branch and pushes; the worktree updates it
$ ls <root>/worktrees/demo/gamma/docs/specs/ <root>/worktrees/demo/gamma/docs/adr/
0001-x.md     gamma.md

# a loose file in the clone does NOT carry over to a new worktree (it is cut from what is committed)
$ ls <root>/worktrees/demo/delta
README.md
```

Paths used: `<root>/worktrees/<repo>/<feature>/docs/specs/<feature>.md` (and `docs/adr/`, `docs/glossary.md`). The real evidence: this project's spec is read at `/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-1/docs/specs/autonomous-orchestrator.md`, a worktree under the root, because it is committed on the branch.

New condition: **before setting `solve:epic:ready`, the spec, ADRs and glossary must be committed and pushed** (to the epic branch or to the base). Otherwise the author runs without them, and so does the reviewer. The caller's task must also carry the epic number so the PRD and tickets are read through `gh`, which is the source that does not depend on paths.

## 4. Same repo name in two organizations

With clones `repos/AshuLab/demo` and `repos/other/demo`, both derive `worktrees/demo/<feature>/`:

```
$ git -C <root>/repos/other/demo worktree add -b feat/alpha/epic <root>/worktrees/demo/alpha origin/main
fatal: '<root>/worktrees/demo/alpha' already exists
```

Git does not overwrite the other folder, but the second repo's `ship` run ends "without a workspace". See consequence 3 of §1.

## 5. A resumed session keeps operating on the same paths

What the [headless spike (#5)](headless-agents.md) already established: `claude --resume <id>` finds the session regardless of the cwd; `codex exec resume` takes the process's cwd. What was missing was which cwd a resumed agent really uses. Test with Claude 2.1.301 (haiku), disposable repo with the worktree `<root>/worktrees/demo/alpha`:

```
== run 1: cwd = el worktree, "recuerda KIWI-7 y corre pwd"
{"session_id":"733e9909-afeb-4f6b-9ca9-ef92f505423c","result":"KIWI-7 <root>/worktrees/demo/alpha"}
== run 2: proceso nuevo (como tras reiniciar carrier), mismo cwd, --resume
{"session_id":"733e9909-...","result":"KIWI-7 <root>/worktrees/demo/alpha"}
== run 3: proceso nuevo, OTRO cwd (<root>/elsewhere), --resume
{"session_id":"733e9909-...","result":"KIWI-7 <root>/elsewhere"}
```

- Resuming remembers the context and keeps the `session_id` in all three cases.
- **The resumed agent's Bash runs in the new process's cwd, not the original one** (run 3). The session does not "remember" the workspace.
- The session file stays in the original cwd's folder: `$CLAUDE_CONFIG_DIR/projects/<cwd with / and . as ->/<id>.jsonl`; run 3 did not create another.

Therefore a resumed session operates on the same paths **if and only if Carrier launches it with the epic's saved `cwd`**. Condition for the runner: persist in SQLite the real workspace path (and the reviewer's) together with the session id, and use that `cwd` on every `--resume` (and every `codex exec resume`). This matches the condition in the [containers research](agent-containers.md) ("if the `cwd` does not change"). On Solve's side, a restart changes nothing: `ship` rederives the path and reuses the worktree if it is already in `git worktree list` (§1.5).

## 6. Two epics drained by `ship` from a managed clone (criterion 2)

Real run of 2026-10-16 against `AshuLab/carrier-sandbox` (private, disposable; how it was seeded and reset is in [sandbox-repo.md](sandbox-repo.md)). `<root>` is `/var/folders/k_/fjsrsfrd2wg690wbghkg77c80000gn/T/tmp.uVIZdTien0/solve-root` (a `mktemp -d` outside `~/.solve`, so as not to touch real work).

**Setup.** Clone in `<root>/repos/AshuLab/carrier-sandbox` (`gh repo clone`, https remote without a token in `.git/config`). The sandbox's `docs/agents/solve.md` was written by the real `setup` skill (`claude -p "/solve:setup ..." --model sonnet`, with the answers in the prompt): Worktrees **on**, path `<root>/worktrees/<repo>/<feature>/` (absolute, with literal `<repo>` and `<feature>`), base and target `main`, branch type `feat`. Two epics shaped like `to-spec`/`to-tickets` output (`#1 Farewell` and `#2 Shout`, label `solve:epic`, `solve:epic:ready` by hand; each with 2 slices `solve:ticket,solve:refined`, sub-issues of their epic, the second `blocked-by` the first and each with a Definition of done). Their specs (`docs/specs/farewell.md`, `docs/specs/shout.md`) were committed and pushed to `main` before setting `ready`.

**Command** (two processes at once, same clone as cwd, stdin closed, real binary `~/.local/bin/claude`, not the Superset wrapper):

```sh
cd <root>/repos/AshuLab/carrier-sandbox && ~/.local/bin/claude -p "/solve:ship drain epic #<n> of AshuLab/carrier-sandbox (the repo in the current directory). Worktree this epic. Run unattended: nobody can answer questions, decide from the skill's own rules. Leave the integration PR as a draft and do not merge it." \
  --model sonnet --permission-mode bypassPermissions --output-format stream-json --verbose --max-budget-usd 4 </dev/null
```

Identity: the `gh` login (`vemec`), without Forge, as the spike asked.

**Result** (both exited with `exit=0`, `ship` `outcome`: epic drained, draft integration PR):

| | `#1 Farewell` | `#2 Shout` |
|---|---|---|
| Duration | 186 s | 169 s |
| Cost (Sonnet 5.5) | USD 0.51 (18 turns) | USD 0.50 (19 turns) |
| Epic worktree | `<root>/worktrees/carrier-sandbox/farewell` | `<root>/worktrees/carrier-sandbox/shout` |
| Lane | `<root>/worktrees/carrier-sandbox/farewell--lane-1` | `<root>/worktrees/carrier-sandbox/shout--lane-1` |
| Slice PRs (merged with a merge commit) | #8 (slice #3), #10 (slice #4) | #7 (slice #5), #9 (slice #6) |
| Integration PR (draft, **not merged**) | #12 `feat/farewell/epic` -> `main` | #11 `feat/shout/epic` -> `main` |

The `<repo>` in the path is `carrier-sandbox`, the clone folder's name, without the organization (§1.3 and §4). `<feature>` is the slug of the epic title and was read from the branch `feat/<feature>/epic`. Timings: the epic worktrees appeared ~38 s after start, the slice PRs between 1 min 10 s and 2 min 20 s and the integration PRs at ~2 min 50 s and ~3 min 5 s.

`git worktree list` of the clone at the end (long paths abbreviated with `<root>`):

```
<root>/repos/AshuLab/carrier-sandbox                          c423756 [main]
<root>/worktrees/carrier-sandbox/farewell                     4c5302c [feat/farewell/epic]
<root>/worktrees/carrier-sandbox/farewell--lane-1             4c5302c (detached HEAD)
<root>/worktrees/carrier-sandbox/shout                        1acb19f [feat/shout/epic]
<root>/worktrees/carrier-sandbox/shout--lane-1                1acb19f (detached HEAD)
```

While they ran (at 45 s) each lane was on its slice branch (`feat/farewell/003-add-farewell`, `feat/shout/005-add-shout`): when finished, `ship` **detached** them (*Freeing a lane*) and deleted the slice branches, so the lane ends up "parked" at the epic's SHA. The managed clone did not move: it is still on `main`, at `c423756`, with a clean tree, and never pulled.

**Comments that `ship` leaves on each epic's issue**, one per worktree, with machine, absolute path, branch and base (epic #1; #2 is the same with `shout`):

```
**Epic worktree**
- Machine: vemec@mac-studio.lan (Darwin arm64)
- Path: <root>/worktrees/carrier-sandbox/farewell
- Branch: feat/farewell/epic
- Base: main

**Lane 1 worktree**
- Machine: vemec@mac-studio.lan (Darwin arm64)
- Path: <root>/worktrees/carrier-sandbox/farewell--lane-1
- Epic branch: feat/farewell/epic
- First slice: #3 (feat/farewell/003-add-farewell)
```

Both integration PRs name the two paths and the `git worktree remove <path>` for each in the body (`Closes #<epic>`, slices, verification, worktrees). `ship` does not close the epic (they remain `OPEN`) nor delete worktrees.

**What a real run confirmed from §1 and §3:**

- **Two drains at once from the same clone do not collide.** Each cut its epic and slice branches in its own namespace and neither pushed `main`. Each `ship` report says it saw the other's drain and did not touch it.
- **Isolating the epic works with the path from `solve.md`**, and the lanes are siblings `<feature>--lane-1` (§1.4). With Worktrees **on**, `ship` creates the worktree by itself; **off + "worktree this epic" was not tested** (consequence 2 of §1 still has no direct observation; the prompt asked for isolation in both cases).
- **The committed spec reaches the workspace**: `<root>/worktrees/carrier-sandbox/farewell/docs/specs/farewell.md` (and `shout.md`) exist in the epic worktree and in each lane, because they were on `main` before `ready` (§3). The epic and tickets were read through `gh` from those same trees.
- **Reuse after relaunching (§1.5).** Slice `#13` was added to the already drained epic `#1` (with the `ready` label set) and the same command was launched again: `ship` reused the epic worktree and the parked lane without creating anything (identical `git worktree list`, same two paths; there were **no** new comments on the issue), built the slice in the lane, merged PR #14 and **updated the body of the existing integration PR #12** instead of opening another. 104 s, USD 0.24.
- **The README conflict is an integration one, not a drain one.** Both integration PRs show `MERGEABLE` / `CLEAN` against `main`, but `git merge-tree --write-tree --name-only origin/feat/farewell/epic origin/feat/shout/epic` exits with code 1: `CONFLICT (content): Merge conflict in README.md`. Whichever is merged second collides; it is `ship`'s own warning ("the conflict is `land`'s to surface"). Carrier must treat it as an integration blocker, not as a drain failure.

**New things for the runner:**

- Running `pnpm test` in each worktree leaves an untracked `pnpm-lock.yaml` (and `node_modules`, ignored). `ship` deleted the lock without committing it; a reviewer or a Carrier "clean tree" check that runs afterwards must tolerate it or the repo must ignore it.
- The worktree path lives in the repo's **versioned** `solve.md`, and in the sandbox it ended up absolute and pointing at a temp directory. Deleting the temp directory leaves a `solve.md` with a dead path; the next seeding rewrites it (see [sandbox-repo.md](sandbox-repo.md)). It is consequence 1 of §1 in practice: a root other than `~/.solve/` forces editing and pushing each repo's `solve.md`.
- Order of magnitude per epic of 2 trivial slices: ~3 min and ~USD 0.5 with Sonnet; the real setup cost USD 0.20 and 31 s. Spike total: ~USD 1.45.

## What was not observed

- Worktrees `off` with "worktree this epic" (the sandbox was configured `on`; reading `SKILL.md` says it is honored in any mode, but it was not run).
- Codex: the resumed session's cwd was taken from what was observed in #5 (`exec resume` uses the process's cwd); the run 3 test was not repeated.
- A repo with `docs/agents/solve.md` without `<repo>` in the path (the collision `WORKTREES.md` warns about) was not tested.

## Effect on the spec

The spec was updated in this PR: the *Shared root* section says that Solve does not receive the root and what Carrier does about it, defines `reviews/`, and sets the new conditions (prepare and push before `ready`, ask for isolation, saved `cwd`, unique repo names). The open question gets a partial result.
