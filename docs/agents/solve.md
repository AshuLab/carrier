# solve skills - operations

The commands the solve skills run in this repo: tracker, branching, worktrees.
The flow and who does what are in `solve-flow.md`.

## Tracker
Epics and tickets are GitHub Issues in `AshuLab/carrier`, via the `gh` CLI. Labels: `solve:epic` (PRD) | `solve:ticket` (slice) | `solve:refined` (fully defined, agent-ready) | `solve:raw` (found along the way, not yet sharpened). `refined` means the ticket's definition is complete, not that it's unblocked - blocking is tracked separately via `blocked-by` edges. List them: `gh issue list --label solve:refined`.

### Tracker operations
- publish a slice -> `gh issue create --title "<title>" --body-file <ticket> --label solve:ticket,solve:refined --parent <epic> --blocked-by <n,n> --milestone <epic's, if any>`
  - `--parent` is the sub-issue link, `--blocked-by` the real dependency
- file a raw issue (found along the way, not yet sharpened) -> `gh issue create --title "$(cat "<dir>/title")" --body-file "<dir>/body" --label solve:raw`
  - `<dir>` is the run's scratch dir (`mktemp -d`, owned by the skill). Write `title` and `body` into it with a file-write tool, never through the shell - no `echo`, `printf` or heredoc: a line equal to a heredoc's delimiter ends it and the rest runs - and reuse its literal path, quoted, in every call (shell variables don't persist between calls). `gh` reads the text from the files, so it's never typed into the command
  - if it fails because `solve:raw` doesn't exist (the repo never ran `setup`): `gh label create solve:raw --color d4c5f9 --description "Found along the way, not yet sharpened"` (no `--force`), then retry
- find a similar issue -> `gh issue list --state all --search "$(cat "<dir>/query")"` - `query` is 2-3 plain keywords written the same way, no `key:value` qualifiers like `is:` or `repo:`
- comment on an existing issue -> `gh issue comment <n> --body-file "<dir>/body"` - `<n>` digits only, from the match you were shown; `body` is written the same way
- claim -> `gh issue edit <n> --add-assignee @me` (leave `solve:refined` as is)
- close the loop -> `gh pr create` with `Closes #<n>`; merging the slice + closing the issue is under **Branching** (the merge into the epic branch won't auto-close it)
- find a slice's epic -> `gh issue view <n> --json parent --jq .parent.number` (and `.parent.title` for the `<feature>` token)
- find the next startable slice of epic `<epic>` -> the lowest-numbered open `solve:refined` slice of that epic that's unassigned and has no OPEN blocker:
  ```
  gh issue list --label solve:refined --state open --limit 500 \
    --json number,assignees,blockedBy,parent \
    --jq "[.[] | select(.parent?.number == <epic>)
           | select((.assignees | length) == 0)
           | select(([(.blockedBy.nodes // [])[] | select(.state == \"OPEN\")] | length) == 0)]
          | sort_by(.number) | .[0].number // empty"
  ```
  Scoping to the epic isn't optional: unscoped, this spans every epic in the repo and a drain starts shipping another epic's slices into this one's branch. `--limit` matters for the same reason - the label query is server-side and defaults to 30, the epic filter runs after it.

## Branching
Merge-only - never squash or rebase; every slice's commits and PR stay in history.
The branch type is `feat`. Each feature gets its own namespace under it: the epic and its slices are siblings inside `feat/<feature>/`, so no branch is one the others nest under (git forbids a branch `x` and one under `x/`).
- **base branch** (`main`) - the epic branch is cut from here
- **epic branch** (`feat/<feature>/epic`) - one per feature; every slice integrates here
- **slice branch** (`feat/<feature>/<NNN-slug>`) - a sibling of the epic in the same namespace (`<NNN>` the ticket number, `<slug>` from its title)
- **destination** (`main`) - where the epic branch merges when done

### Branching operations
- start the epic branch (lazy, first slice of the epic only) -> `git fetch && git switch -c feat/<feature>/epic origin/main && git push -u origin feat/<feature>/epic`
- branch a slice, **hub** (no open blocker, or several) -> `git switch feat/<feature>/epic && git pull && git switch -c feat/<feature>/<NNN-slug> && git push -u origin feat/<feature>/<NNN-slug>` - the `git pull` isn't optional: slices merge server-side, so without it you cut from an epic branch missing every slice merged so far
- branch a slice, **stack** (exactly one open blocker) -> `git switch <blocker-branch> && git pull && git switch -c feat/<feature>/<NNN-slug> && git push -u origin feat/<feature>/<NNN-slug>` - its PR targets `<blocker-branch>`
- open a slice PR -> `gh pr create --base feat/<feature>/epic --head feat/<feature>/<NNN-slug>` with `Closes #<n>`; a stacked slice targets `<blocker-branch>` instead
- merge a slice -> `gh pr merge <pr> --merge` (merge commit; never `--squash` / `--rebase`), then `gh issue close <issue>` - the merge is into the epic branch, not default, so it won't auto-close
- retarget on a blocker's close -> list them with `gh pr list --base <blocker-branch> --json number --jq '.[].number'`, then for each: `gh pr edit <pr> --base feat/<feature>/epic`
- delete a merged slice branch (**after** the retarget, never with `gh pr merge --delete-branch` - that fires on merge, before the retarget runs) -> confirm the merge landed first, remote ref against remote ref: `git fetch && git merge-base --is-ancestor origin/feat/<feature>/<NNN-slug> origin/<the base it was merged into>` must succeed. That base is the epic branch for a hub slice, the blocker's branch for a stacked one - and both sides remote, because `gh pr merge` merges server-side and your local copy of the base doesn't have it yet. Then `git branch -d feat/<feature>/<NNN-slug>` + `git push origin --delete feat/<feature>/<NNN-slug>`. Don't rely on `-d` alone as the check: once the branch has an upstream, `-d` compares against that upstream rather than the base and will delete a branch whose merge never landed, warning but exiting 0
- integration PR (all slices closed) -> `gh pr create --base main --head feat/<feature>/epic --draft` with `Closes #<epic>` in the body - for a human; ship never merges it (the human's merge closes the epic only if `main` is the default branch)
- land the epic (a human accepted the integration PR) -> `gh pr ready <pr>`, then `gh pr merge <pr> --merge`, then clean up in this order: `git worktree remove <path>` (it holds the epic branch, so it goes first), delete `feat/<feature>/epic`, delete any leftover slice branch under `feat/<feature>/*`, close `#<epic>` if the merge didn't. Every delete after `git fetch origin` + `git merge-base --is-ancestor origin/<branch> origin/main` - run the `land` skill rather than these by hand

## Worktrees
**off** - `ship` works in the shared working tree by default. An explicit per-run request ("worktree this epic"), or the pre-flight halt's `worktree` exit, still isolates a single epic at the path below.
- **path** - `~/.solve/worktrees/<repo>/<feature>/`
- **linked config** - none
- **cleanup** - `ship` names the path and the `git worktree remove` in the integration PR body; `land` removes it when it merges that PR
