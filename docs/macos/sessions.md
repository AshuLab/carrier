# Sessions

The Sessions home, the Archive and a session's conversation; a new session is in [new session](new-session.md).

## Sessions home

Selecting the Sessions row shows the Sessions home (`Carrier/SessionsHomeView.swift`; the values are `CarrierCore/SessionsHome.swift` and `sessionGroups`): the title with its count ("5 active · 1 waits for you", "1 of 5 · …" with a filter on, "N results" with a search), one glass group with Search and Filter, and New session, which follows the Sessions flag and does nothing yet.
The list is grouped by workspace (or by age or status), one row per session with the state glyph, title, agent, the branch of a worktree session and the age; a session that waits for the person is orange and a click selects it.
Search is a field in the group (Escape or ✕ closes and clears it) that finds by title, workspace and agent across active and archived sessions, flat, with the workspace as a tag and archived matches dimmed and tagged.
Filter is one popover with the sort (`sidebar.sessionSort`, the sidebar's own, so both agree) and what to show by status and by agent; the button shows how many are on, chips under the header remove one each and Clear filters removes them all.
The search and the filters are not remembered.
Without sessions the page says "No sessions yet"; a search or filter that matches none says "No sessions match" with Clear filters.

## Archive

Selecting the Archive row shows the Archive page (`Carrier/ArchiveView.swift`; the values are `CarrierCore/ChatArchive.swift`, `archivePage`): the title with its count ("5 sessions", "N results" with a search), the same glass group with Search and Filter, and, on the right, Clear sessions…, disabled when nothing is archived.
Filter only sorts, by date archived (Last 30 days, Older) or by project, remembered in `SidebarStore.archiveSort` (the host does not say when a session was archived, so the date is the session's last activity).
Search finds by title, workspace and agent.
Nothing archived says "Nothing archived" ("Archived sessions are kept here."), a search with no result "No sessions match".
On hover a row shows Open (selects the session's conversation, read only: the session stays archived and the message box gives way to a notice with Resume), Resume (`archive` with false, then opens it) and Delete (asks first, then `delete`).
Clear sessions asks with an alert that names the count ("Delete all 5 archived sessions?", Cancel is the default button) and deletes all of them, not only what a search shows; a refusal of the host is told in an alert in its words.
Under each archived row a line says when the session will be deleted ("Deletes in 12 days", "Deletes soon" once it is due) or, for a session the clock spares because its worktree holds unsaved work, "Kept because its worktree has unsaved work" (`archiveNote`, `ArchivePage.notes`): the host's `list` rows carry `kept` and `deleteAt`, and a host that leaves them out reads as not kept and no date, so the row has no line.
On a row of the sidebar's list the pointer brings Pin (Unpin) and Archive in place of the age, the two the context menu has (`SessionRowView`, `hoverActions`); the column keeps the room of the two buttons, so the title does not move, and a refusal of the host (an archive of a working session) is told in an alert as the menu does.
The Archive section and Settings' preview draw the row without them. Settings > Sidebar's preview shows three rows (idle, Done, Needs you); Reset of that page also clears the remembered width (`SidebarStore.widthKey`), which the window reads at launch.
A "Base folder" session says it with a folder mark, as a worktree's branch has its own.

A session whose turn ended and that the person has not opened since (`SessionRow.unread`, `SessionStatus.unread`) says "Done" in green, with how long ago it ended beside it in the colour of a time, in the place of the time (on the second line, as the word alone, when the time is switched off), as "Needs you" does in orange; opening it brings the time back.
"Needs you" is for a permission or a question the agent is blocked on, "Done" for a turn that simply ended.
When the turn ends while the row is on screen, the icon's glow turns green and goes once round, fast, from where the arc was (`WorkingRing`, `finished`); with Reduce Motion the lap is skipped and the word still appears.

A row of the sidebar's list has room around its lines (`Density.sessionRowPadding`: 12 points, 7 compact) and the branch in monospace.
A session that has a pull request, or lines it changed, has a third line: the pull request's chip (`SessionPullRequestChip`: "#412 · ✓", "#979 · CI ✕", "#983 · draft", "#88 · merged", tinted green, red, grey or purple, and a click opens it), the lines it changed as "+86 −12" and the providers, which go down from the second line with it; with only one of the two, the line has only that one.
Without either the row has two lines, as before.
Both come from the host's `list` (`pr` and `diff`, read by git on this Mac and by the person's own `gh`; the host does not wait for them, so a row has them a few seconds after it appears); a host that does not say leaves the row as it was, and the Archive section draws its rows without the third line.
Settings › Sidebar › Session rows has a switch for the chip (Pull request) and one for the lines (Lines changed), both on (`SidebarStore.showsPullRequestKey`, `showsDiffKey`; `SessionRowParts`, `SessionRowContent.hasThirdLine`): with one off the third line has only the other, and with both off the row has two lines again.
A card opens when the pointer rests on a row (`hoverCard`, `HoverCard.swift`, an `NSPopover`) and takes no click from the window under it: its behavior is `applicationDefined`, so the system does not close it for a click outside it, which swallowed that click (the first click on a row or on its Archive did nothing while the card was open), and it ends itself with the first click or scroll in the window, the click going on to the row, or when the app goes to the background.
The card (`SessionPeekView`) says what the row's third line says, whatever the switches: the state in the row's colours (violet while it writes, cyan while it waits for what it started, orange when it waits for the person, green for Done), the pull request's chip with its lines (the lines alone for a session without one) and, while the agent waits for something it started, what it waits for (up to three, with "+n more"); a path and a branch are in monospace.

A session that works keeps its place in the lists: the host moves a session's last activity with every event of its agent, so two that work at once would swap places over and over in a list that puts the newest first.
While a session works, waits for the person or waits for what it started, the lists place it by the time its turn began, as the app first saw it (`SessionRow.orderedAt`, held by `WorkingOrder` in `refreshUnread`), whatever its agent does; when it stops it has its last activity again and takes its place once.
The sidebar, the Sessions home, its search and the next and previous session shortcuts all order by it (`SessionRow.sortedAt`), the age buckets too, so a session does not change bucket because its agent spoke.

A session whose turn ended while the agent waits for something it started (a build, a monitor, a subagent) is working, not idle: `SessionRow.background` is what the host's `list` says (`isWorking`), its ring and its clock go on, in cyan and not in the violet of one that writes, it is in the Working group, it can be stopped (Stop in its menu, which stops those tasks) and it cannot be archived ("Stop the background task to archive it"), and it is not "Done" until the last one ends.

In the conversation, while the host lists background tasks for the session (`ConversationModel.background`, from the same list the sidebar reads), a card sits over the message box, with the notices that are there (`BackgroundWorkCard`, in `ChatToolGroupView.swift` with the pieces it shares with the agent's runs): one line of the glass a run has, in cyan, with a turning ring, a glow round the edge and a shimmer over the words.
Shut, its line names one task at a time ("Waiting on pnpm build…") and rolls to the next every three seconds, with "· 3 tasks" after it, the time since the oldest began at the right (`startedAt`, which the host stamps when it first sees each task) and Stop, which stops them all.
Open (the chevron), it lists the tasks, each with its kind and how long it has run; with more than one, and a host that lists `stopTask` among its capabilities (`ConversationModel.canStopTask`), each has its own Stop (the host's `stopTask`, by the task's id) and the line's says "Stop all".
It is gone with the last task.

Archiving is felt at once: the row is drawn archived as soon as it is asked (`SessionActions.archiving`, put on the list by `refreshUnread`), the host answers without waiting for the agent to end, and the lists are read again right away (`PollNap`) and not at the next tick.
A session that works or waits for an answer cannot be archived (the host refuses it), and a session with running subagents counts as working after its turn ended, so it is drawn working and cannot be archived or deleted until the last subagent ends; so the Archive button of the hover, the one of the Sessions home and the item of the context menu are off, with the reason as their tooltip ("Stop the session to archive it"; `archiveBlock`), and the shortcut says it in an alert.
If the host refuses anyway, the row comes back and an alert says why.

A row of the Sessions home says what the sidebar's row does (`SessionHomeRow`): the icon with its violet ring while the session writes and its cyan one while it waits for something it started, what takes the time's place at the right (`SessionTimeLabel`, shared with the sidebar: "Needs you", the stopwatch, "Done" or the age), and, on the line of where it works, the branch in monospace, its turns and model, its pull request's chip and the lines it changed.
Under the title it says what the agent last wrote, or, while it waits for what it started, what for ("Waiting on pnpm build and 2 more", `waitingOnText`).
The home shows the pull request and the lines whatever the Sidebar switches say: those are for the sidebar's rows.

A session row's context menu in the sidebar and on the Sessions home has Archive (Restore for an archived match), Reveal in Finder and Copy session id.
`SessionActions` runs archive, restore, delete and clear through `ChatHost` and tells `ChatSessionsPoller.invalidateArchived()` after each, so the Archive row's count is right within a second.
Before a Delete and before Clear sessions the app asks the host `deletePreview` (`SessionActions.confirmDelete` and `confirmClear`; the words are `deleteSessionQuestion` and `clearSessionsQuestion`): a session in a worktree says "3 uncommitted files and 2 commits that exist nowhere else will be removed with its worktree" (or only that its worktree will be removed when it holds nothing to lose), a session in a base folder keeps the plain text, and the Clear alert adds how many of the sessions work in worktrees that would lose work and the totals of files and commits; if the preview itself is refused or the host does not answer, that is told in words and nothing is deleted.
A refusal of `delete` (a worktree that cannot be removed) is told in the host's words and the session stays in the list.
The fixture host answers `deletePreview` from `chat-delete-preview.json`.
It keeps the changes in memory and refuses to archive or delete a working or waiting session, as the real one does.
`--smoke-window` ends by selecting the Archive and printing an `archive:` line (the count, the groups, `listed` or the empty state, and whether Clear is enabled) and the layout again.

## Conversation

Selecting a session (`.session(id:)`) shows its conversation (`Carrier/ConversationView.swift`; the logic is in `CarrierCore/ChatConversation.swift`).
While the view is on screen a task runs `ConversationModel.run()`, which asks the chat host for `events` by cursor about every 250 ms, in pages of at most 200 (a full page is followed at once by the next), and ends with the task when the person selects something else.
`chatFeed` turns the events into rows: the person's messages (a bubble on the right), the agent's (markdown), a closing line per turn (model, how long, and the input and output tokens the provider reported, each only when there), the agent's calls and thoughts in order as one work card per run (`ChatToolGroupView`: "Ran 3 commands", a node per call that opens to its output or its diff, "N failed"), an approval as one plain line completed by its answer, an error in red and, last, the `streaming` text as the message in progress.
An event the host stored with a `parentCallId` was made inside a subagent: `chatFeed` does not draw it and no group counts it, and a `task` event is not drawn either.
The launching `Agent` call is drawn as any other call until the subagent rows replace it, and a session stored before the change has no such events and looks as it did.
While a run is live, its line starts with a **Kind chip** saying what the agent is waiting on (Thinking, Read, Search, Edit, Shell, the MCP server's name, or Needs you while an approval waits), and an MCP call reads as its server and tool name (with its arguments inside the opened step).
The timer of a live line is the running call's own time, with the turn's beside it, quieter, while it is longer (the turn's alone while the agent thinks); a Shell or MCP call running for more than 30 seconds turns its timer amber until it ends.
The Agent output tab's live line does the same, since it draws with the same view.
Each subagent the agent launches is a **Subagent row** under the run that launched it: its type as a chip, its title (the description it was launched with), the step it is on, its steps and its timer, with a spinner while it runs, a tick when it finished, a red mark when it failed and a square when it was stopped.
Several launched together each have a row, in the order they started, and the launching `Agent` call is not drawn as another tool.
While any of a run's subagents runs, the run's line reads "N subagents · Waiting for them…", N being those running, and the finished run's summary counts "1 subagent" or "N subagents" apart from "other tools"; both keep following the subagents' events after the turn that launched them has ended, and a subagent that started and never ended shows as running while the session works and as stopped, in its row, in the parent's line and in its view, once it does not (the host restarted and lost it).
A session stored before the host linked subagents to their calls shows no rows.
Tapping a row opens its **Subagent view** over the conversation (the conversation stays under it, so Back finds its feed as it was): `subagentWork` turns the stored events into its brief (the `prompt` of the launching call's input, as stored and cut), its calls, thoughts and messages as flow items, and the rows of the subagents it launched, which open one level deeper.
The window's header then has a ‹ Back button next to the sidebar's, the subagent's description as the title, "<type> · Subagent of <session title>" under it, and its state (Running with a timer, Finished with its duration, Failed or Stopped) where the worktree pill is; the panel button stays.
While the subagent runs, a Stop pill sits next to its state: it stops only that subagent and not the main agent, which reads that the subagent was interrupted and goes on.
The pill asks the host (`stopTask`) and the view says Stopped, as the row does, when the host's `stopped` event arrives and not before; it is not offered once the subagent ended or by a host that does not list `stopTask`.
The message box's Stop, which shows while the session works, interrupts the turn and then asks the host to stop each subagent still running (a host that does not list `stopTask` gets only the interrupt); the rows say Stopped as the events arrive.
Back leaves one level, and so does choosing another session or page.
Back from the last level puts the cursor in the message box again, as when the session opened.
The place of the message box holds "Subagent work is read-only." and a ‹ Back to chat button, so nothing can be typed to it.
While it runs, its live line is the conversation's, for it; once it ended or its session stopped working, a call that never ended shows stopped.
Once the run finishes, its summary counts MCP calls apart from other tools.
A poll that fails shows its reason under the feed and is logged once; polling goes on.

The conversation's title bar is the window's: the title (`conversationTitle`, "New session" while the host has none), under it `conversationSubtitle` ("workspace · ⑂ branch" in a worktree, "workspace · base folder" in a folder) and, on the right, the Open menu (`OpenMenu`, items from `openMenuItems`: Reveal in Finder, Copy path and, for a worktree, Copy branch name; a copy item says "Copied" for a moment).

Markdown: SwiftUI's `AttributedString` parses what is inside a line (bold, italics, inline code, links) and covers what the agents write there; the blocks around it are `markdownBlocks` (`CarrierCore/SessionSections.swift`), the line-by-line reader the epics' Agent output already used, which now also reads fenced code as a block of its own (language after the fence, an open fence runs to the end, as in a message being written).
`CodeBlockView` draws it with the language and a Copy button (`CopyButton`, the one of the console blocks).
Numbered lists and tables are not read as blocks: a numbered item shows as a line with its number.

## The epic's Agent output

The Agent output tab of an epic draws the agent's work with these same views.
The engine's events (`ExecEvent`, from the harness parser) are turned into the chat's `ToolCall`s and `ToolGroup`s by `Transcript` and `flowItems` (`CarrierCore/TranscriptItems.swift`, `TranscriptFlow.swift`), so a run reads the same as in a session: one work card per run of calls, folded until opened (open already when Settings has Tool output on expanded), the agent's text as markdown, an error as the red banner.
An edit with a diff shows as a call with its diff inside the card, as in a session.
The newest run of a running session is live (shimmer, ring, glow), and a call that never ended in a session that is over shows as stopped.
A thought is drawn if the events carry one (`reasoning`; today's parsers send none) and follows Settings, Show reasoning.
What is only the epic's stays between the runs, in event order: notes (a change the agent published, "created 736 (main)", is a quiet line with the pull request as a link), skills as a row of their own, and a subagent's slice row, which opens its Subagent view.
A harness with no parser shows its summarised `tail` lines instead.
The calls are hidden when Tool output is hidden.
