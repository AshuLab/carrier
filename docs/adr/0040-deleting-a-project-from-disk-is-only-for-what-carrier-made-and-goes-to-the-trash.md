# 0040 - Deleting a project from disk is only for what Carrier made, goes to the Trash and stops at unsaved work

- Status: accepted; amends [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) (Carrier never deletes from the projects folder)
- Date: 2026-11-21

## Context

[0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) says that the projects folder is the person's and that Carrier fetches in it and never deletes anything from it, and [0019](0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md) and [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) keep every automatic cleanup away from unsaved work.
Agents now clone and make worktrees that take gigabytes, and the person wants to remove a project from Carrier and, if they choose, take its files off the Mac in the same step instead of going to Finder.
A folder the person added by hand was never Carrier's.

## Decision

Removing a project asks one thing: remove it only from Carrier, where the entry goes and the files and the worktrees stay, or also delete it from disk.
Deleting from disk is offered only for a project whose `origin` is `cloned` or `created` ([0038](0038-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)), a folder Carrier made. A project added by hand offers only Remove from Carrier.
Deleting moves the project's folder and its session worktrees to the Trash and never removes them outright.
It stops, saying why, when the folder or any of its worktrees has uncommitted changes or branches that are not pushed, and goes on only if the person confirms after seeing which.
It does not go ahead at all while a session of the project is working, waiting or open, as [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) never touches one; the other sessions stay as history, with a notice that their folder is gone, and cannot go on.
This is the one place where Carrier deletes from the projects folder, and only because the person asked at that moment. Automatic cleanups keep the rules they have.
The sessions that used the project stay.
Removing a worktree from a project's page, or cleaning up the merged ones, is not this: it takes only the worktree's folder, as [0035](0035-a-worktree-folder-goes-when-its-work-is-done-and-its-branch-stays.md) does, and the branch and the session stay.

## Alternatives considered

Never deleting, as [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) has it. It is the safest, and a person with a dozen clones of several gigabytes each has to find and remove them in Finder.

Deleting outright. It frees the space at once, and a mistake on a folder that holds the only copy of someone's work cannot be undone.

Offering delete for any project, including the ones added by hand, with the Trash as the safety. The Trash would catch the mistake, and the folder was never Carrier's to offer to remove.

Asking the person to type the project's name to confirm. It is right for something that cannot be undone, and heavy for the common case once the Trash and the unsaved-work stop are there.

## Consequences

Carrier records how each project came to be, and an adopted folder stays something Carrier does not delete, even if it lies inside the projects folder.
The space is freed when the Trash is emptied, and the dialog says so.
A folder that cannot be moved to the Trash (another volume, a permission) is reported and nothing is removed.
A person who wants a hard delete of a clone does it themselves.
A session that was open in a project the person wants to delete has to be closed first.
