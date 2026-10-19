# Preparing a repo for Carrier

Carrier does not prepare epics, it runs them. A repo is ready for it when these hold.

## The repo uses Solve

Carrier runs the [Solve](https://github.com/AshuLab/skills) skills (`ship`, `code-review`, `code-post`) through the agents, so the repo needs Solve's setup (`solve:setup`): its labels and `docs/agents/solve.md`. Epics and tickets are GitHub issues created by Solve. The skills have to be available to each agent CLI you use (for Claude Code, the Solve plugin; Antigravity has its own requirement, below).

## The epic is ready

- Solve marks an epic `solve:epic:ready` when its preparation is finished. You can also add the label by hand.
- The spec, ADRs and glossary of the epic must be **on the remote** before that, because Carrier works in its own clone, maybe on another machine, and a file that only exists in your working copy never reaches it. The right place is the **epic branch** (`feat/<feature>/epic`, where `<feature>` is the slug of the epic issue's title), as its first commit: `ship` reuses that branch if it exists. Until Solve has a step that does it ([AshuLab/skills#34](https://github.com/AshuLab/skills/issues/34)), do it by hand, or merge the docs into the base branch with a small PR.
- If the author cannot find what the epic refers to, it stops the epic with `needs-human` and says what is missing. It does not search your disk.
- Slices are real sub-issues of the epic with their dependencies (`--parent`, `--blocked-by`), as Solve creates them.

## Paths match the shared root

Solve does not receive Carrier's `root`: it reads where to put worktrees from the Worktrees line of the repo's `docs/agents/solve.md` (by default `~/.solve/worktrees/<repo>/<feature>/`). With the default `root: "~/.solve"` everything matches. With another root, set that `path` to the same folder.

## Identities

- The author and the reviewer need two different identities. Bots are the clean way: create a GitHub App per bot ([how](https://github.com/AshuLab/agent-forge/blob/main/docs/github-app.md)), install it on the owner of the repo, and register it with `agent-forge add`.
- The App must be installed on the account or org that owns the repo. Forge picks the installation from the owner of the repo it is run in; Carrier does that for you.
- Your own `gh` login can be one of the two roles, never both.

## Antigravity (`agy`) as a harness

Only if you use it as the author or the reviewer. It must be installed and logged in, and the Solve skills (`ship`, `code-review`, `code-post`) must be visible to it **globally**, not through a file inside your repo: a `~/.gemini/config/skills.json` with an entry whose `path` is the Solve plugin's `skills/` folder. That setup was only tested at project level (see [the spike](research/antigravity.md)); check it with a throwaway epic first.

## Safety net

The agents run on your machine with your permissions ([ADR 0004](adr/0004-agents-run-on-host-with-terminal-preferences.md)). Turn on **branch protection** on the repos you point Carrier at: it never merges the final PR, but the agents can push branches.

## Check it

```bash
carrier doctor
```

It tells you if a tool is missing, if an identity cannot get a token for a repo, or if the repo is not reachable.
