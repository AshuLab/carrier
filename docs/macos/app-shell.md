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
The engine's config is `<folder>/engine.json`, and while that file does not exist the Carrier home and the Carrier section of the sidebar say that the engine is not configured (with nothing to do about it here: the setup wizard makes the file) and Start Carrier is off, with that as the reason.
The app asks for the snapshot every second while connected and tries to connect every three seconds while not.

## Sidebar and window shortcuts

The update has no window: a glass pill in the sidebar's title bar, after the window's buttons (`UpdatePill.swift`), is all of it, drawn from `UpdateFlow` (`CarrierCore/UpdateFlow.swift`, tested in `UpdateFlowTests`), which Sparkle's user driver of our own (`UpdateDriver` in `AppUpdater.swift`) moves.
When a check finds a version the pill slides in with `↓ X.Y.Z`; a click downloads it in place, the version rolling to the percent while the chat's thinking glow runs round the edge; done, a tick says Ready and it rolls to `Restart`, whose words shimmer; a click installs and relaunches (`Restarting…`); if Carrier does not close (a quit that was cancelled or delayed), a click on `Restarting…` asks it to quit again, and the log says whether the app had closed (`installing the update, application terminated`).
A failed download leaves `Retry`, which checks again and downloads what it finds.
A check the person asks for (Settings > Updates, Check for Updates… in the menu) that finds an update shows it in the pill too; one that finds nothing, or fails before any download, says so in an alert.
While the sidebar is hidden the pill is not shown; with Reduce Motion the glow, the shimmer and the bounce stop and the words still tell the state.
`--fixture-update` plays the whole course with a made-up version.

The window's sidebar is a stack in a fixed order: Home, Sessions, Terminal, Carrier, then Settings and Usage under a divider.
One section is open at a time and takes all the room that is left, scrolling its own list; the sections above it are folded to their row at the top and the ones under it to their row at the foot (`SidebarView.Slot`).
With none open, Sessions and Terminal are at the top and Carrier alone at the foot.
Archive closes the panel of Sessions, under its list, and is there only while Sessions or Archive is open.
The open section's row is pinned at the top of its scroll (a `Section` header of the lazy stack, `pinnedSectionHeader`); once the list has moved under it the row gets a fill that fades out under it.
The sidebar opens at 360 points, between 260 and 800, and the width the person drags it to is kept (`SidebarStore.width`, `sidebar.width`, saved a moment after the drag settles) and is the one it opens at next time; `SidebarWidthKeeper` sets it on the split view of AppKit under the column, because the `ideal` of `navigationSplitViewColumnWidth` is not what a launch opens at.
Each section is drawn by `SidebarSectionRow`: an icon, a title and its actions, no fill at rest and a light grey one when selected, drawn by the row and not by the list, so it never covers what unfolds under it.
Sessions carries a soft grey badge with the number of open sessions, every one that is not archived (`Sessions.open`, named aloud `1 open session`; not drawn with none), and its list and its search never show an archived session: a query keeps the groups of the chosen order, filtered to the sessions whose title, workspace or agent match.
Terminal (`Carrier/TerminalSidebarView.swift`) carries a grey count badge of open standalone terminals, Search, `+` for a new standalone terminal, middle-click close on each terminal row and its own unfolded list (`OpenSection.terminal`).
Carrier's row is its title, the engine's state word (Running, Paused, Stopped, Problem or Connecting), the search and group-by actions and the slots bar at full width, with no counters and no line about the next check; a stopped engine draws the bar in grey from the total it last reported (`SidebarStore.slotsTotal`, kept between launches; none drawn while connecting or when no total was ever seen), and each epic group header shows its row count (`SidebarGroup.count`); About is an item of the menu bar item's menu.
Archive (`Carrier/ArchiveSection.swift`) shows its count (hidden with nothing archived) and a magnifier; choosing it opens it (`OpenSection.archive`, so Sessions and Carrier fold, and it is remembered like them) and moves the row up, with its archived sessions under it, grouped by the age buckets of Sessions (Today, Yesterday, Last 7 days, Older), newest first and each with `SessionRowView`, as tall as its rows up to about five and then scrolling.
`archivedGroups(_:query:now:calendar:)` (`CarrierCore/Sessions.swift`) returns only archived rows, and with a query the ones whose title, workspace or agent match, keeping the buckets; they show nowhere else in the sidebar.
A session chosen in that list keeps Archive open (the list puts it back, since selecting a session opens Sessions).
The title of every section row is a button, and so is each archived session, so Tab (with Full Keyboard Access) and Space reach and choose Archive, Settings and an archived session without a pointer; a click on the rest of the row still chooses it.
The search is one view for the sections (`Carrier/SidebarSearch.swift`): the magnifier, or ⌘F for the open section, opens a field under the row with a clear button once it has text; esc, a second click on the magnifier or emptying it closes it.
What a list says comes from `SidebarListState` (rows, empty, or no match for what was typed; `CarrierCore/Sidebar.swift`): with no match the list is replaced by the `No results` block (`EmptyState.noResults`, a magnifier with a minus as the nearest SF Symbol to a struck one, and `Nothing matches “query”`) with a Clear search button.
A section with nothing in it says so in the same shape (`SidebarEmptyBlock`): Archive with nothing archived shows `Nothing archived` (`EmptyState.nothingArchived`); Sessions with no open session shows `No sessions yet` (`EmptyState.noSessions`) and a `New session` button; Terminal with no standalone terminals shows `No terminals yet` (`EmptyState.noTerminals`) and a `New Terminal Session` button; unfolded Carrier with no epics shows `No epics yet` (`EmptyState.noEpics`) and that an issue labelled `solve:epic:ready` starts one.
While one is empty its count is not drawn and its magnifier is dimmed and does nothing, ⌘F included.
While the window is the key window, ⌘1 selects Home, ⌘2 the Sessions home, ⌘3 the Carrier home and ⌘F opens the search of the section that is open (Sessions, Terminal, Carrier or Archive; nothing when all are folded).
The window handles them (`shortcutAction` in `CarrierCore/WindowShell.swift`, a key monitor in `WindowController`), not the menu bar item's menu, and each is in the tooltip of its row or magnifier.

The Sessions home, the Archive and a conversation are in [sessions](sessions.md); the Usage row is in [usage](usage.md).

## Resume card

An epic stopped in needs-human shows a notice as the last element of its Agent output tab, after the sessions (or the empty or starting state), in the same column (the width the person chose for the chat, Settings › Chat › Message width) (`CarrierCore/Resume.swift` builds it from the stuck kind, `Carrier/ResumeCardView.swift` draws it as a `NoticeCard`): the reason as the title, one line of what resuming does for that kind, tinted orange when a person's input is needed and red when something failed.
The pipeline above does not say why a step stopped; the notice does.
It has a Resume button only when the engine's hello lists `resumeEpic` (`EpicStore.canResume`, read from the connection the epic poller uses); against any other engine the card shows the reason and the words with no button.
Resume opens a sheet saying what will happen; confirming sends `resumeEpic` with the epic's repository and number on a connection of its own (the engine answers when the epic has started, up to 30 seconds), the button reads "Resuming…" until then and until the snapshot shows the epic out of needs-human, or stopped again after the answer (kept in `EpicStore.resuming`, so selecting another epic and coming back does not lose it), and a refusal (`unknown epic`, `not stopped`, `github unavailable`, `did not restart`) is shown in words, in orange, under the notice's line.

## The pipeline

The strip under the toolbar of an epic shows the steps of its pipeline, each as its state mark and its name, centred and as wide as the feed.
It does not say why a step stopped: for a needs-human stop the notice at the end of the Agent output does (see the resume card above).

## Starting

A running epic in its ship stage whose Agent output tab has no sessions yet (`isStarting`) shows `StartingView`: a card with three steps, Epic queued, Preparing the workspace (Workspace ready once the engine reports a worktree) and First agent starts (`startingSteps`, `CarrierCore/StartingSteps.swift`).
Each has a line with what the snapshot knows and leaves out what it does not: the wait for a slot (`queuedAt` to `startedAt`), the branch from the epic reply ("Branch …", then "Worktree on …" once there is one) and "Its output appears here".
The clock at the right is the time the epic started on the first step and how long the workspace step has been going on the second, ticking once a second.

## Slices and findings in an epic's log

In the builder's session each slice is a glass card of its own, in the order it happened between what the builder said and did: its state, `#730` and title, a quiet line (the step it is on while it works, calls, edits, test runs, errors, the lane, when it ran) and its pull request with a dot for its state (merged, open, draft), which opens GitHub.
Tapping the card opens that subagent's **Subagent view** over the Agent output tab, the one a subagent's row opens in a conversation (`subagentWork(lane:in:epic:)` gives it the lane's own call groups, thoughts and messages, all the runs of a resumed subagent in one view, and no brief).
The window's header then has a ‹ Back button next to the sidebar's, the slice's title as the title (the subagent's own description when the slice is not in the epic's list), "<Builder or Reviewer> · <the epic's title>" under it and the state (Running with a timer, or alone while the lane's start has not arrived; Finished with its duration; Failed) where the epic's links are, with no Stop button; Back, or the ‹ Back to Agent output button where the message box would be, returns to the tab as it was.
In a reviewer's session a second card shows the review: its verdict ("Ready", "Changes requested"), the round and the reviewer's name, its blockers first and then its suggestions, each with its kind as a word, its id, a line, whether it is new, carried (still open) or fixed (verified by the next round, dimmed), and the whole row opens the discussion on GitHub.
An approval's suggestions wait behind one line ("4 suggestions").
The reviewer's verification (CI passed or no CI) is the foot of that card and opens on its evidence, so the reviewer's session has no separate "Completed" row (a stop keeps its row); the engine sends no commit, so the foot names none.
The fixer's session shows the same round's blockers with the ones the next review verified marked fixed, under its own result row.
A note "created 946 (branch)", which Claude Code emits when the agent publishes a change (`code_change_published`), is a quiet line with the pull request as a link; a skill, the closing result and Continue in Terminal are lines of the same card family.
How they are drawn is in [the look of the app](../macos-ui.md#cards-in-the-feed).

## Agent output

An epic's Agent output tab lists its sessions oldest first, the newest last, as centered rows with no card (how they are drawn is in [the UI guide](../macos-ui.md#rows-of-a-feed); the words are `sessionRowText`, `sessionSummary` and `earlierSessions` in `CarrierCore/SessionSections.swift`).
A row says who acted (the GitHub profile, an Agent Forge bot, or the tool's name when none is known), the role and place ("Builder · Ship", "Reviewer · Round 2"), and on a second line the tool, the account, the model and the effort that are known.
The engine's `sessions` reply gives the key of `profiles` the session acted as (`profile`), and the app reads `engine.json` when the tab opens to say whose account that is: a `forge` profile is named by its Agent Forge bot, a `gh` profile has no name in the file, so such a session shows the tool's name, and a key the file does not have stays as sent.
An engine that sends no key (an epic frozen before it was kept) gets the bot of `agents.author` (builder and fixer) or `agents.reviewer`, and the role's `effort` when the session ran on the role's model.
A repository's own `agents` override is not read.
Under the row one line sums the session up: while it runs "Working · since 16:09 · 62 calls"; stopped, the orange `stopped` badge and the failure's kind and detail; open, the counts (calls, edits with their lines, test runs, errors, time); folded, how it ended in bold (Completed, Changes requested, Needs a human), the CI verdict and the time, or the counts when it has no result.
The whole row is the one button that folds the session (the newest and a running or stopped one start open); there are no pinned headers.
Above five sessions the oldest ones are one row ("3 earlier sessions · Builder, Reviewer, Fixer · 45m") that opens them.

## File icons

`fileIcon(path)` (`CarrierCore/FileIcons.swift`) is the one place that picks a file's icon: a bundled SVG from Material Icon Theme (MIT) for the languages in `bundledIconName`, else the category's SF Symbol.
