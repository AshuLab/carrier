# Terminal

The embedded Ghostty terminal in `Carrier.app`: standalone terminals in the sidebar, split panes, the session drawer and the bottom-anchored Zsh prompt.

## Standalone terminals

The sidebar's `Terminal` section (`Carrier/Features/Terminal/TerminalSidebarView.swift`, `TerminalRows`) lists each standalone terminal instance (`TerminalOwner.terminal`), separate from chat sessions.
Each standalone terminal keeps its own ordered list of tabs, active tab and split panes.
Clicking `+` in the section header, "New Terminal Session" in the empty state (`EmptyState.noTerminals`) or "New Terminal" in the toolbar creates a new standalone terminal rooted at the home folder.
When the `Terminal` section is unfolded and has at least one terminal, clicking its magnifier or pressing `⌘F` opens the sidebar's search field (`TerminalRows`).
When `Terminal` itself is selected (`Selection.terminals`), `TerminalsHomeView` lists the open standalone terminals with toolbar Search and `+ New Terminal`.
Closing a standalone terminal from its hover `×`, middle-click (`onMiddleClick`) or context menu asks first when running foreground processes are detected and `confirmCloseRunningProcess` is on (`CarrierTerminalStore.closeAll`), then selects the next open standalone terminal or falls back to the overview.

## Workspace, tabs and splits

Selecting a standalone terminal (`Selection.terminal(id:)`) shows `TerminalDetailView` (`Carrier/Features/Terminal/TerminalDetailView.swift`).
The terminal surface extends under the translucent top toolbar across the full detail height, while top-right pane controls are inset below `safeAreaInsets.top` (`topControlsInset`) so they stay clear of toolbar buttons.
Each pane is a rounded card (`TerminalSurfaceCard`) with a margin around the split tree and an 8 pt gap between panes; the surface is glass (`glassEffect`, tinted with the theme's color) when it is translucent and the theme's color under a fine edge when it is not.
The tab strip (`Carrier/Features/Terminal/TerminalTabBarView.swift`, `TerminalTabBarView`) sits along the bottom edge as a flat group as wide as the tabs (it scrolls horizontally and fades at the end that has more; only the selected tab is glass) with the add-tab and, in the drawer, hide buttons (`TerminalBarButton`) beside it, outside the group, with drag reordering, context-menu and VoiceOver tab move actions, inline rename popovers, a pinned `+` button to add a tab in the active tab's folder, Close Tab / Close Other Tabs in the context menu and middle-click or `×` to close a tab.
Hovering near the top of a pane reveals floating glass controls (`TerminalPaneHeaderView`) to split right, split down, zoom or restore a split pane, drag a pane to another pane's edge to move it or center to swap (`terminalDropZone`), equalize splits or detach a pane into a new tab.
All tab, split, focus, zoom, equalize, detach and close actions are also available via the menu bar (`Terminal` menu, `TerminalMenuControls`), keyboard shortcuts (`⌘⌥T`, `⌘⌃T`, `⌘T`, `⌘D`, `⌘⇧D`, `⌘⇧↩`, `⌘⌥[`, `⌘⌥]`, `⌘⇧[`, `⌘⇧]`, `⌘⇧W`) and pane accessibility actions.
Split dividers (`SplitContainerView`, the gap between two cards) and the drawer's top edge (`TerminalDrawerView`) share `TerminalResizeDivider`, resize by drag or accessibility adjustment with `AppKit` resize cursors managed by `hoverCursor`, and draw a line in the window's `.tint` only while hovered or dragged.

## Appearance and theme alignment

The embedded terminal follows the app's active `Theme`, Light/Dark scheme, `AccentColor`, `Tint` (`off`, `subtle`, `strong`) and **Translucent windows** accessibility-aware preference (`TerminalAppearanceProfile`, `TerminalAppearanceMapper`).
Each of the 12 themes (`carrier`, `graphite`, `ocean`, `forest`, `sunset`, `paper`, `rose`, `lavender`, `midnight`, `solarized`, `nord`, `gruvbox`) provides a curated 16-color ANSI palette in both light and dark modes alongside high-contrast foreground, `boldColor`, accent-tinted selection colors, `cursorColor` and `cursorText`.
Solarized, Nord and Gruvbox take their window and sidebar from the background tones of the palettes of the same names and their accent from Solarized's blue, Nord's frost cyan and Gruvbox's yellow, each with its own light and dark version; their ANSI colours are the palettes' own, nudged only where the contrast test needs it (deeper accents and reds in the light versions, lighter in the dark ones).
When **Translucent windows** is active (with system Reduce Transparency off), with any theme, the Ghostty surface uses `backgroundOpacity = 0` over the pane card's glass and `TerminalDrawerView` is drawn over a `.regularMaterial` backdrop tinted with `chromeBackground`.
When it is off the cards paint the theme's exact tinted window color (`background`) and the chrome around them `chromeBackground`, and `CarrierTerminalStore` live-reloads changes to `UserDefaults`, system appearance and `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
Theme, color scheme, cursor style, typography, padding, minimum contrast, inactive-pane dimming, hover-to-focus splits, copy on select and running-process close confirmation apply immediately in **Settings › Terminal** (`Carrier/Features/Terminal/TerminalTabView.swift`), while scrollback limit, Option-as-Alt mapping and bottom Zsh prompt pinning apply to newly opened panes and shells.
When a tab is split, `TerminalPaneHostView` dims unfocused panes when `dimInactivePanes` is enabled and moves active Ghostty focus under the pointer when `focusFollowsMouse` is enabled.

## Session terminal drawer

Open chat sessions show a terminal glass icon (`terminal`, `terminal.fill` while the drawer is open) in the toolbar, with no words (`ToolbarGlassIconButton`, `Carrier/Features/Epics/PanelToolbar.swift`).
Toggling it opens or hides `TerminalDrawerView` under `ConversationView`, persisted in `WindowShell.terminalDrawerOwners` for the window session and sized by `AppPreferences.terminalDrawerHeightKey` (`"terminal.drawerHeight"`), which is written when the edge is released and not at every tick of the drag (the drawer is drawn from a local height meanwhile).
The drawer starts a `TerminalOwner.session` tab in the session's folder on first open, reuses the shared bottom-tab chrome with a collapse chevron on the right and collapses automatically when its last tab closes.
Archiving or deleting a session closes and prunes its terminal tabs (`SessionActions`, `ChatSessionsPoller`).

## Epic Continue in Terminal drawer

When an epic run exposes a validated resume descriptor in `SessionSectionsView`, clicking **Continue in Terminal** opens `TerminalDrawerView` beneath `EpicView` for `TerminalOwner.epic(repo:issue:)`.
Instead of launching an external terminal app, `embeddedResumeLaunch(_:)` validates folder accessibility (`isAccessibleTerminalDirectory`) and runs a fail-closed `cd` plus the interactive login shell command with inline `CLAUDE_CONFIG_DIR` or `CODEX_HOME` overrides inside the epic's working tree.
Re-clicking **Continue in Terminal** for an already open session focuses the existing tab and pane instead of spawning a duplicate session.
When the resumed agent process exits cleanly, its pane closes automatically and collapses the drawer when no tabs remain.
If opening the directory fails or the agent exits non-zero, the pane holds open until you press Return so the error stays visible.
Clicking the drawer's close (`×`) button closes its epic tabs with running-process confirmation when enabled.
Control returns to Carrier when the person explicitly triggers **Resume** in `EpicView`, and starting a run closes open epic drawer tabs so two writers cannot collide.

## Bottom-anchored Zsh prompt and Clear

When `TerminalSettings.pinPromptToBottom` (`AppPreferences.terminalPinPromptToBottomKey`, opt-in and off by default) is enabled for an interactive Zsh shell with no explicit command override, `CarrierTerminalStore` sets `ZDOTDIR` in the child environment (`resolvedEnvVars`) to `<Carrier folder>/app/cache/zsh-bottom-prompt` without altering stored pane metadata (`TerminalZshBottomPromptShim`).
The shim preserves any user `ZDOTDIR` in `CARRIER_USER_ZDOTDIR`, sources the user's `.zshenv`, `.zprofile`, `.zshrc` and `.zlogin` in order, preserves `~/.zsh_history` unless overridden by user dotfiles, wraps output positioning in synchronized updates (`\e[?2026h...\e[?2026l`), clears the initial login banner before user prompts draw, wraps `clear` only if the user has not defined a custom `clear` function or alias, and attaches a `precmd` hook (`\e[999B`) plus ZLE `clear-screen` overrides so the prompt stays anchored at the bottom row while command output scrolls upward.
Pressing `⌘K` while a terminal pane has focus runs `CarrierTerminalStore.clearScrollback(paneId:)`, which executes `clear_screen` and sends `Ctrl+L` afterwards only when bottom-prompt pinning is active and process inspection confirms without error that no foreground command is running in that pane.

## Persistence

Workspace layout, tab order and split trees are persisted in `<Carrier folder>/app/state/terminals.json` (`0600`) without environment variables (`TerminalWorkspaceFileStore`).
Ephemeral `TerminalOwner.epic` tabs are excluded from both persistence export and restore so resumed CLI processes and their scoped environment variables never respawn across app launches.

## Where it lives in the code

What the person sees: [terminal](terminal.md).
Pure rules (`Terminal{Core,SplitTree,Persistence,Settings,ZshBottomPromptShim}.swift`) are in `CarrierCore` (`TerminalCoreTests`, `TerminalZshBottomPromptShimTests`); Continue in Terminal's launch is `ContinueInTerminal.swift` (`embeddedResumeLaunch`), and the sentences of the close confirmations are `TerminalConfirmationCopy.swift` (`terminalConfirmationQuestion`), in `CarrierCore` too.
The AppKit runtime (`Carrier/Platform/Terminal{Host,Store*,Appearance,ProcessInspector}.swift`, `CarrierTerminalView.swift`) owns the `paneId`-keyed `GhosttyKit` surface cache, live settings reload, `ZDOTDIR` bottom-prompt preparation, `⌘K` scrollback clear and close confirmation; the views are the `Terminal…View` files of `Carrier/Features/Terminal`, `MainMenu.swift`, `PanelView.swift` and friends.
Window selection and drawer state: `CarrierCore/Shell/WindowShell.swift` (`WindowShellTests`).
`libghostty-spm` (`GhosttyTerminal`) is linked by `Carrier` only; `build-app.sh` and `scripts/check-app.sh` bundle and verify `GhosttyKit_GhosttyTerminal.bundle` and `THIRD-PARTY-NOTICES.md`.

The words of the whole area are copy keys (`terminal*` in `design/copy/`): the workspace, its tabs and bar, the terminals home, the confirmations and the Terminal page of Settings; the preview of that page prints a mock terminal's own text (a prompt, a command, a test run), which is not the app's words and stays as it is. A property that said words (`TerminalTab.title`, `TerminalPane.displayTitle`, `TerminalSettings`' option titles) is a method taking `bundle` and `locale`, `TerminalPane.untitled` is the name a pane is stored under (state, not words), and the two sentences Continue in Terminal's shell prints when the agent fails are keys too. `TerminalSpanishTests` renders each function that builds a sentence in Spanish, with every plural and select.
