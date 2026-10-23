# 0005 - The engine runs on its own and the macOS app is a client of its control socket

- Status: accepted
- Date: 2026-10-19

## Context

Today the engine and the terminal panel are one process: pausing, "check now" and quitting are actions inside it, and the panel reads the state from SQLite in the same process. A native macOS app is a different process, so something has to decide who owns the engine and how the app sees it and drives it. The engine runs for hours without anyone watching and its agents are child processes of it ([0004](0004-agents-run-on-host-with-terminal-preferences.md)), so the lifetime of the engine matters: if closing or crashing a window killed it, epics would stop halfway.

## Decision

The `carrier` process keeps running by itself and is not owned by the app. While it runs it listens on a control socket (a Unix socket in the `orchestrator/` folder, readable and writable only by the user). Over that socket it publishes the panel snapshot and the agent's output, and it accepts the commands the app needs: pause or resume taking epics, check GitHub now, and stop. The app is only a client: it connects to any live instance, including one started from a terminal, and can start one that is detached from it. Closing or crashing the app does not stop the engine; stopping is an explicit command, the same graceful shutdown as Ctrl+C. Today that shutdown is an anonymous closure inside the SIGINT handler and is not reachable from outside it, so it becomes a named function that the signals and the socket share. It answers before the process exits, has a timeout because it can otherwise wait forever on an orphaned agent child that keeps the pipes open, and also covers SIGTERM and SIGHUP, which today act as a crash ([research](../research/macos-app.md)).

The socket is created owner-only (mode 0600, inside a 0700 `orchestrator/` folder), the engine checks that its path fits the 104 bytes macOS allows because some Node versions truncate it silently, and a leftover socket is removed only after the instance lock is held, which is what makes it certain to be stale.

The app does not read SQLite and does not know its schema. The only contract between the two is the snapshot as JSON, which changes together with the types in `src/status/types.ts`. The Swift code lives in this repo under `macos/`.

## Alternatives considered

The app launches `carrier` as a child and talks to it over stdio. It is the simplest to wire, but the engine's life becomes the app's life, and a closed window or a crash would stop unattended epics. Rejected for that reason.

The app only attaches to a `carrier` that something else started (launchd or a terminal), and never starts or stops it. It keeps the engine independent but gives up the "control the process from a window" the app is for. Kept as a subset: the app can attach to a terminal instance.

Rewriting the engine in Swift. It throws away a tested engine to get a UI, and forks the logic between the two apps. Rejected.

The app reading SQLite directly for state. It couples Swift to the schema and gives no way to send commands, so a second channel would be needed anyway.

## Consequences

One channel serves both reading and control, and the terminal could later use the same socket. The engine gains a server and a command surface, which is new code in the engine and a new security boundary: anything that can write to the socket can pause or stop the engine, so its permissions are the user's only. When the engine is not running the app has nothing to show but "stopped": no history, because the history lives in SQLite and the app does not read it. An app that quits leaves the engine working, so the person has to stop it on purpose. The terminal panel does not change in this decision.
