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

The update has no window: a glass pill in the sidebar's title bar, after the window's buttons (`UpdatePill.swift`), is all of it, drawn from `UpdateFlow` (`CarrierCore/UpdateFlow.swift`, tested in `UpdateFlowTests`), which Sparkle's user driver of our own (`UpdateDriver` in `AppUpdater.swift`) moves.
When a check finds a version the pill slides in with `↓ X.Y.Z`; a click downloads it in place, the version rolling to the percent while the chat's thinking glow runs round the edge; done, a tick says Ready and it rolls to `Restart`, whose words shimmer; a click installs and relaunches (`Restarting…`).
A failed download leaves `Retry`, which checks again and downloads what it finds.
A check the person asks for (Settings > Updates, Check for Updates… in the menu) that finds an update shows it in the pill too; one that finds nothing, or fails before any download, says so in an alert.
While the sidebar is hidden the pill is not shown; with Reduce Motion the glow, the shimmer and the bounce stop and the words still tell the state.
`--fixture-update` plays the whole course with a made-up version.

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

An epic stopped in needs-human shows a notice as the last element of its Agent output tab, after the sessions (or the empty or starting state), in the same 700 pt column (`CarrierCore/Resume.swift` builds it from the stuck kind, `Carrier/ResumeCardView.swift` draws it as a `NoticeCard`): the reason as the title, one line of what resuming does for that kind, with a thin edge orange when a person's input is needed and red when something failed. The pipeline above does not say why a step stopped; the notice does.
It has a Resume button only when the engine's hello lists `resumeEpic` (`EpicStore.canResume`, read from the connection the epic poller uses); against any other engine the card shows the reason and the words with no button.
Resume opens a sheet saying what will happen; confirming sends `resumeEpic` with the epic's repository and number on a connection of its own (the engine answers when the epic has started, up to 30 seconds), the button reads "Resuming…" until then and until the snapshot shows the epic out of needs-human, or stopped again after the answer (kept in `EpicStore.resuming`, so selecting another epic and coming back does not lose it), and a refusal (`unknown epic`, `not stopped`, `github unavailable`, `did not restart`) is shown in words, in orange, under the notice's line.

## Starting

A running epic in its ship stage whose Agent output tab has no sessions yet (`isStarting`) shows `StartingView`: a card with three steps, Epic queued, Preparing the workspace (Workspace ready once the engine reports a worktree) and First agent starts (`startingSteps`, `CarrierCore/StartingSteps.swift`). Each has a line with what the snapshot knows and leaves out what it does not: the wait for a slot (`queuedAt` to `startedAt`), the branch from the epic reply ("Branch …", then "Worktree on …" once there is one) and "Its output appears here". The clock at the right is the time the epic started on the first step and how long the workspace step has been going on the second, ticking once a second.

## Slices and findings in an epic's log

In the builder's session the epic's slices are one glass card, "Slices", with how many are merged, a mini progress and the time, and a row per slice: its state, `#730` and title, a quiet line (calls, edits, test runs, errors, the lane when slices ran in parallel, when it ran) and its pull request with a dot for its state (merged, open, draft), which opens GitHub. A row opens to what that subagent did; the first one is open while it works. A slice that has not started is a row that says what it waits for. In a reviewer's session a second card shows the review's verdict ("Ready", "Changes requested"), its blockers first and then its suggestions, each with its id, a line, whether it is new, carried (still open) or fixed (verified by the next round, dimmed) and a link to the discussion on GitHub; the fixer's session shows the same round's blockers with the ones the next review verified marked fixed. How they are drawn is in [the look of the app](../macos-ui.md#cards-in-the-feed).

## Agent output

An epic's Agent output tab lists its sessions oldest first, the newest last, as centered rows with no card (how they are drawn is in [the UI guide](../macos-ui.md#the-session-row-of-the-agent-output); the words are `sessionRowText`, `sessionSummary` and `earlierSessions` in `CarrierCore/SessionSections.swift`).
A row says who acted (the GitHub profile, an Agent Forge bot, or the tool's name when none is known), the role and place ("Builder · Ship", "Reviewer · Round 2"), and on a second line the tool, the account, the model and the effort that are known. The profile is the `profile` of the engine's `sessions` reply when it sends one; an engine that does not is read from `config.json` when the tab opens: the Forge bot of `agents.author` (builder and fixer) or `agents.reviewer`, and the role's `effort` when the session ran on the role's model. A `gh` profile has no name in the file, so such a session shows the tool's name (a repository's own `agents` override is not read).
Under the row one line sums the session up: while it runs "Working · since 16:09 · 62 calls"; stopped, the orange `stopped` badge and the failure's kind and detail; open, the counts (calls, edits with their lines, test runs, errors, time); folded, how it ended in bold (Completed, Changes requested, Needs a human), the CI verdict and the time, or the counts when it has no result.
The whole row is the one button that folds the session (the newest and a running or stopped one start open); there are no pinned headers.
Above five sessions the oldest ones are one row ("3 earlier sessions · Builder, Reviewer, Fixer · 45m") that opens them.

## File icons

`fileIcon(path)` (`CarrierCore/FileIcons.swift`) is the one place that picks a file's icon: a bundled SVG from Material Icon Theme (MIT) for the languages in `bundledIconName`, else the category's SF Symbol.
