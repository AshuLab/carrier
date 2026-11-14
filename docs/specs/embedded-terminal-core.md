# Embedded terminal core

Status: implemented (core only; UI unwired, unreleased)

## Problem

When working in `Carrier.app`, a user who needs to run commands, inspect git state, watch logs, or run quick tools in a session's folder or worktree must leave Carrier for an external terminal app and navigate to the right folder manually.
Nothing inside `Carrier.app` today can host native interactive shells, preserve terminal workspaces across restarts, or prevent accidental termination of running commands when closing a workspace or app.

This effort is scoped strictly to the native macOS terminal core so it works cleanly and deterministically before any app UI chrome or orchestrator epic integration is wired on top.
Note: `CarrierTerminalStore` and `CarrierTerminalView` are not yet instantiated or mounted in `Carrier.app`, so the `AppDelegate`, `PanelModel`, and `SessionActions` lifecycle hooks stay dormant until the UI PR opens the first surface.

## Solution

We embed `GhosttyKit` (`Lakr233/libghostty-spm`, pinned to `2.2.2026111302`, MIT) directly in `Carrier.app` via [0027](../adr/0027-embedded-terminal-runs-in-process-with-ghosttykit.md).
Ghostty handles the native PTY (`/usr/bin/login` login shell inheriting the user's full `PATH`), VT parser, Metal/CoreText rendering, IME, clipboard protection, URL click handling, drag-and-drop paths, scrollback search, and `foregroundPid` / `ttyName` / `close_surface(processAlive:)` signals.
Our code divides into two layers so domain rules remain fast, pure, and AppKit-free:

**`CarrierCore` (pure Foundation)** owns the domain model and workspace state machine (`TerminalOwner`, `TerminalTab`, `TerminalPane`, recursive binary split tree, layout moves/reordering, persistence schema, working-directory resolution, URL allowlist, and a structured terminal settings + theme contrast profile).
Every layout mutation — opening tabs, reordering tabs, splitting a pane on any edge, moving or swapping a pane within a tab or across tabs, resizing split ratios, toggling pane zoom, and closing panes with sibling promotion — is a pure value transition with deterministic focus fallback.

```swift
public enum SplitAxis: String, Codable, Sendable { case horizontal, vertical }
public enum SplitEdge: Sendable { case leading, trailing, top, bottom }

public indirect enum SplitNode: Equatable, Codable, Sendable {
    case leaf(UUID)
    case split(axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)
}
```

**`Carrier` (AppKit / SwiftUI runtime host)** owns `CarrierTerminalStore` (`@MainActor @Observable`), one shared `TerminalController`, per-pane platform view caching keyed by `paneId`, lifecycle cleanup, live process close confirmation, search/selection hooks, and persistence I/O.
Caching the underlying Ghostty `TerminalView` by `paneId` (rather than `tabId`) keeps the live PTY and scrollback untouched when switching sessions, hiding views, reordering tabs, or moving a pane between splits and tabs; only visibility pauses/resumes Ghostty's display link.

**Settings-ready configuration.**
Terminal preferences live in a dedicated `TerminalSettings` model backed by `AppPreferences` (`UserDefaults`) so a future Terminal Settings UI page can override theme colors, font family/size/ligatures, cursor style/blink, padding, minimum contrast, and close-confirmation behavior with live hot reload via `TerminalController`.
Each of Carrier's nine light and dark themes maps to complete, high-contrast `background`, `foreground`, `selectionBackground`, `selectionForeground`, `cursorColor`, and `minimumContrast` values.

**Persistence and restore.**
Whenever the terminal workspace structure mutates (tab/pane create, split, move, rename, or close), the store writes `<Carrier folder>/app/terminals.json` immediately ([0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)), while continuous split-ratio drags and shell `workingDirectory` updates are debounced; persistence is skipped under `--fixture` / `--selftest` runs.
On app launch, Carrier restores each owner's tabs, binary split tree, ratios, active tab/pane, zoom, titles, and validated working directories by spawning fresh shells in those positions.

**Process confirmation and teardown.**
Closing a single pane asks Ghostty (`close_surface` -> `onClose(processAlive:)`) or inspects active non-shell foreground/tty processes (`foregroundPid`, `ttyName`) and raises a confirmation request before killing a live command; callers can also pass `force: true` after the user confirms.
Closing an entire tab, deleting or archiving a chat session, or quitting `Carrier.app` (`NSApplicationDelegate.applicationShouldTerminate`) checks every affected pane for active processes before tearing down live surfaces and detaching views and callbacks from `TerminalController`.

## Scope

1. Package and bundle `GhosttyKit` (`Lakr233/libghostty-spm` `2.2.2026111302`), `GhosttyKit_GhosttyTerminal.bundle`, and third-party license notices in `Carrier.app` (`build-app.sh` and `check-app.sh`).
2. Model `TerminalOwner` (`.session(String)` and `.quick`), `TerminalTab`, `TerminalPane`, launch specs, directory validation, and URL policy in `CarrierCore`.
3. Support full tab and split-pane workspace operations in `CarrierCore`: create, select, reorder tabs, split on any edge inheriting the active pane's working directory, resize ratios, equalize, zoom toggle, move/swap panes across edges or tabs, and close panes/tabs with clean sibling promotion and active-focus fallback.
4. Persist terminal workspace layout and working directories to `<Carrier folder>/app/terminals.json` and restore them deterministically on launch (validating stale directories against fallbacks and clearing orphaned tabs).
5. Manage live `GhosttyTerminal` surfaces in `CarrierTerminalStore` cached by `paneId`, exposing search-in-scrollback, selection reading, paste, interrupt (`Ctrl+C`), and live teardown across SwiftUI view swaps and `CarrierTerminalView` mounts.
6. Model `TerminalSettings` in `AppPreferences` (`CarrierCore`) and map Carrier's nine light and dark themes plus font, ligatures, padding, cursor style, and contrast settings live into `TerminalController`.
7. Gate pane close, tab close, session archive/delete, and app termination (`Quit Carrier`) on active-process confirmation (`processAlive` / `foregroundPid` / `ttyName`), and guarantee child-process teardown when closing tabs, deleting sessions, or quitting the app.

## Decisions

**Dependency and runtime architecture.**
See [0027](../adr/0027-embedded-terminal-runs-in-process-with-ghosttykit.md) — `GhosttyKit` runs in-process without a separate Node PTY daemon.
Because `2.2.2026111302` already spawns `/usr/bin/login` -> `-/bin/zsh` cleanly on macOS and populates `foregroundPid` and `ttyName` at runtime, the host does not need custom `PATH` scraping.

**Pane-keyed caching and layout model.**
Every live `TerminalView` is stored in `CarrierTerminalStore` by `paneId`, while `TerminalTab` holds the structural `SplitNode` tree.
Reordering tabs or moving a pane between splits/tabs updates pure registry values without detaching or rebuilding the Ghostty surface unless its container view actually swaps.
Ratios on every internal `.split` node clamp to `[0.15, 0.85]` so panes never collapse to invisible zero-width slivers.
Every split node enforces unique leaf `paneId` invariants so moving a pane removes the source leaf before re-inserting at the target edge.

**Process activity detection for close confirmation.**
We verified against `libghostty-spm` `2.2.2026111302` (`upstream.cf5519b2`) that `view.foregroundPid` returns the interactive shell's PID when idle at a prompt, and switches to the active child's PID when a command runs; `performBindingAction("close_surface")` passes `processAlive == true` only when a non-shell process or background child is active.
For single-pane close, the store uses Ghostty's `close_surface` `processAlive` callback (with `force` override).
For multi-pane / multi-tab / app-quit preflight checks (`pendingConfirmation(for:)`), the store runs one batched off-main-thread `/bin/ps` query across pane TTYs (filtering common interactive shells with a 1.5s timeout and surfacing errors conservatively) behind a testable process-inspector seam so the user gets one clear confirmation prompt before anything starts tearing down.

**Link handling.**
Terminal link activation (`isAllowedTerminalURL`) permits only `http` and `https` URLs with a non-empty host.

**Persistence file location and format.**
Persisted layout uses JSON (`Codable`, versioned `schemaVersion: 1`) written atomically with `0600` permissions in `<Carrier folder>/app/terminals.json` ([0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)), stripping `envVars` so environment secrets never hit disk.
`SchemaVersionHeader` is decoded before the full snapshot so unrecognized future schema versions are logged and write-protected for that launch (newer files are never overwritten), while corrupt files are logged and moved to a timestamped `.bak` copy before recovering persistence.
Stale session ids are pruned only after two consecutive authoritative session snapshots omit them (`ChatSessionsPoller.onAuthoritativeSessionIds`, never when the chat host is unreachable or incomplete), and removed worktree directories fall back safely on restore.

**Testing seams per story.**
- Story 1: Existing `ThirdPartyNoticesTests` (`CarrierTests`) and `macos/scripts/check-app.sh` release bundle + `codesign --verify --deep --strict` verification.
- Stories 2 and 3: Pure unit tests in `CarrierCoreTests` (`TerminalCoreTests`) driving `TerminalRegistry` across split insertion, edge moves, cross-tab pane moves, tab reordering, zoom, ratio clamping, directory fallback, and close collapse invariants.
- Story 4: Pure encode/decode + round-trip + corruption/version-mismatch tests in `CarrierCoreTests`, plus temp-directory load/save integration tests on the persistence store seam without touching real `~/.carrier`.
- Story 5: `@MainActor` `CarrierTerminalStoreTests` verifying `paneId`-keyed `TerminalView` cache reuse across reparenting/moves, visibility toggling, synchronous teardown (`controller == nil`) on close, plus a gated/targeted offscreen `NSWindow` smoke test for selection/search/paste.
- Story 6: Pure mapping tests in `CarrierCoreTests` verifying foreground/background/selection/cursor contrast and font/cursor settings across all nine `Theme` values in both light and dark modes, plus `AppPreferences` round-trip defaults.
- Story 7: Injected process-activity inspector seam on `CarrierTerminalStore` (faked in `CarrierTests`) verifying blocked vs forced close for pane, tab, session deletion, and `AppDelegate` quit confirmation, plus `teardownAll` cleanup verification.

## Out of scope

App UI placement, triggers, buttons, tab bars, drawer/panel chrome, split drag-and-drop gestures, and the future Terminal Settings UI view (left to dedicated UI work once the core is settled).

Any integration with autonomous engine epics, epic intervention, resuming stopped epics from an embedded terminal, or injecting terminal output into agent turns (separated into its own epic).

Detached background PTY daemon survival when `Carrier.app` itself is not running (reopening Carrier restores saved tabs, split layouts, ratios, and working directories as fresh shells rather than reattaching to live orphaned processes).
