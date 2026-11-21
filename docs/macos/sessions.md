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
Archiving (or deleting) the session that is on screen takes the window to a new session, so the next task starts there instead of the conversation staying (`WindowShell.sessionRemoved`).
The Archive section and Settings' preview draw the row without them. Settings > Sidebar's preview shows three rows (idle, Done, Needs you); Reset of that page also clears the remembered width (`SidebarStore.widthKey`), which the window reads at launch.
A "Base folder" session says it with a folder mark, as a worktree's branch has its own.

A session whose turn ended and that the person has not opened since (`SessionRow.unread`, `SessionStatus.unread`) says "Done" in green, with how long ago it ended beside it in the colour of a time, in the place of the time (on the second line, as the word alone, when the time is switched off), as "Needs you" does in orange; opening it brings the time back.
"Needs you" is for a permission or a question the agent is blocked on, "Done" for a turn that simply ended.
When the turn ends while the row is on screen, the icon's glow turns green and goes once round, fast, from where the arc was (`WorkingRing`, `finished`); with Reduce Motion the lap is skipped and the word still appears.
What was seen is kept in `sessions.seen`.
A list the host does not answer (not started yet, being replaced) changes nothing: the lists keep the last rows and no mark is lost, and before the first list that answered nothing is pruned or stored.
When the check of the chat host at open answers, the window's session list is read at once and not at the next tick.

A row of the sidebar's list has room around its lines (`Density.sessionRowPadding`: 12 points, 7 compact) and the branch in monospace.
A session that has a pull request, or lines it changed, has a third line: one capsule (`SessionWorkPill`) with the pull request ("#412 · ✓", "#979 · CI ✕", "#983 · Draft", "#88 · Merged"; a click opens it) and the lines it changed as "+86 −12", then the providers, which go down from the second line with it; with only one of the two, the capsule has only that one. The only colour is a dot before the pull request (green open, red failing, purple merged, a hollow grey ring for a draft or a closed one); the words are grey. The capsule is always laid out, so nothing moves: it has no fill at rest, a quiet one under the pointer and a lighter one on the selected row.
Without either the row has two lines, as before.
Both come from the host's `list` (`pr` and `diff`, read by git on this Mac and by the person's own `gh`; the host does not wait for them, so a row has them a few seconds after it appears); a host that does not say leaves the row as it was, and the Archive section draws its rows without the third line.
Settings › Sidebar › Session rows has a switch for the chip (Pull request) and one for the lines (Lines changed), both on (`SidebarStore.showsPullRequestKey`, `showsDiffKey`; `SessionRowParts`, `SessionRowContent.hasThirdLine`): with one off the third line has only the other, and with both off the row has two lines again.
A card opens when the pointer rests on a row (`hoverCard`, `HoverCard.swift`, an `NSPopover`) and takes no click from the window under it: its behavior is `applicationDefined`, so the system does not close it for a click outside it, which swallowed that click (the first click on a row or on its Archive did nothing while the card was open), and it ends itself with the first click or scroll in the window, the click going on to the row, or when the app goes to the background.
The card (`SessionPeekView`) says what the row's third line says, whatever the switches: the state in the row's colours (violet while it writes, cyan while it waits for what it started, orange when it waits for the person, green for Done), the pull request's chip with its lines (the lines alone for a session without one) and, while the agent waits for something it started, what it waits for (up to three, with "+n more"); a path and a branch are in monospace.

A session that works keeps its place in the lists: the host moves a session's last activity with every event of its agent, so two that work at once would swap places over and over in a list that puts the newest first.
While a session works, waits for the person or waits for what it started, the lists place it by the time its turn began, as the app first saw it (`SessionRow.orderedAt`, held by `WorkingOrder` in `refreshUnread`), whatever its agent does; when it stops it has its last activity again and takes its place once.
The sidebar, the Sessions home, its search and the next and previous session shortcuts all order by it (`SessionRow.sortedAt`), the age buckets too, so a session does not change bucket because its agent spoke.

A session whose turn ended while the agent waits for something it started (a build, a monitor, a subagent) is working, not idle: `SessionRow.background` is what the host's `list` says (`isWorking`), its ring and its clock go on, in cyan and not in the violet of one that writes, it is in the Working group, it can be stopped (Stop in its menu, which stops those tasks) and it cannot be archived ("Stop the background task to archive it"), and it is not "Done" until the last one ends.

In the conversation, while the host lists background tasks for the session (`ConversationModel.background`, from the `session` summary of the `events` reply, or from `list` for a host that does not say), a card sits over the message box, with the notices that are there (`BackgroundWorkCard`, in `ChatToolGroupView.swift` with the pieces it shares with the agent's runs): one line of the glass a run has, in cyan, with a turning ring, a glow round the edge and a shimmer over the words.
Shut, its line names one task at a time ("Waiting on pnpm build…") and rolls to the next every three seconds, with "· 3 tasks" after it, the time since the oldest began at the right (`startedAt`, which the host stamps when it first sees each task) and Stop, which stops them all.
Open (the chevron), it lists the tasks, each with its kind and how long it has run; with more than one, and a host that lists `stopTask` among its capabilities (`ConversationModel.canStopTask`), each has its own Stop (the host's `stopTask`, by the task's id) and the line's says "Stop all".
It is gone with the last task.

Archiving is felt at once: the row is drawn archived as soon as it is asked (`SessionActions.archiving`, put on the list by `refreshUnread`), the host answers without waiting for the agent to end, and the lists are read again right away (`ChatLink.refresh`) and not at the next tick.
A session that works or waits for an answer cannot be archived (the host refuses it), and a session with running subagents counts as working after its turn ended, so it is drawn working and cannot be archived or deleted until the last subagent ends; so the Archive button of the hover, the one of the Sessions home and the item of the context menu are off, with the reason as their tooltip ("Stop the session to archive it"; `archiveBlock`), and the shortcut says it in an alert.
If the host refuses anyway, the row comes back and an alert says why.

A row of the Sessions home says what the sidebar's row does (`SessionHomeRow`): the icon with its violet ring while the session writes and its cyan one while it waits for something it started, what takes the time's place at the right (`SessionTimeLabel`, shared with the sidebar: "Needs you", the stopwatch, "Done" or the age), and, on the line of where it works, the branch in monospace, its turns and model, its pull request's chip and the lines it changed.
Under the title it says what the agent last wrote, or, while it waits for what it started, what for ("Waiting on pnpm build and 2 more", `waitingOnText`).
The home shows the pull request and the lines whatever the Sidebar switches say: those are for the sidebar's rows.

A session row's context menu in the sidebar and on the Sessions home has Archive (Restore for an archived match), Reveal in Finder and Copy session id.
`SessionActions` runs archive, restore, delete and clear through `ChatHost` and tells `SocketChatHost.refreshSessions(archived: true)` after each, so the Archive row's count is right within a second.
Before a Delete and before Clear sessions the app asks the host `deletePreview` (`SessionActions.confirmDelete` and `confirmClear`; the words are `deleteSessionQuestion` and `clearSessionsQuestion`): a session in a worktree says "3 uncommitted files and 2 commits that exist nowhere else will be removed with its worktree" (or only that its worktree will be removed when it holds nothing to lose), a session in a base folder keeps the plain text, and the Clear alert adds how many of the sessions work in worktrees that would lose work and the totals of files and commits; if the preview itself is refused or the host does not answer, that is told in words and nothing is deleted.
A refusal of `delete` (a worktree that cannot be removed) is told in the host's words and the session stays in the list.
The fixture host answers `deletePreview` from `chat-delete-preview.json`.
It keeps the changes in memory and refuses to archive or delete a working or waiting session, as the real one does.
`--smoke-window` ends by selecting the Archive and printing an `archive:` line (the count, the groups, `listed` or the empty state, and whether Clear is enabled) and the layout again.

## Conversation

Selecting a session (`.session(id:)`) shows its conversation (`Carrier/ConversationView.swift`; the logic is in `CarrierCore/ChatConversation.swift`).
While the view is on screen a task runs `ConversationModel.run()`, which asks the chat host for `events` by cursor every 250 ms while a turn runs and someone can see the window, every 2 s while the session is idle with the app in front, every 5 s idle with the window on screen behind another app, and about every 30 s while the window is hidden or the Mac asleep (`conversationWait`; a change of who is looking, or a send, cuts the wait short), in pages of at most 200 (a full page is followed at once by the next), and ends with the task when the person selects something else.
These `events` are also what keeps that session's agent awake.
The host closes an idle session that no request names for ten minutes by default (`idleCloseMinutes`, Settings › Sessions) (listing the sessions does not name it), so the one on screen stays and the others fall asleep, and sending to a sleeping one wakes it as before.
The options and the commands are most of that reply and almost never change, so `SocketChatHost` keeps the ones of each session with the host's `listsRev` and sends it back; a host that lists `listsRev` leaves them out while they are the same, and the reply the model reads has the kept ones in them.
The `session` summary of each reply says what the conversation needs of its session (its agent, whether it is in the archive, whether its agent process runs and what the agent waits for in the background), so a round asks for no list: `events` is the only request of a poll (`ConversationModel.round`).
A host whose summary leaves out `live` (an older one) is still read from its lists, the active one and then the archive, as before.
A summary that says `archived` is read as the archive list was: not live and with no background tasks, even when the host resumed the session and says `live`.
The app opens no child session (the sessions it shows come from the list, which leaves children out), so a summary that always names its session loses nothing the list said.
Two rounds never read at once: a poll asked for while another is under way (a send, an answer) makes that one go round again when it ends, and an event the cursor has passed is never added twice (`ConversationModel.poll`).
`chatFeed` turns the events into rows: the person's messages (a bubble on the right), the agent's (markdown), a closing line per turn (model, how long, the context at the turn's end and the output tokens, each only when there: the context is the size of the turn's last model call that the host reports as `context_tokens`/`contextTokens`; for a turn with none it shows what the turn's calls read added up as `N in`, since that sum, which the tooltip breaks down, is many times the context: each call reads it all again; the host also sends `context_window`/`contextWindow`, the size of the model's window, which `contextUse` turns into the share the message box's ring draws), the agent's calls and thoughts in order as one work card per run (`ChatToolGroupView`: "Ran 3 commands", a node per call that opens to its output or its diff, "N failed"), an approval as one plain line completed by its answer, an error in red and, last, the `streaming` text as the message in progress.
An event the host stored with a `parentCallId` was made inside a subagent: `chatFeed` does not draw it and no group counts it, and a `task` event is not drawn either.
The launching `Agent` call is drawn as any other call until the subagent rows replace it, and a session stored before the change has no such events and looks as it did.
While a run is live, its line starts with a **Kind chip** saying what the agent is waiting on (Thinking, Read, Search, Edit, Shell, the MCP server's name, or Needs you while an approval waits), and an MCP call reads as its server and tool name (with its arguments inside the opened step).
The timer of a live line is the running call's own time, with the turn's beside it, quieter, while it is longer (the turn's alone while the agent thinks); a Shell or MCP call running for more than 30 seconds turns its timer amber until it ends.
The Agent output tab's live line does the same, since it draws with the same view.
Each subagent the agent launches is a **Subagent row** under the run that launched it: its type as a chip, its title (the description it was launched with), the step it is on, its steps and its timer, with a spinner while it runs, a tick when it finished, a red mark when it failed and a square when it was stopped.
Several launched together each have a row, in the order they started, and the launching `Agent` call is not drawn as another tool.
While any of a run's subagents runs, the run's line reads "N subagents · Waiting for them…", N being those running, and the finished run's summary counts "1 subagent" or "N subagents" apart from "other tools"; both keep following the subagents' events after the turn that launched them has ended, and a subagent that started and never ended shows as running while the session works and as stopped, in its row, in the parent's line and in its view, once it does not (the host restarted and lost it).
A session stored before the host linked subagents to their calls shows no rows.
Tapping a row opens its **Subagent view** over the conversation (it replaces the conversation: the conversation stays mounted but is not drawn, so none of it shows through and Back finds its feed as it was): `subagentWork` turns the stored events into its brief (the `prompt` of the launching call's input, as stored and cut), its calls, thoughts and messages as flow items, and the rows of the subagents it launched, which open one level deeper.
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

### Changing the agent

The button at the left of the message box (`ComposerMenuButton`) opens a panel whose tabs are the host's agents, the session's own underlined. A tab changes the session's agent (`ConversationModel.switchAgent`, the host's `switchAgent`, [switch and delegate](../specs/switch-and-delegate-between-agents.md)): the session keeps its transcript, folder and worktree, and the new agent goes on from a selection of the newest messages (up to 16,000 bytes, with the first one) and can read the rest through the chat MCP's `history`; its reasoning and tool state do not carry over. The transcript says it with a notice ("The agent changed from … to …"). The tabs are off while the agent answers or a switch is under way, for an archived session and for a host that does not list `switchAgent`; an agent that is not installed or signed out is listed, off, with why. A refusal of the host (waiting for an approval, preparing, a model the harness does not list) is said in its words under the box. What was chosen for the old agent while the session was asleep is let go.

## The epic's Agent output

The Agent output tab of an epic draws the agent's work with these same views.
The engine's events (`ExecEvent`, from the harness parser) are turned into the chat's `ToolCall`s and `ToolGroup`s by `Transcript` and `flowItems` (`CarrierCore/TranscriptItems.swift`, `TranscriptFlow.swift`), so a run reads the same as in a session: one work card per run of calls, folded until opened (open already when Settings has Tool output on expanded), the agent's text as markdown, an error as the red banner.
An edit with a diff shows as a call with its diff inside the card, as in a session.
The newest run of a running session is live (shimmer, ring, glow), and a call that never ended in a session that is over shows as stopped.
A thought is drawn if the events carry one (`reasoning`; today's parsers send none) and follows Settings, Show reasoning.
What is only the epic's stays between the runs, in event order: notes (a change the agent published, "created 736 (main)", is a quiet line with the pull request as a link), skills as a row of their own, and a subagent's slice row, which opens its Subagent view.
A harness with no parser shows its summarised `tail` lines instead.
The calls are hidden when Tool output is hidden.

## Context and limits beside the microphone

Settings > Chat > Message box > Context and limits (`chat.showsContextUsage`, on by default) shows or hides it; off, the box has nothing beside the microphone.
In an open session the message box has a ring left of the microphone (`ContextUsageButton`, [how it is drawn](../macos-ui.md#the-ring-beside-the-microphone)): the outer ring is how full the context is, the inner one how much of the session's account has been used of its 5h limit.
The context is the last turn that told it (`contextUse(rows)`: `context_tokens` over `context_window`, so a turn cut short leaves the one before); the limits are the account's, from the same quotas as the Usage page (`accountUsage(model.agent, …)`).
The quotas are asked of the host when the ring appears, when a turn ends and when the popover opens, and never more than once a minute (`UsageStore.loadUnlessRecent`: the host keeps the quotas that long, and each ask also reads the history of what was used); the page's own minute timer is not on in a conversation.
A session whose host does not send the window shows the tokens and no ring share; an account that is signed out says so instead of showing meters, and a host that did not answer says the limits could not be read.
The tooltip and VoiceOver read the ring in words (`contextRingWords`): the window the inner ring follows by its name (5h, Weekly or Monthly), "near the limit" from 90 % and "limits last known" when stale, since the color and the dimming say that only to the eye.

## How the app reads the chat host

`ChatLink` (`CarrierCore/ChatLink.swift`) is the one reader of the chat host's socket, one per socket path (`ChatLink.link(for:)`), and `SocketChatHost` goes through it for what the app asks again and again: `list`, a conversation's `events`, the hello's capabilities (`capabilities()`) and the sessions' updates (`sessionUpdates()`).
Everything else (`send`, `resume`, `usage`, a clone, `health`...) is an action and keeps one connection per request, as before.
The host answers a connection one request at a time, so only requests that return at once go over the kept connection.

- **One connection, one hello.** The connection is opened on the first read, its hello is read once and kept, and its socket work runs on a queue of its own (`ChatConnection`), so no thread of the cooperative pool waits on it. A connection whose host closed it (a stopped host, a replaced one: the app replaces a host when `carrier` has a newer version) is seen before it is used (`ControlClient.peerClosed`), opened again with a new hello, and a request that finds it closed anyway is made once more on a new one. A timeout or a bad line drops it; an error reply does not.
- **Capabilities** come from that hello, so `UsageStore`, `HealthStore` and a conversation's first poll open no connection for them.
- **Two asks for the same list at the same time share one request** (`list(archived:)`; the active and the archived list are two requests).
  A message sent to a session that may have been closed asks the active list (`deliver`) and can join a read that began a few milliseconds earlier: against a rule that closes a session after ten minutes idle, the window is too small to matter.
  A conversation's `events` are not shared: each open session has one reader, and `ConversationModel.poll` never reads one cursor twice at a time.
- **The sessions are read by one loop for everyone who listens** (`sessions()`; the sidebar's `ChatSessionsPoller`, `watchChatSessions` for the notifications and the menu, and `NewSessionModel` while a repository waits to be watched). It starts with the first listener and stops with the last. A listener gets the last update at once (`replayed`, never `authoritative`), then one at each read, always the newest.
  The notifications' listener lasts as long as the app runs, so the loop, and the archived list every 60 s with it, goes on with the window closed.
- **The pace** is `PollPace.seconds`: 2 s in front, 5 s behind another app, 10 s in Low Power Mode. While the host does not answer the wait doubles with each miss, up to 30 s (`sessionsPollWait`), and the wait ends at once when the app starts or replaces the host (`ChatHostStarter`) and when the window comes to the front.
- **The archived list** is read every 60 s, in the same cycle after an archive, a restore or a delete of the app's own (`refresh(archived: true)`), and when a session leaves the active list without being in the archived one, so a session that something else archived is never missing from active plus archived (what `CarrierTerminalStore.reconcileKnownSessions` prunes by). `SessionsReader` holds these rules.
- **A miss is told once**, here: the update carries the last good lists with `stale` (never an empty list for a host that did not answer; empty with `stale` only when none was ever read), the first miss after an answer is logged, and the ones after it add nothing. A listener ignores a stale update: the sidebar keeps its rows and what the person has seen, and the notifications keep their last list (the Mac is let sleep: `KeepAwakeController.sessions(working: 0)`).
- **`authoritative`** is true only for a cycle that read both lists and the host answered: what feeds the terminals' pruning.
- **`readAt`** is when a read began. `NewSessionModel` looks only at reads that began after the session was opened, as a list read before it cannot say it is gone.
- **The keep-alive of a session is not the link's.** The loop names no session, so it renews none; a conversation's own `events` do. The kept connection counts as a client of the host for as long as the app runs, so the host does not end itself while the app is open (as the polls every few seconds did not let it) and ends itself after the app quits.

A host that is not a `SocketChatHost` (a test's fake) gets a default `sessionUpdates()` that reads `list` at the same pace and by the same rules.
`ChatLinkTests` runs the link against `FixtureServer` and `TestServer` with a ticker in place of the wait; `ChatSessionsTests` has the reader's rules.
