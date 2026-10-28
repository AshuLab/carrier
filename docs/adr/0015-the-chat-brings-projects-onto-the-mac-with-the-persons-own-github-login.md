# 0015 - The chat brings projects onto the Mac with the person's own GitHub login

- Status: accepted
- Date: 2026-10-28

## Context

A user session works in a folder the person picked, and nothing else is offered: the New session draft lists recent folders and Open folder…. Someone who wants to talk to an agent about a repository that is on GitHub and not on their Mac, or to start from nothing, has to prepare a folder by hand first.

Carrier already knows repositories, but they are the engine's: the config's `repos` carry only `owner/name`, and the clones the engine keeps for them live under the shared root's `repos/`, which the chat host refuses to work in on purpose. The engine also reaches GitHub as a profile that can be a bot identity, chosen for unattended work, and its repo list shows only what that login can push to.

Three things about what the chat brings onto the Mac are hard to change once people have work in it: where it lives, whose credentials fetched it, and whether Carrier's own list of repos is the list the person works from.

## Decision

The chat brings projects into one projects folder, `<CARRIER_HOME>/chat/projects` by default and changeable in the config. A clone goes to `<owner>/<repo>` and a new project to `local/<name>`, the layout the session worktrees already use. A repository that is already there is fetched, not cloned again. Carrier never deletes anything in it.

A project comes from a folder the person picks, from a GitHub URL (`owner/repo` or the full address), from a list of the repositories the person's GitHub login can read, or from nothing: a new project is a folder with `git init`, on this Mac only. The clone happens when the repository is chosen, not when the first message is sent, so the draft can say the branch, the uncommitted changes and whether a worktree is possible before anything is written.

The GitHub login is the person's own: the account that is active in `gh` when they pick. The chat host uses it to list and to clone, never the engine's profile, and the token goes to git in the environment and not in argv, as the engine does. When `gh` is missing or not signed in, the draft says so in words.

The chat has a list of its own. The config's `repos` are not offered as workspaces. Carrier watching a repository is a separate choice, offered when a project comes from GitHub and on by default: choosing it adds `{ "name": "owner/repo" }` to the config's `repos`, and the engine, which reads the config when it starts, begins to listen from its next start with a clone and worktrees of its own.

## Alternatives considered

Showing the config's repos in the picker. It matches what a person sees in Settings, but the only clones Carrier has for them are the engine's, which a chat must not touch, and the config has no folder of the person's to point at.

A `path` for each repo in the config, filled by hand or from the app. It makes the picker follow the config, but it asks the person to maintain a second list of folders and ties the chat to the engine's file.

Cloning when the first message is sent. It would not need a pending state in the draft, but the draft would have nothing to show about branches and a worktree, which is what its sentence is for.

Listing only what the login can push to, as the engine's picker does. It is the right filter for repos to watch and the wrong one for a conversation, which needs only to read.

Cloning with the engine's profile. It already has the code, but a bot identity may not see the person's private repositories, and a conversation of the person's is not the engine's unattended work.

Making a new project also create the repository on GitHub. It would let Carrier watch it from the start, and it is a larger decision about a repo's name, owner and visibility that this one leaves out.

## Consequences

Disk use grows with what the person brings in, in a folder they can see and clean. A repository Carrier watches has two clones on the machine, the engine's and the person's, which the engine never touches and the chat never edits in the engine's.

The chat can open a repository the person can only read: an agent can change the local clone and the person cannot push it. That is the person's call, as it is with any folder.

Choosing to watch a repository changes the config file and takes effect at the engine's next start; the app says so and does not restart anything on its own.

The chat needs `gh` on the machine and signed in for anything from GitHub; a folder the person picks does not.
