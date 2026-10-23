# 0010 - Carrier runs in the background as a detached process started on demand, not as a login service

- Status: accepted
- Date: 2026-10-22

## Context

`carrier` holds the terminal it was started from until Ctrl+C, and the people who run it want to leave it working and look at it when they choose, from a terminal or from the macOS app. [0005](0005-engine-independent-of-the-macos-app.md) already made the engine a process of its own with a control socket, so anything can attach to it; what is missing is a way to start it without a terminal and to look at it from one.

Two rules pull against an easy answer. The macOS app's spec says Starting Carrier is always an explicit act, never automatic, because Carrier runs agents with the user's permissions on the user's repos. And launchd gives a service a minimal `PATH`; the research in `docs/research/macos-app.md` measured that `claude`, `codex`, `gh` and `agent-forge` live in folders only the user's interactive shell sees, so a service would not find the tools it exists to run unless it also captured and stored the shell's `PATH`.

## Decision

We add `carrier start`, which launches Carrier in its own session with no terminal, writes its output to a log under `orchestrator/logs/`, waits for the control socket to answer and returns, and `carrier stop`, which stops it through the socket. A person looks at a running Carrier with `carrier status` (one snapshot) or `carrier watch` (the live panel, attached; closing it leaves Carrier running), and the macOS app is one more client of the same socket.

We do not install Carrier as a login service. Nothing starts it but a person: the command, the app's Start Carrier button, or the app's opt-in switch "Start Carrier when the app opens", which is off by default.

## Alternatives considered

A launchd LaunchAgent (`carrier install-service`) that starts at login and restarts on a crash. It is the usual way to leave something running, but it brings automatic start into a tool whose spec forbids it, and it needs the `PATH` problem solved and kept current. It can still come later as an opt-in on top of `carrier start`.

`nohup carrier &` or redirecting the output, which already works because the panel writes plain lines when it has no terminal. It has no wait for readiness, no clean stop and no way to look at the running process, which is the part people miss.

Leaving only the foreground process and the app. It is the status quo: the terminal stays busy, and a terminal-only user has no way to see a Carrier they started elsewhere.

## Consequences

A detached Carrier survives closing the terminal but not a logout or a reboot, and nothing restarts it if it crashes: the app shows it as stopped and it stays so until a person starts it. That is slower to recover than a service and is accepted as the price of never starting on its own.

The spawn exists twice for a while: in Swift (the app's StartController) and in the CLI. Until the app calls `carrier start` instead of its own code, the two are kept in step by their tests; once the CLI's has proven itself, the app delegates and the Swift one goes.

The one-instance lock per root stays the guard against two Carriers; `start` on a running Carrier says so and does nothing.
