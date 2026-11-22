# 0041 - A project is an entry of `projects.json`, identified by its folder

- Status: accepted; amends [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) (the list the chat works from, and what the projects folder is) and [0018](0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md) (when a clone or a new project happens)
- Date: 2026-11-21

## Context

Until now the person's projects were only folders: a path on a session's row, grouped in the sidebar by the last part of that path, with the icon's colour made from the name. Nothing could be set on a project (a name, an order, tags, an icon, what a new session starts with), and the only page about repositories in Settings is the engine's list of what Carrier watches.
[0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) gave the chat one projects folder where everything it brings lands, and said the chat has a list of its own without saying where it is kept.

The person wants a place to manage the projects they work on, apart from Carrier watching any of them, and their projects are in more than one folder.
Three things are hard to change once people have set things on their projects: what identifies a project, where what they set is kept, and who may write it.

## Decision

We keep the person's projects in `projects.json`, at the top of the Carrier folder with the other files a person edits ([0034](0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)), read by the app and by the chat host.
An entry holds the project's path, its name, how it came to be (`origin`: `cloned`, `created` or `added`), whether it is pinned or hidden, its tags, its icon (a colour and a mark, or an image), what a new session starts with (agent, base folder or worktree, base branch; empty means the same as everywhere) and its actions ([0039](0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)).
What can be derived is never in the file: the remote, the branch, the worktrees, their state and their size. The size is cached by the host somewhere else, since walking `node_modules` is slow.
Both the app and the host write the file, as both write `engine.json`: read again just before writing, written whole and atomically, every key the writer does not know kept; the schema is strict and goes through the config contract tests.

A project is identified by its folder's path. Adding a path that is already a project opens that project. A project whose folder is gone stays in the list as not found, with a way to point it at the folder's new place.

There is no folder where a person's projects have to live. Each project is added by its own folder: an existing one, a clone from GitHub or a new project. `projectsFolder` in `chat.json` stays, and is only where a new clone or a new project goes by default (`<owner>/<repo>` and `local/<name>`, as before). Carrier does not scan it or list what is in it, and it does not import the clones that were there before: the list starts empty and the person adds what they choose.

A project is born in one of two ways. The person adds it by hand from Settings, and a clone or a new project then happens at once, since the person asked for it. Or a new session's plan that clones or creates a workspace is prepared successfully at the first message ([0018](0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)), and the clone or the new folder becomes a project. A folder chosen with Open a folder in a new session stays a plain workspace, with an Add as project to turn it into one.

A project's name and icon are what it is called and drawn as wherever it shows: the sidebar's groups, the rows of a session, the new session's picker and the rows of an epic whose repository is the project's `origin`. A project that has no icon of its own is drawn as before, with the initials of its folder on a colour made from its name. An image is copied, made small, into the Carrier folder and the entry names the copy, so moving or deleting the original changes nothing.

Hiding a project takes it out of the new session's picker, among projects and among recent folders, and nowhere else: its sessions stay grouped in the sidebar.

Watching stays the engine's. The Carrier switch of a project reads `engine.json`'s `repos` as it is when the page opens and writes the project's `owner/name` to it, and needs a GitHub origin. Removing a project does not touch the watch, and the Repos page is as it was. The engine's repos are still not offered as workspaces, and a watched repository the person never cloned is not a project.

A project's worktrees are the sessions whose base folder is its path, not the folders on disk under its name, and the layout of `worktrees/` does not change. Adding a project whose worktree directory (`<owner>/<repo>`, or `local/<folder name>` without a GitHub origin) would be the same as another project's is refused, with the reason, as the engine refuses two watched repos with one folder name.

## Alternatives considered

A global projects folder that Carrier scans, the shape [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) had. It is one place to look, but it forces a layout on the person and hides the projects that are anywhere else.

What the person sets kept in the repository (`.carrier/project.json`). It travels with the repo, but it dirties repositories that are not the person's, and it would make Carrier read commands from a repository it just cloned ([0039](0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)).

A table in `chat.db`. The host owns it, but the app would need requests and a capability to read and to write it, and nobody could look at it or mend it by hand; accounts already live in a file both processes read ([0020](0020-accounts-live-in-a-file-both-processes-read.md)).

Extending `engine.json`'s `repos` with a path, tags and an icon. It is one list, but it ties the projects to the watcher, which is what hurt in the first place, and the engine's schema would carry fields only the app reads.

Importing the clones already in the projects folder the first time. It would fill the list with things the person never chose; they decided the list starts empty.

Naming worktree folders by a project id. It would end the collisions between two projects with one folder name, and it would move every worktree that exists.

## Consequences

Two files are written by two processes with the same careful pattern, and a project's settings survive a reset of `chat.db`.
A project and its sessions are matched by path only: a folder that is moved loses the match, and Locate… points the project at the new place without rewriting what its old sessions remember, so they stay where they were.
Someone who updates sees an empty Projects page, and the clones they already have stay on disk, unlisted, until they add them.
The sidebar keeps grouping sessions by the last part of the folder's path, as it does.
The sidebar and the session rows now read the project list, so a name or an icon set once is the same everywhere.
Two lists of repositories exist, the person's projects and what Carrier watches, and the switch on a project is the only bridge between them.
