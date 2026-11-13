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
`chatFeed` turns the events into rows: the person's messages (a bubble on the right), the agent's (markdown), a closing line per turn (model, how long, and the input and output tokens the provider reported, each only when there), a tool call as one plain line completed by its end (tool, argument, the first line of its output or "failed"), an approval as one plain line completed by its answer, an error in red and, last, the `streaming` text as the message in progress.
A poll that fails shows its reason under the feed and is logged once; polling goes on.

The conversation's title bar is the window's: the title (`conversationTitle`, "New session" while the host has none), under it `conversationSubtitle` ("workspace · ⑂ branch" in a worktree, "workspace · base folder" in a folder) and, on the right, the Open menu (`OpenMenu`, items from `openMenuItems`: Reveal in Finder, Copy path and, for a worktree, Copy branch name; a copy item says "Copied" for a moment).

Markdown: SwiftUI's `AttributedString` parses what is inside a line (bold, italics, inline code, links) and covers what the agents write there; the blocks around it are `markdownBlocks` (`CarrierCore/SessionSections.swift`), the line-by-line reader the epics' Agent output already used, which now also reads fenced code as a block of its own (language after the fence, an open fence runs to the end, as in a message being written).
`CodeBlockView` draws it with the language and a Copy button (`CopyButton`, the one of the console blocks).
Numbered lists and tables are not read as blocks: a numbered item shows as a line with its number.
