# 0028 - Epic Continue in Terminal runs inside an ephemeral embedded Ghostty drawer

- Status: accepted
- Date: 2026-11-15

## Context

In [0007](0007-continue-in-terminal-through-a-validated-descriptor.md), Continue in Terminal wrote a one-use `.command` script (mode `0700`) and handed it to `NSWorkspace` because `Carrier.app` did not yet host an embedded terminal.
Now `Carrier.app` embeds `GhosttyKit` in-process with owner-scoped workspaces and bottom drawers ([0027](0027-embedded-terminal-runs-in-process-with-ghosttykit.md)).
For epic runs in `EpicView`, kicking the user out to an external Terminal.app window is no longer necessary, while Health and Forge fix actions still launch through `.command` scripts under `0007`.

## Decision

Epic **Continue in Terminal** runs inside `Carrier.app` using an ephemeral `TerminalOwner.epic(repo:issue:)` bottom drawer in `EpicView`.
`validateResume` still enforces the harness allowlist, strict session-id pattern, and existing absolute directory inside `<Carrier folder>/engine/`.
`embeddedResumeLaunch(_:)` checks directory accessibility, fails closed on `cd`, and constructs an interactive login shell command (`/bin/zsh -il -c`) with inline `CLAUDE_CONFIG_DIR` or `CODEX_HOME` scoping instead of writing a `.command` file for `NSWorkspace`.
Clean exits close the resumed pane and collapse the drawer when no tabs remain, whereas non-zero exits keep the pane open (`Press Return to close...`) so errors remain visible.
Re-clicking **Continue in Terminal** for an open session focuses the existing tab and pane rather than spawning a concurrent writer.
`.epic` workspaces are excluded from persistence in `<Carrier folder>/app/terminals.json` and closed automatically if the epic starts running again.

## Alternatives considered

Keep `.command` + `NSWorkspace` for epics while using Ghostty only for sessions and standalone terminals.
That avoids changing epic UI flow, but splits terminal debugging across external windows and loses integrated close guards and inline error retention.

Persist `.epic` tabs in `terminals.json`.
Rejected so resumed harness CLIs and their engine-scoped config paths never respawn unattended on app relaunch.

## Consequences

Epic Continue in Terminal no longer relies on macOS's `.command` file handler or launches external windows for interrupted runs.
Resumed shells run in the user's environment without Forge bot credentials, while Health and Forge fix launchers remain governed by [0007](0007-continue-in-terminal-through-a-validated-descriptor.md).
Control returns to the orchestrator only when the person explicitly chooses Resume in `EpicView` (or when active `.epic` drawer panes close as the epic starts running).
