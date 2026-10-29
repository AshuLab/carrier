# 0007 - Continue in Terminal: the engine sends a descriptor, the app builds and launches the command

- Status: proposed
- Date: 2026-10-21

## Context

When an epic stops for a person, or has finished, that person may want to talk to the agent that did the work: ask why a reviewer flagged something, or unstick an author. The three harnesses can resume a session in an interactive terminal (`claude --resume <id>`, `codex resume <id>`, `agy --conversation <id>`), and the engine already records each execution's session id. The app is a separate process that never reads SQLite ([0005](0005-engine-independent-of-the-macos-app.md)), so the engine has to tell it what to resume, and the app has to open a terminal.

Two things make this delicate. The id and the folder come from the engine and, through it, from agent output, so building a shell string from them is an injection risk. And the agent ran as the Forge bot, with its token and git identity, while a terminal the person opens runs as them with their own environment.

## Decision

The engine publishes, for each session, a descriptor with three fields: the harness, the session id and the working folder the session was started in, plus the path of the agent's configuration folder when the engine set one (a path, not a secret). It never publishes a command line or a token, and it publishes nothing for a session that is still running, because two writers on one session would corrupt it. The app offers the action only for a session that is not running, in an epic that needs a person or has finished.

The app validates the descriptor before using it: the harness must be one of the allowed harnesses, the id must match a strict identifier pattern, and the folder must be an existing absolute path inside the engine's folder, `<folder>/engine/` in the Carrier folder. It then builds the command itself, putting each value in single quotes, writes it to a one-use script file with a `.command` extension and mode 0700 in the user's temporary folder, and opens the file with `NSWorkspace`, which hands it to the user's terminal. The script removes itself. It runs as the user, in their environment, not as the Forge bot.

The folder is the one the session started in, which for a ship session is the shared clone, not the epic's worktree. The ship session is also the one that Continue in Terminal resumes for an epic in ship: the lanes are subagents inside it and have no session of their own.

## Alternatives considered

AppleScript `tell application "Terminal" to do script`. It works, but the first use shows the system's Automation permission prompt, and the app would hold a permission to control another app for a small convenience.

`open -a Terminal` with arguments, with no script. It cannot run a command in a chosen folder in a portable way and depends on the terminal application.

The engine sends the whole command string. The simplest wiring, and the one with the injection risk: anything that can influence the id or folder would run in the user's shell.

An embedded terminal inside the app. It is the better experience and stays a later possibility, but it is a large piece of work and the owner chose to start with a new terminal window.

Run it under the bot's identity, copying its token into the terminal. Rejected: it would spread a credential to a place it does not need to be, and the work is the person's.

## Consequences

No Automation permission prompt and no quarantine flag on the script (verified). The security boundary is the app's validation, so the allowlist and the patterns have to change whenever a harness is added, and they are tested. The behaviour depends on the user's handler for `.command` files, which is Terminal by default; iTerm2, Ghostty and Warp have not been verified. Whether an interactive resume finds a session that was created by a headless run from another folder has not been verified either, and the feature is not trusted until it is. Because the engine's agents used their own configuration folders, the terminal may need the same `CLAUDE_CONFIG_DIR` or `CODEX_HOME` to find the session; the engine can send those two folder paths and nothing else.
