# 0027 - The embedded terminal runs in-process with GhosttyKit and restores layout across launches

- Status: accepted
- Date: 2026-11-13

## Context

People using `Carrier.app` frequently need a real interactive shell inside a session's folder or worktree, or a quick general-purpose shell, without switching out to an external terminal app and locating the folder by hand.
At the same time, Carrier must preserve the native macOS speed, Metal/CoreText typography, IME input, and visual polish of the desktop app, while supporting multiple tabs, flexible split panes that can move and rearrange freely, confirmation before killing live processes, and session restoration across app restarts.
The `terminal` CLI commands live separately in [carrier-terminal-experience](../specs/carrier-terminal-experience.md), and orchestrator epic intervention is explicitly deferred to a separate effort so the core terminal subsystem remains cleanly decoupled.

Two main architectures exist for embedding a terminal inside a desktop app: running a separate Node/PTY daemon over IPC rendered through a web terminal (`xterm.js` + `node-pty`), or embedding a native terminal engine directly inside the macOS process.

## Decision

We run the embedded terminal in-process inside `Carrier.app` using `GhosttyKit` (`libghostty-spm`, MIT-licensed `GhosttyTerminal` wrapper over Ghostty's C API) as the native PTY, VT parser, input handler, and Metal/CoreText renderer.
Each terminal pane corresponds to one `GhosttyKit` surface cached by pane identity so UI transitions, tab switches, and pane moves keep the live PTY and scrollback untouched.

`CarrierCore` owns the domain model that `GhosttyKit` does not provide out of the box: terminal owners (`session` and `quick`), multi-tab ordering, a binary split tree per tab supporting pane insertion, removal, resizing, reordering, and cross-tab/cross-edge moves, plus an app-owned terminal settings model ready for a future Terminal settings page.
On app relaunch, Carrier restores persisted owners, tabs, split layouts, ratios, titles, and working directories by opening fresh shells in those saved positions and directories rather than keeping detached processes alive while the app is quit.

## Alternatives considered

Running an external Node PTY daemon over WebSockets or Unix sockets (the architecture used by Electron/web hosts such as `paradev` and `t3code`), paired with `xterm.js` in a `WKWebView` or a custom Metal renderer.
A detached PTY daemon lets child processes survive an app quit, but forces Carrier to bundle/manage `node-pty` native builds across macOS updates, proxy every keystroke, resize, and VT byte over IPC, and rebuild IME, selection, links, and GPU glyph rendering that `GhosttyKit` already solves natively in Swift/C.

Shipping an in-memory-only tab registry without layout persistence or split panes in v1.
That would simplify the initial slice, but breaks normal desktop terminal expectations (arranging splits freely and returning to open workspace tabs after restarting the app) and is harder to bolt onto a single-surface-per-tab model after UI integration begins.

## Consequences

`Carrier.app` ships the statically linked `GhosttyKit.xcframework` and `GhosttyTerminal` resource bundle (`terminfo` and shell integration) with third-party notices updated accordingly, gaining GPU-accelerated rendering, shell integration (CWD tracking, prompt markers, command exit codes), and native close-confirmation primitives (`TerminalViewState.onClose(processAlive:)`).

Because terminals run inside `Carrier.app`, running child processes exit when the user quits Carrier (gated by close confirmation when active processes exist), while the tab and split structure plus working directories restore cleanly on the next launch.
Extracting persistent out-of-process PTY survival later would still be possible behind a separate session backend if Carrier ever needs long-lived background dev servers across app restarts.
