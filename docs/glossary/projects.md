# Projects

**Workspace** - The folder a user session works in: a folder on this Mac the person picks, a GitHub repository the chat clones for them into the projects folder, or a new project it makes there, both when the first message is sent ([0018](../adr/0018-a-new-session-is-a-plan-and-the-host-prepares-it-when-the-first-message-is-sent.md)). The sidebar groups sessions by workspace. It is never the shared clone an epic runs in nor an epic's worktree, and Carrier's list of repos to watch is not where workspaces come from ([0015](../adr/0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md)). A workspace whose folder is in the person's list is a project ([0041](../adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)).
_Avoid_: epic checkout.

**Projects folder** - The folder where a new clone or a new project goes by default: a clone at `<owner>/<repo>`, a new project at `local/<name>`. By default `<CARRIER_HOME>/chat/projects`, changeable in the chat config. It is not where projects have to live and Carrier does not list what is in it ([0041](../adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)). It is the person's: Carrier fetches in it and deletes from it only when the person removes a project it made and asks for the files to go ([0040](../adr/0040-deleting-a-project-from-disk-is-only-for-what-carrier-made-and-goes-to-the-trash.md)). It is not the engine's `repos/`, where the engine keeps its own clones and the chat host refuses to work.
_Avoid_: workspace folder, clones folder, repos folder, where projects live.

**Project** - A folder the person has registered with Carrier as somewhere they work: one entry of `projects.json` with its path (its identity), name, icon, tags, what a new session starts with there, its actions, and whether it is pinned or hidden from the new session picker ([0041](../adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)). It is added by hand from Settings, or becomes one when the chat clones or creates it at a first message; a folder picked with Open a folder stays a plain workspace until it is added. It is not an epic's repository: Carrier watching it is a switch on the project that writes the engine's `repos`, and removing the project does not touch it.
_Avoid_: repo (for the folder; a repo is `owner/name` on GitHub), watched repo, workspace (a session's folder, which may not be a project).

**Project action** - A command the person sets on a project, run by the chat host as a step of the preparation, in the folder of a new worktree or of a fresh clone, and again when the folder of a cleaned worktree comes back. It is kept in `projects.json` and never read from the repository ([0039](../adr/0039-a-projects-actions-are-kept-in-carrier-and-never-read-from-the-repository.md)). It is not run in an epic's worktrees.
_Avoid_: hook (git's word), script, setup.

**Base folder** - The workspace's own folder, as opposed to a worktree made from it. A session that works in the base folder edits the person's own checkout, with whatever branch and uncommitted changes it has.
_Avoid_: main folder, original, source.

**Session worktree** - A git worktree that Carrier creates for a user session, on a new branch named `carrier/<adjective>-<unit>-<place>` and cut from a branch the person picks, so the base folder stays untouched. It lives in the chat folder's `worktrees/`, its name is generated (the person may type another after the `carrier/` prefix) and it is removed with the session ([0014](../adr/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md)). It is not an epic's worktree and not a lane.
_Avoid_: workspace copy, sandbox, checkout, epic worktree.

**Start point** - The branch a session worktree is cut from, taken from its remote copy (`origin/<branch>`) by default and from the local branch when the person chooses it.
The default is `worktreeStart` in `chat.json`, the session's own choice is the Remote or Local tab of the branch picker, and a branch that exists only locally can only start from local.
A start point that cannot be reached falls back to the local branch with a notice ([0037](../adr/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md)).
_Avoid_: base branch (that is the base folder's), source branch, parent branch.
