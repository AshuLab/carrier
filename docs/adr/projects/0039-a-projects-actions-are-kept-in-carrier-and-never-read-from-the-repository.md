# 0039 - A project's actions are kept in Carrier and never read from the repository

- Status: accepted; amends [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) (the per-repo setup that it left for later)
- Date: 2026-11-21

## Context

[0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) left a per-repo hook for later, "how projects are set up", and said that a worktree that was cleaned comes back on its branch without its dependencies until something installs them.
People who start work in a new worktree, or in a fresh clone, have to install dependencies or copy a file before anything runs, and the agent has to be told or find out.

The commands run on the person's Mac with the person's credentials, so where the list comes from decides who can make Carrier run something.

## Decision

A project's actions are kept in its entry of `projects.json` ([0041](0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)), written by the person in Settings.
Carrier never reads a command from a file inside a repository, whether it is `.carrier/`, `package.json`, a git hook or anything else, so cloning or fetching a repository that is someone else's cannot make Carrier run anything.

An action has a name, a command, when it runs (in a new worktree, or after a clone), whether it is on, and what happens when it fails: warn and continue, the default, or stop the session.
The chat host runs them in order, in the folder of the new worktree or the fresh clone, as steps of the preparation ([0018](../sessions/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)): after the worktree or the checkout and before the agent starts, each one an event of the session that the conversation shows.
They run too when the folder of a cleaned worktree comes back ([0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md)).
They do not run in the engine's worktrees for an epic.

## Alternatives considered

A file in the repository that the team shares.
It is convenient and travels with the code, and it is a way for any repository to run commands on the Mac of whoever clones it.

A fixed list of presets (install dependencies, copy the environment file).
It is safe and it covers the common case, and it cannot say `cp "$CARRIER_MAIN/.env" .env` or anything a project needs that is its own.

Running them in the engine's worktrees as well.
An epic runs unattended and in a clone the person never opens; nobody has asked for it, and [0012](../sessions/0012-sessions-and-epics-are-two-separate-worlds.md) keeps the two worlds apart.

Stopping the session on any failure by default.
A flaky install would block every session; the person who wants a hard stop sets it on that action.

## Consequences

Actions do not travel with a repository: each person sets their own on their own Mac, and a teammate who clones the project starts without them.
A command is as trusted as the person who typed it, and it runs without a sandbox, with the environment the host gives its sessions.
A stopping failure blocks the start of a session, with the reason in words and Try again, as any failed step does.
Changing an action affects the next worktree, not the ones that exist.
