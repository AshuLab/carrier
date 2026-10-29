# The chat in the Carrier folder, started by the app

Status: spec

## Problem

A person who opens the macOS app cannot use its sessions unless someone started the chat host by hand. The app starts the host only at the moment a new session is created, and only when three settings (`node`, `carrier`, the config path) were filled in by someone who knows what they are, so opening the app on a Mac where the host is not running shows an empty list of sessions that look lost. The author has run the host in a terminal of its own for the whole of the work on the chat, and nobody else could use the app at all.

Underneath, the host cannot start by itself. `carrier chat-host` demands `--config`, loads the engine's whole schema and reads from it the root folder, the log level, the GitHub timeout and the chat's own agents and projects folder, so a person who only wants to chat has to have configured an engine first, and the app cannot start the host before any engine exists. The chat's files are also split across two folders that were never designed together: its database, socket and projects under the engine's `<root>/chat` (`~/.solve/` by default, a name that belongs to the skill set) and its session worktrees under `~/.carrier/`.

We know it is solved when someone opens the app with Carrier installed, with no engine configured and no terminal, and sees their sessions and can start new ones, and when `carrier chat` from a terminal does the same.

## Solution

The chat host and its client take only the Carrier folder, `~/.carrier/` or `CARRIER_HOME`, as ADR 0016 defines it. Everything the chat owns lives in `<folder>/chat/`: `state/` (the database, the socket and the lock), `logs/`, `projects/` and `worktrees/`, and its configuration in `<folder>/chat/chat.json`. The `<root>/chat` folder, `root` as far as the chat is concerned, and `--config` on `chat-host` and on the way `carrier chat` starts the host all go away, and nothing from the old locations is read.

The chat's configuration is a level of its own. `chat.json` holds the agents a chat can start with (the same shape as the engine's `chat.agents` today, `claude` and `codex` by default), the projects folder (`<folder>/chat/projects` by default, an absolute path or one starting with `~/`), the GitHub timeout in seconds (30 by default) and the log level (`info` by default). Every key is optional and the file may not exist. A file that cannot be read or does not match its schema makes the host refuse to start and say which key, and the app shows that as it shows any host that fails to start (the alert with the tail of the log), instead of running on defaults the person did not choose. The `chat` section leaves the engine's config, which rejects it as any other unknown key, and the engine keeps its own GitHub timeout and log level.

The chat refuses to work inside the engine's folder, `<folder>/engine/`, and through a symlink into it, as it refuses the engine's folders today. That is where the engine will live once it joins the Carrier folder, so until then the engine's old folders are not protected by the chat; it is accepted because the next epic lands right after this one and the person would have to choose such a folder by hand.

`carrier` learns to say its own version with `carrier --version`, the number the host's hello already carries.

The app starts the chat host every time it opens when it does not answer, not only when a session is created, because the host runs no agent until a session exists and the sessions in the sidebar are what the host holds. The command it builds needs `node` and `carrier` and no config path, and it passes `CARRIER_HOME`, taken from the app's own environment or `~/.carrier`, so a build under development launched with a scratch folder never touches the author's real sessions. The log of that start is `<folder>/chat/logs/app-start.log`.

When the app cannot find `carrier`, it does not interrupt the person with an alert at open. The Sessions section of the sidebar and the Sessions home say what is missing and what to install or set, until it is fixed. Creating a session while it is missing keeps the alert it already has, because there the person asked for something that cannot happen.

When the host that answers is older than the installed `carrier`, the app replaces it, only if no session is working or waiting for an approval; otherwise it tells the person to restart it, because stopping the host closes its agents' processes and the work in them. "Older" is the version: the app asks the installed `carrier` for its version once per launch and compares it with the hello's. A build under development keeps the same version, so there the host is restarted by hand, as it is today.

The documentation that describes the chat is rewritten to the new model in this same epic, with no mention of how it used to be: the chat-host and session-worktrees specs, ADRs 0013, 0014 and 0015, the chat parts of the README, `AGENTS.md`, the configuration guide and `macos/README.md`, and the glossary entries of the projects folder and the session worktree. The README also gains a short guide to developing against a throwaway folder (`CARRIER_HOME`).

## Scope

1. A person with no engine configured runs `carrier chat-host`, or `carrier chat`, with nothing but the Carrier folder and the host starts.
2. Everything the chat keeps is under `<folder>/chat/` (state, logs, projects, worktrees), and a throwaway `CARRIER_HOME` leaves the person's real folder untouched.
3. The person sets the chat's agents, projects folder, GitHub timeout and log level in `chat/chat.json`, each optional and the file too.
4. A `chat.json` that cannot be read or is wrong stops the host with a message that names the key, and the app shows it as a failed start.
5. The engine's config rejects a `chat` section.
6. A chat never works inside `<folder>/engine/`, nor through a symlink into it.
7. `carrier --version` prints the version.
8. When the app opens and the host does not answer, it starts it with no session and no config path, passing the Carrier folder.
9. When `carrier` cannot be found, the app opens without an alert and the Sessions sidebar section and the Sessions home say what is missing.
10. A host older than the installed `carrier` is replaced by the app when no session is working; with one working, the app says to restart it and leaves it running.
11. The chat documentation describes the new model, and a developer can follow the README to run the app against a scratch folder.

## Decisions

The model, the layout and the three levels of configuration are in ADR 0016; this epic is its chat half and does not restate it.

`chat.json` is read as the engine's config is: one schema, strict (an unknown key is an error), with the same result shape (`ok` and a list of path and message). The projects folder is re-read at each request, as it is today, so a change applies to the next clone with no restart; the agents, the timeout and the log level are read when the host starts. The default projects folder keeps the rule that it may not lie inside the engine's folders or the chat's own `state/`, `logs/` and `worktrees/`.

The socket path keeps its limit: the server already refuses a path that does not fit in a socket and says so, and `<folder>/chat/state/chat.sock` fits for any ordinary folder.

The app learns the Carrier folder from `CARRIER_HOME` in its own environment, else `~/.carrier`; there is no preference for it in this epic. The fixture server follows the new layout.

The replacement rule is a pure decision of three inputs (the running host's version, the installed version, whether a session is working or waiting) with three outcomes: keep, replace, tell the person to restart. The notice for a missing `carrier` is the same kind of pure value, built from what the settings lack.

Testing seams, per story:

- 1, 2: `host.test.ts` drives `startChatHost` through its overrides (logging, clock, exit, runners, git) with a temporary folder, which is the seam the host is tested through today, and `server.test.ts` covers the paths; `main.test.ts` covers that `chat-host` and `chat` dispatch without `--config`. The CLI client's `chat.ts` is tested with its replaceable `start`. A test for the socket path of the app (`chatSocketPath`) sits with the other path tests of `CarrierCore`.
- 3, 4: a unit test of the chat config loader for defaults, a missing file, an unknown key, a wrong type and a relative projects folder; the host test asserts it refuses to start with that message. The app's alert for a failed start already exists and is not tested again.
- 5: `load.test.ts`, the engine schema's own test, gets the rejection.
- 6: `folder.test.ts`, with the engine folder as the new place.
- 7: `main.test.ts`.
- 8: the command the app builds is a pure function in `CarrierCore` (`startChatHostCommand`) and so is the decision to start; both are tested in `StartChatHostTests` with no `--config` and with the folder in the environment. The wiring in the app delegate has no automated test, like the rest of the shell's views and delegates; it is checked by running the app.
- 9, 10: the notice and the replacement rule are pure functions in `CarrierCore`, each with its own test file; the views that show them have no test.
- 11: no tests, it is documentation; the review greps the chat documents for the old locations and for `--config` on the chat.

## Out of scope

Moving the engine into the Carrier folder, removing `root` and `~/.solve/`, the engine's config and its start from the app: the next epic.

Homebrew, the signing and notarization, and the Settings fields that disappear when `carrier` has a known place: their own epic.

The native setup wizard, what the app shows of the machine's tools and logins, and the coexistence with Solve's worktrees: separate epics.

A Settings pane for `chat.json`, and a preference for the Carrier folder.

A build identifier to tell a stale host apart under development.

Migration of any kind, and reading the old folders or the old `chat` section of the engine's config.
