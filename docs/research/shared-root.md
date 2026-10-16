# Shared root with Solve (spike #8)

Date: 2026-10-15. Environment: macOS, git 2.54.0 (Apple Git-157), gh 2.102.0, Node 26.12.0, pnpm 12.11.2, Claude Code 2.1.301, `solve` plugin 0.24.0 (the most recent in `~/.claude-ashu-lab/plugins/cache/ashulab/solve/`). Everything ran in disposable repos inside `mktemp -d` with a local bare remote (no GitHub). The temporary directories were deleted at the end.

Result: criteria 1 and 3 to 6 have evidence. Criterion 2 (two epics drained by `ship` from a clone in `<root>/repos/<org>/<repo>/`) was read from the sources but not run here. The spec was updated in this same PR.

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

## What was not observed

- Worktrees `off` with "worktree this epic" (the test repo was configured `on`; reading `SKILL.md` says it is honored in any mode, but it was not run).
- Codex: the resumed session's cwd was taken from what was observed in #5 (`exec resume` uses the process's cwd); the run 3 test was not repeated.
- A repo with `docs/agents/solve.md` without `<repo>` in the path (the collision `WORKTREES.md` warns about) was not tested.

## Effect on the spec

The spec was updated in this PR: the *Shared root* section says that Solve does not receive the root and what Carrier does about it, defines `reviews/`, and sets the new conditions (prepare and push before `ready`, ask for isolation, saved `cwd`, unique repo names). The open question gets a partial result.
