# Test repo `AshuLab/carrier-sandbox`

Private, disposable repo to test Carrier and the Solve skills end to end (spike #8; slice #33 reuses it to seed its own epics). Default branch `main`. Both Forge bots (`artanis-agent`, `tassadar-agent`) have access. Writes only go there: none of this touches another repo.

## What it contains

- A Node project with no dependencies: `package.json` (`"type": "module"`, `test` = `node --test`), `greet.js` + `greet.test.js`, `.gitignore` (`node_modules`), `AGENTS.md` (conventions and a `## solve skills` block) and `README.md` with a `## Functions` section (one line per function; it is the deliberate conflict point between epics).
- `docs/agents/solve.md` and `docs/agents/solve-flow.md`, written by the real `setup` skill: GitHub Issues, branch type `feat`, base and target `main`, Worktrees **on**, path `<root>/worktrees/<repo>/<feature>/` (absolute, with literal `<repo>` and `<feature>`), no bootstrap.
- Labels: `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw` (created by `setup`) and `solve:epic:ready` (by hand, `#fbca04`).
- Two example epics, with their specs in `docs/specs/farewell.md` and `docs/specs/shout.md`, committed to `main` before setting `ready`: `#1 Farewell` (slices `#3` and `#4`, `#4` blocked by `#3`) and `#2 Shout` (`#5` and `#6`, `#6` blocked by `#5`). Plus `#13`, an extra slice of `#1` to test reuse. Their PRs (merged slices, draft integration PRs `#11` and `#12`) and branches `feat/farewell/epic`, `feat/shout/epic` remain as evidence; see [shared-root.md](shared-root.md) §6.
- Commits on `main`: `89d89a4` (project + `AGENTS.md`), `2fe4983` (`setup`), `c423756` (specs).

## How it was seeded

`<root>` is a directory of your choice (the real run used a `mktemp -d` outside `~/.solve`). Node 26 and `pnpm`; `gh` logged in with write permission on the repo, no tokens in the clone.

```sh
R=AshuLab/carrier-sandbox; ROOT=$(mktemp -d)/solve-root
mkdir -p $ROOT/repos/AshuLab && cd $ROOT/repos/AshuLab && gh repo clone $R && cd carrier-sandbox

# 1. Project: package.json, greet.js, greet.test.js, AGENTS.md, .gitignore and the README's ## Functions section
#    (the files are on `main`: git show 89d89a4)
git add -A && git commit -m "chore: seed sandbox project (greet + test, AGENTS.md)" && git push origin main

# 2. Real Solve setup, no questions: the answers go in the prompt (31 s, ~USD 0.20 with Sonnet)
~/.local/bin/claude -p "/solve:setup Run non-interactively, nobody can answer questions; use exactly these answers. GitHub remote is $R. Context file: AGENTS.md (already exists). Anything particular: nothing. Worktrees: mode ON, path $ROOT/worktrees/<repo>/<feature>/ (absolute, keep <repo> and <feature> as literal tokens), bootstrap: none (no dependencies), linked config: none. Branch type: feat. Base and destination: main. Repo notes: none. I confirm the final values. Commit the files on main as 'chore: set up the solve skills' and push to origin main. Create the labels in GitHub too." \
  --model sonnet --permission-mode bypassPermissions --output-format json </dev/null

# 3. The label Solve does not create yet
gh label create solve:epic:ready --repo $R --color fbca04 --description "Epic ready for Carrier (set by hand until Solve adds it)" --force
```

For `claude`, use the real binary (`~/.local/bin/claude`), not the Superset wrapper on the `PATH`.

## Create a new test epic

The same thing `to-spec` and `to-tickets` produce, written by hand so it is deterministic:

1. Spec in `docs/specs/<feature>.md` with `Status: spec` and the sections Problem, Solution, Scope, Decisions, Out of scope. Commit and push it to `main` **before** setting `ready` (otherwise the workspace does not see it; see [shared-root.md](shared-root.md) §3).
2. Epic: `gh issue create --repo $R --title "<Feature>" --body-file <spec without H1 or Status> --label solve:epic`. The `<feature>` in the branches and the worktree comes from the title (lowercase slug).
3. Slices in topological order, each with `# NNN - title`, Goal, Context, **Definition of done** (every checkbox verifiable with `pnpm test` or by looking at a file) and Blocked by: `gh issue create --repo $R --title "<title>" --body-file <ticket> --label solve:ticket,solve:refined --parent <epic> [--blocked-by <n>]`. Wait a couple of seconds between `create` calls to avoid the rate limit.
4. Queue it in Carrier with `gh issue edit <epic> --repo $R --add-label solve:epic:ready`.
5. To test only `ship`, without Carrier, from the clone (each epic in its own process, in parallel if you want):

```sh
cd $ROOT/repos/AshuLab/carrier-sandbox && ~/.local/bin/claude -p "/solve:ship drain epic #<n> of AshuLab/carrier-sandbox (the repo in the current directory). Worktree this epic. Run unattended: nobody can answer questions, decide from the skill's own rules. Leave the integration PR as a draft and do not merge it." \
  --model sonnet --permission-mode bypassPermissions --output-format stream-json --verbose --max-budget-usd 4 </dev/null
```

An epic with 2 trivial slices takes about 3 min and costs ~USD 0.5. To make two epics collide on purpose, have both add a line to the README's `## Functions`: nothing fails while draining, the conflict shows up when integrating them.

## Resetting it

It was not run: the state of the #8 run was left as evidence. It is disposable, so it can be forced. Every step touches only this repo.

```sh
R=AshuLab/carrier-sandbox
# Open PRs and the epics' branches
gh pr list --repo $R --state open --json number --jq '.[].number' | xargs -I{} gh pr close {} --repo $R --delete-branch
git ls-remote --heads https://github.com/$R.git 'refs/heads/feat/*' | awk '{sub("refs/heads/","",$2); print $2}' | xargs -I{} git push origin --delete {}
# issues: delete them (needs admin) or close them
gh issue list --repo $R --state all --limit 200 --json number --jq '.[].number' | xargs -I{} gh issue delete {} --repo $R --yes
# main goes back to the seed + setup (no specs)
git fetch origin && git push --force origin 2fe4983:main
```

Afterwards, in a new clone: **edit the `path` line of `## Worktrees` in `docs/agents/solve.md`** so it points at the new `<root>` (`sed -i '' "s#^- \*\*path\*\* - .*#- **path** - \`$ROOT/worktrees/<repo>/<feature>/\`#" docs/agents/solve.md`), commit and push to `main` (`ship` cuts the epics from `origin/main`), and continue with [Create a new test epic](#create-a-new-test-epic). The path is absolute and lives in the versioned `solve.md`, so a different `<root>` needs that commit; a deleted temp directory leaves a dead path, not an error: `ship` simply creates the worktree there.
