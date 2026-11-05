# 0018 - A new session is a plan, and the host prepares it when the first message is sent

- Status: accepted
- Date: 2026-11-04

## Context

The workspace sources spec decided that the clone happens when the repository is chosen in the workspace chooser, "not when the first message is sent", so the draft can show the branch, the uncommitted changes and the worktree choice for it. The same spec has "Let Carrier watch this repo" add the repository to the engine's `repos` at that moment, and New project creates its folder at "Create and use".

In use this made browsing the chooser a set of actions with consequences: a repository is cloned and written into the engine's config before anything is said to an agent, and the draft is one long-lived object that keeps its workspace, worktree and name after a message is sent, so a person who changes their mind has no way back to a blank draft. The owner wants sessions to be nearly disposable: the person chooses everything, and only when the first message is sent does what the session needs come into being.

## Decision

The new session draft is a plan, a value that says where the session will work (a folder that exists, a repository to clone, or a new project), with which worktree, branch and name, which agent and options, and the text. Choosing and changing any of it does nothing on the machine. Every time the person opens New session the draft is blank.

When the first message is sent the app makes one request to the chat host, `open`, carrying the whole plan. The host creates the session at once, in a preparing state, and then does, in order, only what the plan needs: clones or creates the project, makes the worktree, checks out the branch, starts the agent and delivers the message. Each step is recorded as an event of the session, so the conversation shows the list of steps and where it stands until the agent answers. A step that fails stops the preparation and leaves the session where it is, with the reason in words and a retry that repeats the steps that did not finish; a clone, a worktree or a folder already made is reused, never made twice.

The checkout follows what the person picked whenever the workspace is a git repository, with one guard: Carrier does not change the branch of a folder that already existed and has uncommitted changes. That step fails with the reason and the person decides. A repository that was just cloned and a worktree are Carrier's own, so they always follow the pick.

A repository is added to the engine's `repos` only when the preparation succeeded.

A clone, once made, stays in the projects folder when the session is deleted: it is a cache, and [0015](0015-the-chat-brings-projects-onto-the-mac-with-the-persons-own-github-login.md) already says Carrier never deletes it.

The branches of a repository that is not on disk yet come from the host asking GitHub with the person's own `gh` login, a read-only request; one that is on disk is read locally as today.

## Alternatives considered

Keep the clone at choosing, and only reset the draft. It is the smallest change and keeps the previews, but a repository is still cloned and written into the engine's config by looking at it, and it does not give the lifecycle the owner asked for, where a session exists from its first message.

The draft waits, with the steps shown in it, and the session appears only when everything worked. No session is left behind on a failure, but the person looks at a frozen draft while the agent thinks, a failed preparation leaves no trace to look at, and a retry has nowhere to live. A session in a preparing state costs a state and gives the person a place to see what happened and try again, as a failed first message already does.

Roll back what a failed preparation made. A clone is a cache and a worktree is empty at that point, so there is little to protect, and keeping them makes the retry fast; the person deletes the session, as any other, to remove the worktree.

## Consequences

The draft cannot show the uncommitted changes of a repository that is not cloned, which is nothing: a fresh clone has none. It shows the branches from GitHub, and the worktree name is generated without asking the host, because a fresh clone has no worktree to collide with; a name the person types is checked when the worktree is made.

A person can start a session on a slow clone and see nothing happen for a while; the steps list is what tells them it is alive, and Cancel stops the preparation and undoes only what that one send created.

The chat host's `open` grows from a folder and a worktree to a plan, behind a capability in its hello, so an older app still works with a newer host; an app that finds a host without it says the host is older and to restart it, rather than keeping a second draft behaviour. A session now has a state before it is idle, and the events of a session include steps.

The sentence in the workspace sources spec that says the clone happens when the repository is chosen is superseded by this decision.

0014 says Carrier never changes the base folder's branch. That stays true for a worktree session, and for any folder when the person has uncommitted changes; a person who picks another branch for a clean folder asked for it, and the draft says so beforehand.
