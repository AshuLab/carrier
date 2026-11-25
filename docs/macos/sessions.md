# Sessions

The Sessions home and the Archive; a session's conversation is in [chat](chat.md) and a new session in [new session](new-session.md).

## Sessions home

Selecting the Sessions row shows the Sessions home (`Carrier/Features/Sessions/SessionsHomeView.swift`; the values are `CarrierCore/Sessions/SessionsHome.swift` and `sessionGroups`): the title with its count ("5 active · 1 waits for you", "1 of 5 · …" with a filter on, "N results" with a search), one glass group with Search and Filter, and New session, which follows the Sessions flag and does nothing yet.
The list is grouped by workspace (or by age or status), one row per session with the state glyph, title, agent, the branch of a worktree session and the age; a session that waits for the person is orange and a click selects it.
Search is a field in the group (Escape or ✕ closes and clears it) that finds by title, workspace and agent across active and archived sessions, flat, with the workspace as a tag and archived matches dimmed and tagged.
Filter is one popover with the sort (`sidebar.sessionSort`, the sidebar's own, so both agree) and what to show by status and by agent; the button shows how many are on, chips under the header remove one each and Clear filters removes them all.
The search and the filters are not remembered.
Without sessions the page says "No sessions yet"; a search or filter that matches none says "No sessions match" with Clear filters.

## Archive

Selecting the Archive row shows the Archive page (`Carrier/Features/Sessions/ArchiveView.swift`; the values are `CarrierCore/Chat/ChatArchive.swift`, `archivePage`): the title with its count ("5 sessions", "N results" with a search), the same glass group with Search and Filter, and, on the right, Clear sessions…, disabled when nothing is archived.
Filter only sorts, by date archived (Last 30 days, Older) or by project, remembered in `SidebarStore.archiveSort` (the host does not say when a session was archived, so the date is the session's last activity).
Search finds by title, workspace and agent.
Nothing archived says "Nothing archived" ("Archived sessions are kept here."), a search with no result "No sessions match".
On hover a row shows Open (selects the session's conversation, read only: the session stays archived and the message box gives way to a notice with Resume), Resume (`archive` with false, then opens it) and Delete (asks first, then `delete`).
Clear sessions asks with an alert that names the count ("Delete all 5 archived sessions?", Cancel is the default button) and deletes all of them, not only what a search shows; a refusal of the host is told in an alert in its words.
Under each archived row a line says when the session will be deleted ("Deletes in 12 days", "Deletes soon" once it is due) or, for a session the clock spares because its worktree holds unsaved work, "Kept because its worktree has unsaved work" (`archiveNote`, `ArchivePage.notes`): the host's `list` rows carry `kept` and `deleteAt`, and a host that leaves them out reads as not kept and no date, so the row has no line.
On a row of the sidebar's list the pointer brings Pin (Unpin) and Archive in place of the age, the two the context menu has (`SessionRowView`, `hoverActions`); the column keeps the room of the two buttons, so the title does not move, and a refusal of the host (an archive of a working session) is told in an alert as the menu does.
Archiving (or deleting) the session that is on screen takes the window to a new session, so the next task starts there instead of the conversation staying (`WindowShell.sessionRemoved`).
The Archive section and Settings' preview draw the row without them. Settings > Sidebar's preview shows three rows (idle, Done, Needs you); Reset of that page also clears the remembered width (`Preference.sidebarWidth`), which the window reads at launch.
A "Base folder" session says it with a folder mark, as a worktree's branch has its own.

A session whose turn ended and that the person has not opened since (`SessionRow.unread`, `SessionStatus.unread`) says "Done" in green, with how long ago it ended beside it in the colour of a time, in the place of the time (on the second line, as the word alone, when the time is switched off), as "Needs you" does in orange; opening it brings the time back.
"Needs you" is for a permission or a question the agent is blocked on, "Done" for a turn that simply ended.
When the turn ends while the row is on screen, the icon's glow turns green and goes once round, fast, from where the arc was (`WorkingRing`, `finished`); with Reduce Motion the lap is skipped and the word still appears.
What was seen is kept in `sessions.seen`.
A list the host does not answer (not started yet, being replaced) changes nothing: the lists keep the last rows and no mark is lost, and before the first list that answered nothing is pruned or stored.
When the check of the chat host at open answers, the window's session list is read at once and not at the next tick.

The title of a row (`RollingTitle`) rolls when it changes: the new words come in from below and the old ones leave above, as the words of a run's line do (a crossfade with Reduce Motion).
"Regenerate title" in the row's menu shows it waiting while the host writes the new one (`TitleRegeneration`): the title goes quiet and shimmers for at least two seconds, even when the model answers at once, and for as long as the model takes when that is longer; then the new title rolls in.
The title just written is held for ten seconds, until the list has caught up with it, and a refusal of the host (no generator chosen, no model answering) stops the wait, leaves the old title and is told in words.
The window's own title in the toolbar is the system's and changes at the next read of the list, with no effect.

A row of the sidebar's list has room around its lines (`Density.sessionRowPadding`: 12 points, 7 compact) and the branch in monospace.
A session that has a pull request, or lines it changed, has a third line: one capsule (`SessionWorkPill`) with the pull request ("#412 · ✓", "#979 · CI ✕", "#412 · CI running", "#983 · Draft", "#88 · Merged"; a click opens it) and the lines it changed as "+86 −12", then the providers, which go down from the second line with it; with only one of the two, the capsule has only that one. The only colour is a dot before the pull request (green open, red failing, purple merged, a hollow grey ring for a draft or a closed one); the words are grey. The capsule is always laid out, so nothing moves: it has no fill at rest, a quiet one under the pointer and a lighter one on the selected row.
Without either the row has two lines, as before.
Both come from the host's `list` (`pr` and `diff`, read by git on this Mac and by the person's own `gh`; the host does not wait for them, so a row has them a few seconds after it appears); a host that does not say leaves the row as it was, and the Archive section draws its rows without the third line.
Settings › Sidebar › Session rows has a switch for the chip (Pull request) and one for the lines (Lines changed), both on (`SidebarStore.showsPullRequestKey`, `showsDiffKey`; `SessionRowParts`, `SessionRowContent.hasThirdLine`): with one off the third line has only the other, and with both off the row has two lines again.
A card opens when the pointer rests on a row (`hoverCard`, `HoverCard.swift`, an `NSPopover`) and takes no click from the window under it: its behavior is `applicationDefined`, so the system does not close it for a click outside it, which swallowed that click (the first click on a row or on its Archive did nothing while the card was open), and it ends itself with the first click or scroll in the window, the click going on to the row, or when the app goes to the background.
The card (`SessionPeekView`) says what the row's third line says, whatever the switches: the state in the row's colours (violet while it writes, cyan while it waits for what it started, orange when it waits for the person, green for Done), the pull request's chip with its lines (the lines alone for a session without one) and, while the agent waits for something it started, what it waits for (up to three, with "+n more"); a path and a branch are in monospace.
For a worktree the card says "Worktree of <project>", the branch with "cut from <branch>" under it, and the folder by its name with the whole path under it (`CardFact.detail`), so two worktrees of one project are told apart.

A session that works keeps its place in the lists: the host moves a session's last activity with every event of its agent, so two that work at once would swap places over and over in a list that puts the newest first.
While a session works, waits for the person or waits for what it started, the lists place it by the time its turn began, as the app first saw it (`SessionRow.orderedAt`, held by `WorkingOrder` in `refreshUnread`), whatever its agent does; when it stops it has its last activity again and takes its place once.
The sidebar, the Sessions home, its search and the next and previous session shortcuts all order by it (`SessionRow.sortedAt`), the age buckets too, so a session does not change bucket because its agent spoke.

A session whose turn ended while the agent waits for something it started (a build, a monitor, a subagent) is working, not idle: `SessionRow.background` is what the host's `list` says (`isWorking`), its ring and its clock go on, in cyan and not in the violet of one that writes, it is in the Working group, it can be stopped (Stop in its menu, which stops those tasks) and it cannot be archived ("Stop the background task to archive it"), and it is not "Done" until the last one ends.

In the conversation, while the host lists background tasks for the session (`ConversationModel.background`, from the `session` summary of the `events` reply, or from `list` for a host that does not say), a card sits over the message box, with the notices that are there (`BackgroundWorkCard`, in `Carrier/Features/Chat/BackgroundWorkCard.swift`, with `Shimmer` and `GlowEdge` of `Carrier/UI/Feedback`, which it shares with the agent's runs): one line of the glass a run has, in cyan, with a turning ring, a glow round the edge and a shimmer over the words.
Shut, its line names one task at a time ("Waiting on pnpm build…") and rolls to the next every three seconds, with "· 3 tasks" after it, the time since the oldest began at the right (`startedAt`, which the host stamps when it first sees each task) and Stop, which stops them all.
Open (the chevron), it lists the tasks, each with its kind and how long it has run; with more than one, and a host that lists `stopTask` among its capabilities (`ConversationModel.canStopTask`), each has its own Stop (the host's `stopTask`, by the task's id) and the line's says "Stop all".
It is gone with the last task.

Archiving is felt at once: the row is drawn archived as soon as it is asked (`SessionActions.archiving`, put on the list by `refreshUnread`), the host answers without waiting for the agent to end, and the lists are read again right away (`ChatLink.refresh`) and not at the next tick.
A session that works or waits for an answer cannot be archived (the host refuses it), and a session with running subagents counts as working after its turn ended, so it is drawn working and cannot be archived or deleted until the last subagent ends; so the Archive button of the hover, the one of the Sessions home and the item of the context menu are off, with the reason as their tooltip ("Stop the session to archive it"; `archiveBlock`), and the shortcut says it in an alert.
If the host refuses anyway, the row comes back and an alert says why.

A row of the Sessions home says what the sidebar's row does (`SessionHomeRow`): the icon with its violet ring while the session writes and its cyan one while it waits for something it started, what takes the time's place at the right (`SessionTimeLabel`, shared with the sidebar: "Needs you", the stopwatch, "Done" or the age), and, on the line of where it works, the branch in monospace, its turns and model, its pull request's chip and the lines it changed.
Under the title it says what the agent last wrote, or, while it waits for what it started, what for ("Waiting on pnpm build and 2 more", `waitingOnText`).
The home shows the pull request and the lines whatever the Sidebar switches say: those are for the sidebar's rows.

A session row's context menu (`sessionMenu` in `CarrierCore/Chat/ChatArchive.swift`, tested in `SessionMenuTests`) is in four groups: Stop (while it works), Pin (Unpin) and Mark as unread (Mark as read once it has the dot); Rename and Regenerate title; New session on its branch, Project settings…, Open in Terminal, Copy (path, branch name, session id) and, on the home, Filter; Archive (Restore for an archived one) and Delete….
In the sidebar and on the home (`inWindow`) the menu also has Mark as unread, which forgets what the person saw of the session (`PanelModel.setUnread`), so it is unread again when it is idle and answered; it is off for the session that is open, since opening one marks it read. It is not in the Archive.
New session on <branch> (or New session in this project for a session that works in the folder itself) opens the new session draft in the session's project with a worktree cut from that branch (`NewSessionModel.start(in:branch:)`: its local branch, else the remote one; a branch the folder no longer has leaves the draft as the project sets it). It sends nothing until the person writes a message. An archived session has none.
Project settings… opens the project's page in Settings; it is only there when the session's folder is in Carrier's list of projects.
Delete… asks first, naming what its worktree holds (`deleteSessionQuestion`), as it did for an archived session, and is off while the session works or waits, with the reason as its tooltip, like Archive.
`SessionActions` (`CarrierCore/Chat/SessionActions.swift`) runs archive, restore, delete and clear through `ChatHost` and tells `SocketChatHost.refreshSessions(archived: true)` after each, so the Archive row's count is right within a second.
Before a Delete and before Clear sessions the app asks the host `deletePreview` (`SessionActions.confirmDelete` and `confirmClear`; the words are `deleteSessionQuestion` and `clearSessionsQuestion`): a session in a worktree says "3 uncommitted files and 2 commits that exist nowhere else will be removed with its worktree" (or only that its worktree will be removed when it holds nothing to lose), a session in a base folder keeps the plain text, and the Clear alert adds how many of the sessions work in worktrees that would lose work and the totals of files and commits; if the preview itself is refused or the host does not answer, that is told in words and nothing is deleted.
A refusal of `delete` (a worktree that cannot be removed) is told in the host's words and the session stays in the list.
The fixture host answers `deletePreview` from `chat-delete-preview.json`.
It keeps the changes in memory and refuses to archive or delete a working or waiting session, as the real one does.
`--smoke-window` ends by selecting the Archive and printing an `archive:` line (the count, the groups, `listed` or the empty state, and whether Clear is enabled) and the layout again.

## Conversation

The conversation of a session, changing its agent and the context and limits beside the microphone are in [chat](chat.md); an epic's Agent output is in [epics](epics.md#the-epics-agent-output).

## How the app reads the chat host

`ChatLink` (`CarrierCore/Connection/ChatLink.swift`) is the one reader of the chat host's socket, one per socket path (`ChatLink.link(for:)`), and `SocketChatHost` goes through it for what the app asks again and again: `list`, a conversation's `events`, the hello's capabilities (`capabilities()`) and the sessions' updates (`sessionUpdates()`).
Everything else (`send`, `resume`, `usage`, a clone, `health`...) is an action and keeps one connection per request, as before.
The host answers a connection one request at a time, so only requests that return at once go over the kept connection.
Two costs are known and accepted.
A host that is wedged (it takes the connection and does not answer) holds the requests queued behind the first one: each pays up to its own 5 s timeout in turn, which drops the connection, so with N open conversations the last poll of a round waits about 5N s.
A caller whose task is cancelled still waits for its reply or the timeout (the continuation is not cancellable); nothing is left half-read, and the next request is not affected.

- **One connection, one hello.** The connection is opened on the first read, its hello is read once and kept, and its socket work runs on a queue of its own (`ChatConnection`), so no thread of the cooperative pool waits on it. A connection whose host closed it (a stopped host, a replaced one: the app replaces a host when `carrier` has a newer version) is seen before it is used (`ControlClient.peerClosed`), opened again with a new hello, and a request that finds it closed anyway is made once more on a new one. A timeout or a bad line drops it; an error reply does not.
- **Capabilities** come from that hello, so `UsageStore`, `HealthStore` and a conversation's first poll open no connection for them.
- **Two asks for the same list at the same time share one request** (`list(archived:)`; the active and the archived list are two requests).
  A message sent to a session that may have been closed asks the active list (`deliver`) and can join a read that began a few milliseconds earlier: against a rule that closes a session after ten minutes idle, the window is too small to matter.
  A `refresh` ends the sharing: a read that began before it still answers its own callers, and the ask after it is a read of its own, so a list read before an archive is never taken for the one the refresh asked for.
  A conversation's `events` are not shared: each open session has one reader, and `ConversationModel.poll` never reads one cursor twice at a time.
- **The sessions are read by one loop for everyone who listens** (`sessions()`; the sidebar's `ChatSessionsPoller`, `watchChatSessions` for the notifications and the menu, and `NewSessionModel` while a repository waits to be watched). It starts with the first listener and stops with the last. A listener gets the last update at once (`replayed`, never `authoritative`), then one at each read, always the newest.
  The notifications' listener lasts as long as the app runs, so the loop, and the archived list every 60 s with it, goes on with the window closed.
- **The pace** is `PollPace.seconds`: 2 s in front, 5 s behind another app, 10 s in Low Power Mode. While the host does not answer the wait doubles with each miss (the first miss waits twice the pace: 4 s at a pace of 2 s) up to 10 s while the window is in front or on screen (`PollPace.looking`), so a host restarted by hand shows within 10 s, and up to 30 s while nobody can see it (`sessionsPollWait`); the wait ends at once when the app starts or replaces the host (`ChatHostStarter`) and when the window comes to the front.
- **The archived list** is read every 60 s, in the same cycle after an archive, a restore or a delete of the app's own (`refresh(archived: true)`), and when a session leaves the active list without being in the archived one, so a session that something else archived is never missing from active plus archived (what `CarrierTerminalStore.reconcileKnownSessions` prunes by). `SessionsReader` holds these rules.
- **A miss is told once**, here: the update carries the last good lists with `stale` (never an empty list for a host that did not answer; empty with `stale` only when none was ever read), the first miss after an answer is logged, and the ones after it add nothing. A listener ignores a stale update: the sidebar keeps its rows and what the person has seen, and the notifications keep their last list (the Mac is let sleep: `KeepAwakeController.sessions(working: 0)`).
- **`authoritative`** is true only for a cycle that read both lists and the host answered: what feeds the terminals' pruning.
- **`readAt`** is when a read began. `NewSessionModel` looks only at reads that began after the session was opened, as a list read before it cannot say it is gone.
- **The keep-alive of a session is not the link's.** The loop names no session, so it renews none; a conversation's own `events` do. The kept connection counts as a client of the host for as long as the app runs, so the host does not end itself while the app is open (as the polls every few seconds did not let it) and ends itself after the app quits.

A host that is not a `SocketChatHost` (a test's fake) gets a default `sessionUpdates()` that reads `list` at the same pace and by the same rules.
`ChatLinkTests` runs the link against `FixtureServer` and `TestServer` with a ticker in place of the wait; `ChatSessionsTests` has the reader's rules.
