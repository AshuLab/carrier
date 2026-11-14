# The app shell

How `Carrier.app` sits on the Mac: the Dock, the menu bar item, the window and its sidebar, an epic's resume card and file icons.

## Dock and menu bar

`Carrier.app` is an app of the Dock: it has its icon there (`Resources/AppIcon.icns`, made by `swift scripts/make-icon.swift`), opens on its window, keeps its menu bar (Carrier, File, Edit, View, Conversation, Engine, Window, Help: `MainMenu.swift`, built from the shortcut table of `CarrierCore/Shortcuts.swift`, the Edit menu being what gives ⌘C and ⌘V to a text field), remembers where its window was, stays running when the window is closed and opens it again from the Dock icon (whose menu has New Session and Open Window).
Besides, it shows one menu bar item at the right of the screen.
Its menu opens with a heading (a dot, green while running, orange when intake is paused, an epic needs you or there is a problem, grey when stopped; a bold title and the epic and slot counts), then, while Carrier runs, the epics (needs you, running, waiting, ready; at most twenty, then "… and N more") with a state glyph, a secondary line and a badge, rebuilt each time the menu opens; the Settings switch "Show epics in the menu" (user default `menu.showEpics`, on by default) turns the list off, and choosing an epic opens the window on its section.
Then only the controls that apply: while Carrier is stopped, Start Carrier (enabled only when the engine is configured and `carrier` is found, and `node` too when it is a script; it says what is missing otherwise); while it runs, Pause intake (Resume intake while paused), Check GitHub now and Stop Carrier, which asks first when epics are running, since it interrupts them (they resume on the next start), and stops straight away when none are.
Last, Open window (⌘O), Settings… (⌘,) and Quit Carrier (⌘Q).
The line comes from Carrier's control socket, `<folder>/engine/state/control.sock`, where `<folder>` is the Carrier folder: `CARRIER_HOME` from the app's own environment, else `~/.carrier`.
The app finds the engine from the folder alone, with no config file read, and has no setting for a config path; it works the folder out again at each connection attempt.
The engine's config is `<folder>/config.json`, and while that file does not exist the Carrier home and the Carrier section of the sidebar say that the engine is not configured (with nothing to do about it here: the setup wizard makes the file) and Start Carrier is off, with that as the reason.
The app asks for the snapshot every second while connected and tries to connect every three seconds while not.

## Sidebar and window shortcuts

When the updater's scheduled check finds a new version, the sidebar's title bar shows a pill after the window's buttons, `Update X.Y.Z` (`UpdatePill.swift`), instead of Sparkle's window.
Clicking it opens Sparkle's window for that update; the pill goes away once the person has looked at it, and while the sidebar is hidden it is not shown.
A check the person asks for (Settings > Updates, Check for Updates… in the menu) opens Sparkle's window as before.
`--fixture-update` shows the pill with a made-up version.

The window's sidebar is sections drawn by `SidebarSectionRow` (Home, Sessions and Carrier with its epics in the scrolling list, and, fixed in the foot, Archive above the divider and Settings with Usage directly under it): an icon, a title and its actions, no fill at rest and a light grey one when selected, drawn by the row and not by the list, so it never covers what unfolds under it.
Sessions carries a soft grey badge with the number of open sessions, every one that is not archived (`Sessions.open`, named aloud `1 open session`; not drawn with none), and its list and its search never show an archived session: a query keeps the groups of the chosen order, filtered to the sessions whose title, workspace or agent match.
Carrier's row is its title, the engine's state word (Running, Paused, Stopped, Problem or Connecting), the search and group-by actions and the slots bar at full width, with no counters and no line about the next check; a stopped engine draws the bar in grey from the total it last reported (`SidebarStore.slotsTotal`, kept between launches; none drawn while connecting or when no total was ever seen), and each epic group header shows its row count (`SidebarGroup.count`); About is an item of the menu bar item's menu.
Archive (`Carrier/ArchiveSection.swift`) shows its count (hidden with nothing archived) and a magnifier; choosing it opens it (`OpenSection.archive`, so Sessions and Carrier fold, and it is remembered like them) and moves the row up, with its archived sessions under it, grouped by the age buckets of Sessions (Today, Yesterday, Last 7 days, Older), newest first and each with `SessionRowView`, as tall as its rows up to about five and then scrolling.
`archivedGroups(_:query:now:calendar:)` (`CarrierCore/Sessions.swift`) returns only archived rows, and with a query the ones whose title, workspace or agent match, keeping the buckets; they show nowhere else in the sidebar.
A session chosen in that list keeps Archive open (the list puts it back, since selecting a session opens Sessions).
The title of every section row is a button, and so is each archived session, so Tab (with Full Keyboard Access) and Space reach and choose Archive, Settings and an archived session without a pointer; a click on the rest of the row still chooses it.
The search is one view for the sections (`Carrier/SidebarSearch.swift`): the magnifier, or ⌘F for the open section, opens a field under the row with a clear button once it has text; esc, a second click on the magnifier or emptying it closes it.
What a list says comes from `SidebarListState` (rows, empty, or no match for what was typed; `CarrierCore/Sidebar.swift`): with no match the list is replaced by the `No results` block (`EmptyState.noResults`, a magnifier with a minus as the nearest SF Symbol to a struck one, and `Nothing matches “query”`) with a Clear search button.
A section with nothing in it says so in the same shape (`SidebarEmptyBlock`): Archive with nothing archived shows `Nothing archived` (`EmptyState.nothingArchived`); Sessions with no open session shows `No sessions yet` (`EmptyState.noSessions`) and a `New session` button; unfolded Carrier with no epics shows `No epics yet` (`EmptyState.noEpics`) and that an issue labelled `solve:epic:ready` starts one.
While one is empty its count is not drawn and its magnifier is dimmed and does nothing, ⌘F included.
While the window is the key window, ⌘1 selects Home, ⌘2 the Sessions home, ⌘3 the Carrier home and ⌘F opens the search of the section that is open (Sessions, Carrier or Archive; nothing when all are folded).
The window handles them (`shortcutAction` in `CarrierCore/WindowShell.swift`, a key monitor in `WindowController`), not the menu bar item's menu, and each is in the tooltip of its row or magnifier.

The Sessions home, the Archive and a conversation are in [sessions](sessions.md); the Usage row is in [usage](usage.md).

## Resume card

An epic stopped in needs-human shows a card between its title and its tabs (`CarrierCore/Resume.swift` builds it from the stuck kind, `Carrier/ResumeCardView.swift` draws it): the reason, one line of what resuming does for that kind, orange when a person's input is needed and red when something failed.
It has a Resume button only when the engine's hello lists `resumeEpic` (`EpicStore.canResume`, read from the connection the epic poller uses); against any other engine the card shows the reason and the words with no button.
Resume opens a sheet saying what will happen; confirming sends `resumeEpic` with the epic's repository and number on a connection of its own (the engine answers when the epic has started, up to 30 seconds), the button reads "Resuming…" until then and until the snapshot shows the epic out of needs-human, or stopped again after the answer (kept in `EpicStore.resuming`, so selecting another epic and coming back does not lose it), and a refusal (`unknown epic`, `not stopped`, `github unavailable`, `did not restart`) is shown in words in the card.

## File icons

`fileIcon(path)` (`CarrierCore/FileIcons.swift`) is the one place that picks a file's icon: a bundled SVG from Material Icon Theme (MIT) for the languages in `bundledIconName`, else the category's SF Symbol.
