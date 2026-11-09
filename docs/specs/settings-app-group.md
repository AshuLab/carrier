# Settings has a base and an App group

Status: spec

Source: AshuLab/carrier#677

## Problem

Settings today is a flat rail of six pages (Engine, Behavior, Repos, Sessions, Notifications, Health) that mix three kinds of settings the person cannot tell apart: what the app does on this Mac, what the engine does (`config.json`) and what the chat does (`chat.json`). There is no home for the preferences of the app itself: the menu bar icon, the confirmation before stopping Carrier, the look of the app, what the sidebar shows, how the message box and the conversation behave and the shortcuts live in the menu, are fixed in code or do not exist.

The person who feels it is whoever uses the app every day, and whoever sets Carrier up later: the setup wizard and the pages for providers, models, identities and repos need a Settings whose shape is already clear, or each of them invents its own.

We know it is solved when Settings shows the three kinds apart, when every preference of the app has a page where a person looks for it first, and when the next epic (the Carrier and Chat pages) can add its pages to the rail without redesigning it.

## Solution

The Settings sheet keeps its shape, a rail on the left and a page on the right, and the rail gets groups (the glossary's Settings group): App first and without a heading, then groups with a heading. This epic ships the App group and a Legacy group; the Carrier and Chat groups, with their pages, come in the next epic, which takes the pages in Legacy and designs them. Three arrangements were weighed in a prototype (`docs/research/macos-app-design/explorations/settings-groups-options.html`): one rail with every page and headed groups, a switch of group on top of a short rail, and a rail of three rows with one long page each. The first won: every page is one click away and the rail reads as a table of contents.

The Legacy group holds Engine (the paths of `carrier` and `node`, and "Start Carrier when the app opens"), Behavior, Repos, Sessions and Health exactly as they are, so nothing the person can do today is lost while the groups are built. Each of them leaves Legacy when the next epic redesigns it into its group.

Every page follows one pattern, and the next epic reuses it: a header with an icon, a title and a line; cards of rows, each row a title and a line on the left and its control on the right, under a small uppercase title; a live preview wherever a control changes how something reads; a Reset at the bottom of the pages with many controls. A page does not say where it is saved and does not mark what is new. The settings of the App group are the app's preferences and apply as soon as they change, with no Save button. Every control works: a control that does nothing does not ship.

The App group has six pages.

General has three blocks. Menu bar: the icon style, whether the icon animates and whether the menu lists epics, which exist today as preferences with no page. Display: how times read everywhere in the app, relative ("11m") or as a clock time ("14:32"), and the clock (system, 12 or 24 hours); today ages and clock times are formatted in many places, all 24-hour, so they go through one formatter. Confirmations: ask before stopping Carrier when it would interrupt epics, which exists today as a preference nothing writes. The Carrier folder and About are not here.

Notifications keeps what exists (Needs attention, Ready for test, A problem; only when the app is not in front; the system permission with Open System Settings and Send a test) and renames "Needs you" to Needs attention in Settings and in the menu bar. It adds a Chat block, a Dock badge, a sound, reminders and quiet hours.

The Chat block has Needs attention (a session waits for an approval; a question of the agent has no event of its own, so an approval is the only case) and Done (a turn ended), the first on and the second off. Chat sessions notify today never: their states exist and nothing reads them while the window is closed, so the list of sessions is polled for the life of the app, as the engine's monitor already is, and a change from working to waiting, or from working to idle, is what notifies. The Dock badge is the number of epics that need a person plus the sessions waiting for an approval, and disappears at zero. The sound plays with each banner. A reminder notifies again at an interval (never, after 15 minutes, after an hour) while something still needs attention; it covers the Needs attention of epics and of sessions and never Ready for test or Done; the app is a regular app that stays alive with its window closed, so a timer inside the app is enough.

Quiet hours has a switch, a start and an end, and may cross midnight. During them a notification is kept and not lost: it is posted with no banner and no sound, so it waits in the Notification Center, and the Dock badge is not affected. Quiet hours overlap with the system's Focus modes, which silence the same way for the whole Mac; they are here because the person asked for them, and they are independent of Focus.

Appearance has the color scheme (system, light, dark); a theme, from a gallery of six, each with a light and a dark version, of which the color scheme picks the one shown (Carrier, Graphite, Ocean, Forest, Sunset, Paper); the accent color (the theme's own, or one of seven); a tint of the accent on the windows (off, subtle, strong); the text size of the whole interface (90 to 130 percent); the density (compact or comfortable, in the sidebar rows and the space between messages); and translucent windows (off draws solid backgrounds; by default it follows the system's Reduce transparency). For the chat and terminal it has a monospace font from the installed families, its size, the line height (tight, normal, loose), ligatures, wrapping of long lines and line numbers, with a preview. It has a setting to tell the states apart by shape, a symbol in each state so that color is not the only clue, and the width of a message (narrow, medium, wide). The interface font stays the system's: changing it breaks spacing and alignment, and only its size is chosen.

The text size is the reason for a central type scale. Today about 135 places set a font size by hand (the sidebar's metrics, the message box, the transcript and the terminal blocks) and nothing multiplies them. This epic puts every interface size behind one scale that the text size setting multiplies, and the monospace font, size and line height of the chat and terminal are their own settings that the transcript, the tool output, the approvals and the agent output window read. A size set by hand outside the scale is a bug after this epic.

Sidebar has what the Sessions section shows: how it is grouped (by state or by project), how it is sorted inside a group (workspace, age, status), four switches for what each row shows (the project icon, the branch, the providers, the age) with a preview, and how the Archive is sorted (date archived, project). The grouping and the sorts are the values the sidebar's own menu already changes and remembers; the page and the menu are two controls of one preference.

Chat has the message box and the conversation. Message box: the key that sends (Return or ⌘Return, the other makes a new line); what sending does while the agent works (queue the message, as the box does today, or interrupt the turn and send); Writing Tools, off; check spelling; correct spelling automatically, off. Interrupting is the app's: it stops the turn through the host's existing `interrupt`, which answers only when the turn has really ended, and then delivers the message; the host needs no change. Conversation: what the agent's tools show (hidden, collapsed, expanded); whether a call that failed unfolds by itself even when the rest are folded; how an edit reads (unified or split); how many lines of a command's output show before Show more (20, 50, 100); whether the agent's reasoning shows folded under its message; whether the conversation follows new output; whether messages show their time (never, on hover, always, in the General format). Sessions: ask before deleting a session. The sidebar's own menu and the message box keep working as they do; this page sets their defaults.

The reasoning is the one piece of the Chat page that needs the host. Today the providers' thinking is dropped: the Claude adapter keeps only text and tool blocks and the Codex adapter only messages and commands, the chat's event type has no kind for it and the conversation shows a fixed "Thinking…" label. The epic adds a `reasoning` event kind to the chat host (the event type, its schema and database, the two adapters mapping the thinking blocks and reasoning items), the app decodes it into a row of the conversation, and the setting shows it folded under its message or leaves it out. The host and the app are told apart by capabilities, as the other optional requests are, so an older host keeps working and shows no reasoning.

Keybindings lists the shortcuts in four groups: Go to (Home ⌘1, Sessions ⌘2, Carrier ⌘3, Archive ⌘4), Sessions (new session ⌘N, search ⌘F, next ⌘], previous ⌘[, archive the session ⇧⌘A), Conversation (focus the message box ⌘L, stop the agent ⌘., jump to the latest message ⌘↓, fold or unfold the tool calls ⌥⌘E, copy the last answer ⇧⌘C) and Carrier (start or stop, pause or resume, look for ready epics now, with no shortcut by default). A shortcut is changed by clicking it and pressing the new keys, which need ⌘, ⌃ or ⌥; Esc cancels, Delete clears it; a shortcut already taken by another action is flagged with that action's name; each row can go back to its default and a Reset restores all. Only ⌘1, ⌘2, ⌘3, ⌘N and ⌘F exist today, so the rest are commands this epic adds. Today the keys are held in two places that repeat each other, the menu built in AppKit and a key monitor that asks one pure function; they become one table of actions with their default keys and the person's own, which the menu and the monitor both read, and the menu is rebuilt when a key changes.

Cut on purpose. A theme editor of the person's own, importing and exporting themes, and a different interface font: a lot of work before the base is good. A summary notification in place of many and a mute per repo: nothing says they are needed. Pasting a long text as a folded block and the height of the message box: a fixed value solves them. Naming a session from its first message as a setting: the host already does it, and it is solved another way. The Carrier folder and About in General, and the Window shortcuts (sidebar, inspector) and the Settings shortcut in Keybindings: the system and the menu already cover them. The epic card on hover and the free slots, which the Carrier sidebar shows: they go to the Carrier page of the next epic if they are wanted.

## Scope

1. The Settings rail shows the App group first, with no heading, and the Legacy group with its heading; a page of the rail opens in one click, and Done and the readiness banner behave as they do today.
2. Legacy holds Engine, Behavior, Repos, Sessions and Health as they are today, with the same controls and the same saving.
3. Every page of the App group has a header, cards of rows, and a Reset where the page has many controls; none says where it is saved and none marks what is new.
4. A change in any App page applies at once and survives a relaunch; Reset on a page restores its defaults and only its.
5. General: the person chooses the menu bar icon style, whether it animates and whether the menu lists epics, and the menu bar follows at once.
6. General: the person chooses whether times read relative or as a clock time and, for clock times, system, 12 or 24 hours; every age and every clock time in the app follows.
7. General: the person switches off the question before stopping Carrier, and stopping does not ask while it is off; while it is on it asks only when epics would be interrupted.
8. Notifications: the person chooses, for Carrier and for Chat separately, which events notify; "Needs you" reads Needs attention in Settings and in the menu bar.
9. Notifications: a chat session that goes from working to waiting for an approval, or from working to idle, notifies as Needs attention or as Done according to the switches, with the window closed or the session not open.
10. Notifications: the Dock icon shows the number of epics that need a person plus the sessions waiting for an approval, and no badge at zero, whether the switch is on or the app is in front.
11. Notifications: the sound plays with a banner only when the sound switch is on.
12. Notifications: while an epic or a session still needs attention, a reminder notifies again at the chosen interval; with Never none does; Ready for test and Done never remind.
13. Notifications: between the quiet hours' start and end, including across midnight, a notification is posted with no banner and no sound and waits in the Notification Center, and the Dock badge still counts.
14. Notifications: "only when the app is not in front", the system permission, Open System Settings and Send a test keep working as they do.
15. Appearance: the color scheme (system, light, dark) sets the appearance of every window of the app; system follows the Mac.
16. Appearance: choosing a theme changes the colors of the windows and the sidebar, in its light or dark version according to the color scheme.
17. Appearance: the accent color (the theme's own or one of seven) colors the controls and the selection, and the tint (off, subtle, strong) colors the backgrounds.
18. Appearance: translucent windows off draws solid backgrounds, and by default the app follows the system's Reduce transparency.
19. Appearance: the text size from 90 to 130 percent scales every text of the interface, and no text is left at a size set by hand outside the scale.
20. Appearance: the density (compact, comfortable) changes the height of the sidebar rows and the space between messages.
21. Appearance: the monospace font, its size, the line height, the ligatures, the wrapping of long lines and the line numbers apply to the transcript, the tool output, the approvals and the agent output window, with a preview in the page.
22. Appearance: telling the states apart by shape adds a symbol to each state wherever a state is drawn by color alone.
23. Appearance: the width of a message (narrow, medium, wide) limits how wide an answer gets before it wraps.
24. Sidebar: the person chooses how Sessions is grouped and sorted and how the Archive is sorted, and the sidebar's own menu shows and changes the same values.
25. Sidebar: the switches for the project icon, the branch, the providers and the age show and hide them on every session row, with a preview in the page.
26. Chat: the key that sends is Return or ⌘Return and the other makes a new line, in the message box of every session and of the new session draft.
27. Chat: with Interrupt chosen, sending while the agent answers stops the turn and delivers the message once the turn has ended; with Queue it holds the message and sends it when the turn ends, as today.
28. Chat: Writing Tools, check spelling and correct spelling automatically apply to the message box.
29. Chat: tool output hidden, collapsed or expanded, a failed call that unfolds by itself, the diff style, the output length with Show more, and following new output apply to every conversation.
30. Chat: with Show reasoning on, the agent's reasoning shows folded under its message, for Claude and for Codex; off, or with a host that does not send it, nothing shows.
31. Chat: message times show never, on hover or always, in the General format.
32. Chat: with the confirmation on, deleting a session asks first, and says its worktree goes with it.
33. Keybindings: each action of the four groups has its default shortcut, and the menu and the keyboard run the same action from the same table.
34. Keybindings: clicking a shortcut records the next combination that has ⌘, ⌃ or ⌥, Esc cancels, Delete clears it, and the new shortcut works at once and after a relaunch.
35. Keybindings: a shortcut taken by another action is flagged with that action's name, a row goes back to its default, and Reset restores all.
36. The actions that did not exist (Archive as a destination, next and previous session, archive the session, focus the message box, jump to the latest message, fold or unfold the tool calls, copy the last answer, start or stop Carrier, pause or resume it, look for ready epics now) run from their shortcut and from the menu.

## Decisions

The groups and the pages are values: a `SettingsPage` carries its group and its row of the rail, the rail is built from the pages, and Legacy holds exactly the five pages that exist today. The sheet reads them and draws.

The App group's preferences live in one store over an injected `UserDefaults`, each with its default and a fallback when a saved value is bad, in the way `MenuBarStore` and `SidebarStore` already are; the keys that exist (`menu.iconStyle`, `menu.animate`, `menu.showEpics`, `stop.confirm`, the `sidebar.*` ones and the `notify.*` ones) keep their names so nothing a person set is lost, and no migration is written. Reset removes the keys of one page.

Times go through one formatter in `CarrierCore` that takes a date, a reference date and the format preference and returns the text; the age helper, the epic's duration lines and the three places that build "HH:mm" call it.

The type scale is one value in `CarrierCore` that turns a base size into the scaled one, and a small set of font helpers in the app that every view uses instead of `.font(.system(size:))`; the sidebar's metrics and the message box read it. The monospace settings are a second value (family, size, line height, ligatures, wrapping, line numbers) read by the views that draw code.

The theme is a pure value: for a theme, a scheme and a transparency preference it gives the surface colors and the accent. The accent and the surfaces the app draws itself are colored; the system's own chrome (title bar, menus, system sheets and popovers) is not, and the spec does not promise it.

The notification decisions stay pure: a function that, from the previous and the current snapshot of the engine and of the chat sessions and from the preferences, says which notifications to post and how (banner, quiet, no sound); a function that says whether a moment is inside the quiet hours; a function that says which reminders are due from what still needs attention, when each last notified and the interval. The Dock badge count is a pure function of the same two snapshots. Posting, the timer and the badge are the app's thin layer over them. Quiet delivery is posting with the passive interruption level and no sound; whether macOS then shows no banner is checked by hand on the first slice that posts, because a test cannot see it.

The session list that the sidebar polls is also what the notifications read, and it is polled for the life of the app, started with the engine's monitor and not with the window.

Interrupt is the app's `stop()` followed by delivering the message once the host reports the session idle; the host's `interrupt` already answers only after the adapter ended the turn. The race to cover is a late `turn_end` of the stopped turn arriving after the next turn started.

Reasoning is a new `reasoning` kind of `ChatEvent` in the host, with its schema and migration, mapped from the Claude thinking blocks and the Codex reasoning items, listed in the host's capabilities; the app decodes it into a conversation row that is folded by default.

The shortcuts are one table in `CarrierCore`: an action id, its title, its default combination and the person's own, with the validation of a recorded combination and the detection of a clash; `shortcutAction` reads the table, the menu is built from it and rebuilt when it changes, and the message box's own keys (send, new line, the command list) stay where they are and read the preference for the send key.

Testing seams, story by story. The seams are the ones the macOS tests already use: pure values and stores in `CarrierCoreTests` with a `UserDefaults(suiteName:)` and fakes of the ports, and views and controllers in `CarrierTests` only where a view is the behavior.

Stories 1 to 4: the rail and the store, in `CarrierCoreTests` (the pages of each group, the five of Legacy, defaults, persistence across a new store on the same suite, a bad value falling back, Reset of one page); the sheet itself has one view test that the rail shows the groups.
Stories 5 to 7: the store for the menu bar and the confirmation, extending the `MenuBarStoreTests` seam, and the formatter in its own test file (relative and clock, 12 and 24 hours, system).
Stories 8 to 14: the pure notification functions in `NotificationsTests` with the `NotificationCentre` fake, including the chat diff from a fake session list, the quiet hours across midnight, the reminders due and the badge count; the posting and the badge are checked by hand on the first slice.
Stories 15 to 18: the pure theme value (a scheme and a theme give a variant, the accent override, the tint, solid when transparency is off); applying it to the windows is checked by hand and by the prototype in the open question.
Story 19: the type scale in `CarrierCoreTests` (a size and a text size give the scaled size, bounds), plus a check in the test suite that no view sets a font size by hand outside the helpers, so a new one fails the build.
Stories 20 to 23: the preferences as values in `CarrierCoreTests`; the row builders that already take display flags (`Sidebar`, the transcript flow) get a case for each flag; the monospace settings reach `CommandStyle` and the transcript views, with one view test in `CarrierTests` that the font and size change.
Stories 24 and 25: `SidebarTests` and `SidebarStore` tests for the grouping, the sorts and the row flags.
Stories 26 to 28: `CommandTextViewTests` in `CarrierTests` for the send key and the new line; `ChatSendTests` and `ChatConversationTests` with the fake host for Queue and Interrupt, including the late `turn_end` race.
Stories 29, 31 and 32: `ChatToolGroups` and `TranscriptFlow` tests for the tool output modes, the failed call, the output length and the split diff (the diff lines as a split pair are a pure function); the confirmation in the session delete flow.
Story 30: the host side in vitest (`claude.test.ts`, `codex.test.ts`, `sessions.test.ts`, the schema and migration test), the event decoding and the folded row in `ChatConversationTests`, and a gated integration test against the real providers if their variables are set.
Stories 33 to 36: the shortcut table in `CarrierCoreTests` (defaults, record validation, clash, reset, `shortcutAction` reading the table) and a test in `CarrierTests` that the menu's items carry the table's keys and change when it changes; each new action has its case where its behavior lives.

## Out of scope

The Carrier and Chat groups and their pages: providers, models, identities, agents per role, failover, the chat's agents and projects folder, and the redesign of Repos, Behavior and Sessions. How the engine's `config.json` and the chat's `chat.json` are written from the app, including who creates the first config: the setup wizard (E4) comes after the Carrier group and is parked with its decisions. Where Health and the paths of `carrier` and `node` end up: they stay in Legacy until then. The code colors, the highlighting of code blocks: the app has no syntax highlighter today, so a setting for the colors would color nothing; it comes back when the app has one. Replacing the system's own chrome (title bar, menus, system sheets and popovers), which an app cannot theme.

## Open questions

How far a theme and the accent reach. The accent and the surfaces the app draws itself can be colored, but how the Liquid Glass buttons, the sidebar's selection and the sheets take a tint has to be tried in the app before the gallery is built, because the HTML prototype cannot show it. A small SwiftUI prototype settles it, and what it cannot do changes what a theme is. It is the first thing the Appearance slices do.
