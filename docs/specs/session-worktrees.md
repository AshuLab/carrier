# A session can work in its own worktree

Status: implemented (v0.1.0)

## Problem

A user session works in a folder, and today that folder is the person's own: the agent edits their checkout, on whatever branch it is on, next to whatever they had not committed. That is fine for a quick question and a poor place to let an agent change code, so people who want to keep working while a session runs, or want to throw its result away, have nowhere to put it.

The sessions screens that were just designed ([in-app sessions research](../research/in-app-sessions.md), "Chat UI decisions") ask for exactly this: when a session starts, the person chooses between working in the base folder and in a new worktree, and picks the branch to start it from. The chat host of [the core chat](chat-host.md) only knows folders: it can run an agent in a path, and has no idea what a branch is, whether the folder is a git repository, what is uncommitted in it, or how to make or remove a worktree. Without that the app can draw the choice and nothing behind it.

This epic is the backend of that choice and nothing else. The screens are the sessions epic's, built in parallel against fixtures; what is common to both is the contract below.

## Solution

The chat host learns git, with the `git` on the machine and nothing else. It inspects a folder, creates a worktree for a session, and removes it when the session is deleted. Where a worktree lives, what it is called and when it dies are decided in [0014](../adr/projects/0014-a-session-worktree-lives-in-carriers-home-and-dies-with-its-session.md); this epic builds that.

**Inspecting a folder.** A new request, `workspace`, tells a client what a folder is, so the app can draw the sentence "Work in …": whether it is a git repository (and not a bare one), the branch checked out or that the HEAD is detached, the repository's default branch, how many files have uncommitted changes (tracked or not), the local branches and the remote branches as of the last fetch, when that fetch was, the `owner/name` read from the `origin` remote, and whether the folder is itself a linked worktree. A folder that is not a git repository answers with `git: false` and nothing else is asked of it. A second request, `fetch`, runs `git fetch origin --prune` in the folder (never prompting for credentials, and bounded in time) and answers with the new `workspace` reply, so the branch picker's "Fetch now" works.

**Names.** `suggestName` returns a free name, `<adjective>-<unit>-<place>`, from three word lists kept in the repository (units, structures and tech of StarCraft; single words, never a character's full name), rolled again whenever `carrier/<name>` is taken by a local branch, a remote branch or a folder, never numbered. `checkName` says whether a name the person typed is a valid one (the part after the fixed `carrier/` prefix: lowercase letters, digits, hyphens, underscores and dots, starting with a letter or a digit, at most 60 characters, and a valid git ref name) and whether it is free, with a reason in words when not.

**Opening in a worktree.** `open` accepts a `worktree` request: the branch to start from, one of those `workspace` listed (local or remote), and optionally a name. The host picks a name when none is given, creates `<folder>/chat/worktrees/<owner>/<repo>/<name>` (`<folder>` is the Carrier folder, `~/.carrier/` or `CARRIER_HOME`) on a new branch `carrier/<name>` cut from the chosen branch, opens the session in it, and records what it made (the path, the branch, where it started from and the base folder) with the session. A folder with no GitHub `origin` goes under `local/<folder name>`. It is one step that either leaves a session in a worktree or leaves nothing behind: a worktree whose session could not be created is removed. The base folder is never changed (no checkout, no stash, no commit), and a request that is not about a git repository, names a branch that is not listed, or a name that is invalid or taken is refused with a reason.

**Where a plan's worktree starts.** A new worktree of a plan is cut from the remote copy of the branch by default ([0037](../adr/projects/0037-a-new-worktree-is-cut-from-the-remote-branch-by-default-and-choosing-a-project-fetches-it.md), [the spec](worktrees-start-from-remote.md)): `git worktree add --no-track -b carrier/<name> <path> refs/remotes/origin/<branch>`, from whatever `origin/<branch>` the repository has on disk.
The plan's `worktree` takes an optional `startFrom`, `remote` or `local` (anything else is refused by the strict schema); without it the host applies `worktreeStart` of `chat.json` ([configuration](../configuration.md)), read at each plan.
`local` cuts from the local branch and refuses, as for any branch the repository does not list, a branch that has none.
A branch that exists only locally is cut from it with a remote start, with no notice and no failure.
A `branch` that already carries `origin/` is cut from that ref whatever `startFrom` says.
The session records the ref it was cut from (`origin/main` or `main`) as its worktree's start.
The host lists the capability `worktreeStart`, because an older host refuses the field: a client sends `startFrom` only to a host that lists it.
The older `open` request keeps its own `worktree: { from, name }`, which names the exact ref.

**Fetch if stale, and the counts.** `fetch` takes an optional boolean `ifStale` (anything else is refused by the strict schema).
With `ifStale: true` and a last fetch of `origin` within `FETCH_FRESH_MS` (the window of "The fetch before the cut") the host runs no `git fetch` and answers with the current `workspace` reply; with an older fetch, none on record, or no `ifStale`, it fetches as before.
The host lists the capability `fetchIfStale`, because an older host refuses the field: a client sends `ifStale` only to a host that lists it.
In the `workspace` reply a local branch that has `origin/<name>` carries `behind` (commits of the remote one it lacks) and `ahead` (its commits not on the remote one, the ones not pushed); a local branch without one carries neither, and neither does a remote branch.
The host reads every branch and its commit in one `git for-each-ref`, takes the two copies that print the same commit as 0 and 0 with no further call, and runs one `git rev-list --left-right --count` for each branch whose copies differ, eight at a time; a count git cannot make leaves that branch without counts and the reply stands.

**The fetch before the cut.** For a folder the person already had (a GitHub project keeps its own `clone` or `fetch` step, which fails the session when GitHub cannot be reached), a remote start runs the plan's `fetch` step ahead of the `worktree` step when `origin/<branch>` is on disk and the last fetch of `origin` (`fetchedAt` of `workspace`) is older than five minutes, one constant of the host, `FETCH_FRESH_MS`. It is the same `git fetch origin --prune` as `fetch`, with its timeout and no credential prompt. A fresh fetch, a local start, a branch with no `origin/<branch>` on disk and a `branch` that carries `origin/` run none. If the fetch fails, times out or removes `origin/<branch>`, the worktree is cut from the local branch, the `fetch` step still ends as `done` (the app lists it as "Updating the repository" and shows a reason only for a failed step), the send goes on, and the session stores a `notice` that names the branch, says why and, when `origin/<branch>` is known, how many commits the local branch is behind it (`git rev-list --count refs/heads/<branch>..refs/remotes/origin/<branch>`). A branch with no local copy is then cut from the `origin/<branch>` the last fetch left, with a notice saying so. A folder's session is never refused because the remote could not be reached.

**The list.** Each session in `list` says whether it works in the base folder or in a worktree and, for a worktree, its branch, where it started from, its path and the base folder, so the sidebar can show the branch and group the session under its repository.

**Deleting.** `deletePreview` takes one or several sessions and says what deleting them would discard, for each one that has a worktree: the uncommitted changes in it and the commits on its branch that exist nowhere else, so the app's confirmation can say it (the archive's "Clear sessions" asks for all of them at once). `delete` removes the session's worktree and its branch and then the session; a worktree that cannot be removed stops the deletion with a reason and the session stays. Archiving a session keeps its worktree. Only folders the host recorded for a session, and that lie under its worktrees folder, are ever removed, and a branch is only deleted if it is the one recorded; if the base folder is gone, so that git cannot do it, the worktree folder is removed directly and the branch is left to the repository that lost its folder.

What was cut. A watcher that cleans up worktrees whose session was lost: a recorded worktree goes with its session and nothing else is touched. Setting an upstream for the branch or pushing it: that is the agent's or the person's. The diff of a worktree: another epic. Special handling of submodules and sparse checkouts. A worktree inside the repository, beside it or under the engine's folder, and keeping the worktree after the session is deleted: they lost in the ADR.

## Scope

1. A client can ask what a folder is and learn: git or not, bare or not, the branch or a detached HEAD, the default branch, the number of uncommitted files, the local and remote branches, the time of the last fetch and the `origin` owner and name.
2. A client can fetch the remote of a folder and get the refreshed answer, and a fetch that fails or takes too long says so in words.
3. A client can get a free generated name and check one it typed: valid or not, free or not, and why.
4. Opening a session with a worktree request creates the worktree under the chat's folder, `<folder>/chat/worktrees/`, on a new `carrier/<name>` branch from the chosen branch, and the session runs in it.
5. Opening in a worktree changes nothing in the base folder, and a failure on the way leaves no worktree and no session.
6. A folder that is not a git repository, a bare one, an unlisted starting branch and an invalid or taken name are refused with a reason.
7. The list says which sessions work in a worktree and on which branch, from where, and in which base folder.
8. Before deleting, a client can see what would be discarded for each session with a worktree: uncommitted files and commits that exist nowhere else.
9. Deleting a session removes its worktree and branch; one that cannot be removed stops the deletion and says why; archiving removes nothing.
10. The host never removes a folder it did not record for a session or one outside its worktrees folder, and never passes a name or a branch to `git` as anything but an argument.
11. Sessions that exist before this change keep working: they are in the base folder.
12. A developer can test all of it with a fake git and a temporary SQLite, and the edge cases against real repositories in a gated integration test.

## Decisions

The requests and replies, as the contract the app builds against. All requests are strict objects with a positive integer `id`, like the others on the chat socket.

```ts
// new requests
{ cmd: 'workspace'; folder: string }
{ cmd: 'fetch'; folder: string; ifStale?: boolean }        // capability `fetchIfStale`
{ cmd: 'suggestName'; folder: string }                        // -> { name: string }, the part after carrier/
{ cmd: 'checkName'; folder: string; name: string }            // -> NameCheck
{ cmd: 'deletePreview'; sessionIds: string[] }                // 1..500 ids

// changed
{ cmd: 'open'; agent: string; folder: string; options?: Record<string, string>;
  worktree?: { from: string; name?: string } }                // from: a name `workspace` listed

// the plan of `open` (see "Where a plan's worktree starts")
plan.worktree?: { name?: string; startFrom?: 'remote' | 'local' }  // capability `worktreeStart`

type WorkspaceInfo = {
  folder: string;                  // the real path
  git: boolean;                    // false for a plain folder; every field below is then at its empty value
  bare: boolean;
  linkedWorktree: boolean;         // the folder is itself a linked worktree of another repository
  repo: { owner: string; name: string } | null;     // from `origin` (an ssh alias of GitHub counts), null without a GitHub origin
  branch: string | null;           // checked out; null when detached
  defaultBranch: string | null;    // origin/HEAD, else main or master when one exists
  dirty: number;                   // files with uncommitted changes, tracked or not
  branches: { name: string; remote: boolean; ahead?: number; behind?: number }[];  // local first, then remote as "origin/x"; "origin/HEAD" left out; ahead and behind only on a local branch that has an origin/<name>
  fetchedAt: number | null;        // ms since epoch of the last fetch of origin
};
type NameCheck = { valid: boolean; free: boolean; reason?: string };
type DeletePreview = { sessions: { sessionId: string; worktree: null | { path: string; branch: string; dirty: number; unpushed: number } }[] };
// each session summary in `list` and `events` gains:
type SessionWorkspace = { kind: 'folder' } | { kind: 'worktree'; branch: string; from: string; base: string; path: string };
```

`unpushed` is the number of commits on the session's branch that no other branch or remote branch contains, so a branch that was only created counts 0 and a commit that was pushed counts 0. `dirty` is the number of lines `git status --porcelain` prints. The default branch comes from `origin/HEAD` when it is set, else `main`, else `master`, else null; a client treats null as "ask the person".

Git runs through a port, with a fake for tests, as the engine's other tools do; the real one runs the `git` of the machine with `execFile` (never a shell), the host's own environment plus `GIT_TERMINAL_PROMPT=0`, and a time limit per command. Folder, branch and name only ever go to git as arguments after `--` or as a value that cannot start with a dash. The Carrier folder is the one of [0016](../adr/config/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md), shared and not copied. The worktrees folder is not the engine's folder (`<folder>/engine/`, which the host refuses), and it is checked by construction that a worktree's path lies under it. The `sessions` table gains the worktree columns by a migration of the chat database (`workspace kind`, `branch`, `from`, `base`, `path`), with the existing rows left as folder sessions.

The word lists are three arrays of lowercase single words, at least thirty each, no duplicates, and the generator takes its randomness as a parameter so a test can fix it. `suggestName` gives up after fifty rolls with a reason in words, which only an exhausted list could cause.

Testing seams, by story:

- Stories 3, 4, 5, 6, 7, 8, 9, 10 and 11: the host through the same interface its socket uses, with the fake git (it keeps a table of repositories, branches, refs and folders and plays scripted outputs and failures) and a temporary SQLite, as the host's other tests do. The fake runner of the chat stays for the agent. This is the broadest seam and carries the behaviour: the names, the checks, the atomic open, the preview, the removal order, the refusals.
- Stories 1 and 2: the parsing of git's output into `WorkspaceInfo` as pure functions over sample outputs (porcelain status, `for-each-ref`, `symbolic-ref`, `rev-list`), plus the socket test in the style of the existing one for the new strict requests.
- Stories 1, 4, 5, 8, 9 and 12: a gated integration test against real repositories made in temporary folders (`CARRIER_IT_GIT=1`, listed in the file's header): a repository with and without a remote, a detached HEAD, a bare repository, a linked worktree as base, an untracked file and an unpushed commit, the creation and the removal, and the base folder untouched. This is where what git really does in the awkward cases is settled, and a case that git refuses is refused with a reason in words.
- The word lists: a test of their shape (lowercase single words, size, no duplicates) and of the generator with a fixed random source.
- No tests: nothing is left without one.

## Out of scope

The screens (the sentence, the branch picker, the delete confirmation): the sessions epic. Cloning from GitHub, creating a repository, an empty folder as a workspace, and turning a folder into one of those. Merging a session's branch, opening a pull request, rebasing or syncing it with its source branch. The diff and the changes panel. Anything that changes the base folder. Worktrees for the engine's epics: they have their own.
