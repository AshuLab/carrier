# 0036 - A new worktree is cut from the remote branch by default, and choosing a project fetches it

- Status: accepted; amends [0014](0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md) (the branch a session worktree is cut from)
- Date: 2026-11-19

## Context

A session worktree is cut from "a branch the person picks", and the branch offered first is the local one.
Carrier's fetch moves `origin/*` and never the person's local branch, so a worktree can start many commits behind `origin/<branch>` even right after a fetch.
The agent then works on code that is out of date, and the sidebar, which counts a session's lines from the merge-base with the local branch, shows everything that landed since as the session's own work.
Choosing a folder in the new-session screen was read-only until now, and the host never fetched a folder that is not a project it cloned.

## Decision

A new worktree is cut from `origin/<branch>` unless the person chooses the local branch.
Where it starts is `worktreeStart` in `chat.json` (`remote` or `local`, `remote` by default), because the chat host does the fetch and the cut and cannot read the app's preferences; the host reads it fresh at each preparation, as it reads the session ages.
A session's own choice, the Remote or Local tab of the branch picker, is sent as an optional `startFrom` on the worktree request and never written to the setting.

When a project that is a git repository with an `origin` is chosen, the host fetches `origin` in the background (`git fetch origin --prune`, no credential prompt, bounded in time) unless the last fetch is recent.
That is the one case where choosing a folder writes to it: `FETCH_HEAD` and the `origin/*` refs, never a branch, the index or the working tree.
Sending checks the same freshness and fetches first when it is older, as one more step of the plan.

When the fetch fails or `origin/<branch>` does not exist, the worktree is cut from the local branch, the send goes ahead, and the session carries a notice that says so.
The host never refuses to start a session in a folder because it could not reach the remote; the fetch or clone step of a GitHub project is as it was and still fails the session.

## Alternatives considered

Keeping the local branch as the default and warning when it is behind.
The warning is read after the worktree exists, and the drift comes back with every `main` that was not pulled.

Remote with no way to choose local.
A person whose `main` holds commits not pushed yet could not start from them without naming a branch by hand, so the picker keeps a Local tab and says how many commits are not pushed.

The setting in the app's preferences, as "Work in" is.
The host, which does the fetch and the cut, cannot read them, so a plan that does not say where to start would have no default.

Fetching only the chosen branch.
It would be a second fetch mechanism next to the `git fetch origin --prune` that "Update the repository" and "Fetch now" already run, for the sake of fetching less; the one that exists has its timeout and its credential handling.

Fetching only when the message is sent.
The picker would then show branches and "behind" counts that are days old at the moment the person chooses, which is when they need them.

Refusing to send when the fetch fails.
It would stop a person without network from working at all, for a condition the notice already explains.

## Consequences

A new worktree is current with the remote by default, the sidebar's count of a new session starts at zero, and the picker can say how far behind or ahead a local branch is.

Commits on a local branch that are not pushed are not in a new worktree unless the person picks Local, and the picker says how many there are so the omission is visible.

Choosing a project touches the network and writes refs in the person's repository without being asked, and on a large repository or a slow remote it costs time and bandwidth for a session the person may never start; it is skipped while the last fetch is recent, and the window is measured before it is fixed.

A session already cut from a stale branch is not moved; only its sidebar count changes, through the merge-base with the most recent of the local and the remote copy.
