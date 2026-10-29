# 0014 - A session worktree lives in Carrier's home and dies with its session

- Status: accepted
- Date: 2026-10-28

## Context

A user session can work in a new git worktree instead of the person's own folder, so that an agent can edit freely while the base folder keeps its branch and its uncommitted changes. That makes Carrier create folders full of the person's work, and three things about them are hard to change once people rely on them: where they are, what they are called, and when they go.

The engine already has worktrees of its own for epics, under `root` today and in `<folder>/engine/worktrees` once the engine moves into the Carrier folder ([0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)), and the chat host refuses any folder inside the engine's folder. The Carrier folder (`CARRIER_HOME`, `~/.carrier` by default, [0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) holds a folder for the chat beside the engine's, and the chat's worktrees live there.

## Decision

A session worktree is created under `<folder>/chat/worktrees/<owner>/<repo>/<name>`, where `<folder>` is the Carrier folder and `<owner>/<repo>` come from the base folder's `origin` remote and a folder with no GitHub remote goes under `local/<folder name>`. Its branch is `carrier/<name>`, where `<name>` is generated as `<adjective>-<unit>-<place>` from lists of StarCraft words (never a character's full name), unless the person types another after the fixed `carrier/` prefix; a name taken by a local branch, a remote branch or a folder is rolled again, never numbered. The branch is cut from the branch the person picks, which defaults to the one checked out in the base folder when the workspace is chosen.

Carrier never changes the base folder: it does not switch its branch, stash or commit in it.

The worktree is removed, with its branch, when the session is deleted, and not before: archiving keeps it. Before deleting, the host can say what would be lost (uncommitted changes, and commits on the branch that exist nowhere else), and the app shows that in its confirmation. A worktree that cannot be removed stops the deletion with a reason, and Carrier only ever removes folders it recorded for a session and that lie under that location.

## Alternatives considered

Inside the repository (a `.worktrees` folder). It keeps the work next to the code, but it adds a folder to every repository and a line to every `.gitignore`, and an agent can walk into it from the base folder.

Beside the repository. No new location to learn, but it clutters the folder the person keeps their projects in and fails when that folder is read-only or synced.

Under the engine's folder with the epics' worktrees. One place for every worktree, but the chat host refuses that folder by design, and a session's work would sit among the unattended runs.

Keeping the worktree after the session is deleted. It loses nothing, but disk and branches pile up with no owner, and the person has to clean them by hand.

## Consequences

Deleting a session can discard work that was never pushed; the confirmation has to say so, and "Clear sessions" in the archive says it for all of them at once. A person who wants to keep the work pushes the branch or does not delete the session.

Disk use grows with the sessions in worktrees until they are deleted, in a place the person can see and clean (`git branch --list 'carrier/*'` finds every branch, and the folder is under their own home).

The prefix `carrier/` makes Carrier's branches easy to find, hide or delete in a repository's own tools, and means a branch of that name that Carrier did not create is never touched, because only recorded worktrees are removed.

Creating and removing worktrees needs `git` on the machine; a folder that is not a git repository is refused with a reason in words; it is never opened as a session in a worktree instead.
