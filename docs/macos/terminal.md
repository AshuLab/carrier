# Terminal

The embedded Ghostty terminal in `Carrier.app`: standalone terminals in the sidebar, split panes, the session drawer and the bottom-anchored Zsh prompt.

## Standalone terminals

The sidebar's `Terminal` section (`Carrier/TerminalSidebarView.swift`, `TerminalRows`) lists each standalone terminal instance (`TerminalOwner.terminal`), separate from chat sessions.
Each standalone terminal keeps its own ordered list of tabs, active tab and split panes.
Clicking `+` in the section header, "New Terminal Session" in the empty state (`EmptyState.noTerminals`) or "New Terminal" in the toolbar creates a new standalone terminal rooted at the home folder.
When the `Terminal` section is unfolded and has at least one terminal, clicking its magnifier or pressing `⌘F` opens the sidebar's search field (`TerminalRows`).
When `Terminal` itself is selected (`Selection.terminals`), `TerminalsHomeView` lists the open standalone terminals with toolbar Search and `+ New Terminal`.
Closing a standalone terminal from its hover `×`, middle-click (`onMiddleClick`) or context menu asks first when running foreground processes are detected and `confirmCloseRunningProcess` is on (`CarrierTerminalStore.closeAll`), then selects the next open standalone terminal or falls back to the overview.

## Workspace, tabs and splits

Selecting a standalone terminal (`Selection.terminal(id:)`) shows `TerminalDetailView` (`Carrier/TerminalWorkspaceView.swift`).
The terminal surface extends under the translucent top toolbar across the full detail height, while top-right pane controls are inset below `safeAreaInsets.top` (`topControlsInset`) so they stay clear of toolbar buttons.
The tab strip (`Carrier/TerminalTabBarView.swift`, `TerminalTabBarView`) sits along the bottom edge with drag reordering, inline rename popovers, a pinned `+` button to add a tab in the active tab's folder, Close Tab / Close Other Tabs in the context menu and middle-click or `×` to close a tab.
Hovering near the top of a pane reveals floating glass controls (`TerminalPaneHeaderView`) to split right, split down, zoom or restore a split pane, drag a pane to another pane's edge to move it or center to swap (`terminalDropZone`), equalize splits or detach a pane into a new tab.
All split, zoom, equalize, detach and close actions are also available via the menu bar (`Terminal` menu, `TerminalMenuControls`), keyboard shortcuts (`⌘D`, `⌘⇧D`, `⌘⇧↩`, `⌘⇧W`) and pane accessibility actions.
Split dividers (`SplitContainerView`) and the drawer's top edge (`TerminalDrawerView`) share `TerminalResizeDivider`, resize by drag or accessibility adjustment with `AppKit` resize cursors managed by `hoverCursor`, and highlight using `Color.themeAccent`.

## Appearance and theme alignment

The embedded terminal follows the app's active `Theme`, Light/Dark scheme, `AccentColor`, `Tint` (`off`, `subtle`, `strong`) and **Translucent windows** accessibility-aware preference (`TerminalAppearanceProfile`, `TerminalAppearanceMapper`).
Each of the 9 themes (`carrier`, `graphite`, `ocean`, `forest`, `sunset`, `paper`, `rose`, `lavender`, `midnight`) provides a curated 16-color ANSI palette in both light and dark modes alongside high-contrast foreground, `boldColor`, accent-tinted selection colors, `cursorColor` and `cursorText`.
When the active theme is `carrier` and **Translucent windows** is active (with system Reduce Transparency off), the Ghostty surface uses `backgroundOpacity = 0` over the window's translucent frosted background and draws `TerminalDrawerView` over a `.regularMaterial` backdrop tinted with `chromeBackground`.
Opaque themes paint the theme's exact tinted window color (`background`) inside both the surface and chrome without double-tinting the tab bar, and `CarrierTerminalStore` live-reloads changes to `UserDefaults`, system appearance and `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
Theme, color scheme, cursor style, typography, padding, minimum contrast, inactive-pane dimming, hover-to-focus splits, copy on select and running-process close confirmation apply immediately in **Settings › Terminal** (`Carrier/TerminalTabView.swift`), while scrollback limit, Option-as-Alt mapping and bottom Zsh prompt pinning apply to newly opened panes and shells.
When a tab is split, `TerminalPaneHostView` dims unfocused panes when `dimInactivePanes` is enabled and moves active Ghostty focus under the pointer when `focusFollowsMouse` is enabled.

## Session terminal drawer

Open chat sessions show a Show Terminal / Hide Terminal glass pill in the toolbar (`PanelView.swift`).
Toggling it opens or hides `TerminalDrawerView` under `ConversationView`, persisted in `WindowShell.terminalDrawerOwners` for the window session and sized by `AppPreferences.terminalDrawerHeightKey` (`"terminal.drawerHeight"`).
The drawer starts a `TerminalOwner.session` tab in the session's folder on first open, reuses the shared bottom-tab chrome with a collapse chevron on the right and collapses automatically when its last tab closes.
Archiving or deleting a session closes and prunes its terminal tabs (`SessionActions`, `ChatSessionsPoller`).

## Epic Continue in Terminal drawer

When an epic run exposes a validated resume descriptor in `SessionSectionsView`, clicking **Continue in Terminal** opens `TerminalDrawerView` beneath `EpicView` for `TerminalOwner.epic(repo:issue:)`.
Instead of launching an external terminal app, `embeddedResumeLaunch(_:)` validates folder accessibility (`isAccessibleTerminalDirectory`) and runs a fail-closed `cd` plus the interactive login shell command inside the epic's working tree with any scoped `CLAUDE_CONFIG_DIR` or `CODEX_HOME` environment variables.
When the resumed agent process exits cleanly, its pane closes automatically and collapses the drawer when no tabs remain.
If opening the directory fails or the agent exits non-zero, the pane holds open until you press Return so the error stays visible.
Clicking the drawer's close (`×`) button closes its epic tabs with running-process confirmation when enabled.
Control returns to Carrier only when you explicitly trigger the epic's **Resume** action.

## Bottom-anchored Zsh prompt and Clear

When `TerminalSettings.pinPromptToBottom` (`AppPreferences.terminalPinPromptToBottomKey`, opt-in and off by default) is enabled for an interactive Zsh shell with no explicit command override, `CarrierTerminalStore` sets `ZDOTDIR` in the child environment (`resolvedEnvVars`) to `<Carrier folder>/app/terminal/zsh-bottom-prompt` without altering stored pane metadata (`TerminalZshBottomPromptShim`).
The shim preserves any user `ZDOTDIR` in `CARRIER_USER_ZDOTDIR`, sources the user's `.zshenv`, `.zprofile`, `.zshrc` and `.zlogin` in order, wraps output positioning in synchronized updates (`\e[?2026h...\e[?2026l`), clears the initial login banner before user prompts draw, wraps `clear` only if the user has not defined a custom `clear` function and attaches a `precmd` hook (`\e[999B`) plus ZLE `clear-screen` overrides so the prompt stays anchored at the bottom row while command output scrolls upward.
Pressing `⌘K` while a terminal pane has focus runs `CarrierTerminalStore.clearScrollback(paneId:)`, which executes `clear_screen` and sends `Ctrl+L` afterwards only when bottom-prompt pinning is active and process inspection confirms without error that no foreground command is running in that pane.

## Persistence

Workspace layout, tab order and split trees are persisted in `<Carrier folder>/app/terminals.json` (`0600`) without environment variables (`TerminalWorkspaceFileStore`).
Ephemeral `TerminalOwner.epic` tabs are excluded from both persistence export and restore so resumed CLI processes and their scoped environment variables never respawn across app launches.
