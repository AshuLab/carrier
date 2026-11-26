# App

**Call group** - A run of the agent's tool calls (and thoughts, when the events carry them) with nothing between them but other calls, drawn in the Agent output tab and in a session's conversation as the same one glass card: "Ran 4 commands" (or Explored, Changed, Worked), what it counted, "N failed", and a timer and shimmer while the agent works in it. It folds until opened and then lists its steps. A message, a note, an error, a skill or a slice ends the run; a lone call is a group of one.
_Avoid_: batch (that is slices started together), step, turn.

**Slice card** - The card of the Agent output tab that stands for one subagent building one slice: its state, its slice and title, its counts and pull request, placed in the log where the slice was taken and opening the subagent's view on its own calls.
One card per subagent; a resumed one is still one card.
_Avoid_: lane (the place it runs in), lane card, task.

**Subagent row** - The line a subagent has in a conversation: its type as a chip, its title, the step it is on now, its steps, its timer and its state, with the height of a call group's line.
One row per subagent, under the line of the run that launched it, and tapping it opens the subagent view.
In the Agent output tab the slice card plays this part.
_Avoid_: subagent card (that is the slice card of the epic), task, child.

**Subagent view** - What replaces the conversation when a subagent row is opened: the window's header with a ‹ Back button, the subagent's title, its state and Stop, and the subagent's own brief, call groups, thoughts and messages drawn as the main agent's are.
It is read only: a subagent cannot be written to from the host.
_Avoid_: subagent tab, subagent panel, subagent session (it has none of its own).

**Kind chip** - The small label at the start of a live line that says what the agent is waiting on: Thinking, Read, Search, Edit, Shell, the server of an MCP call, "N subagents" or "Needs you".
The timer beside it is the running call's.
_Avoid_: badge, tag, status.

**Your turn** - The Carrier home's list of what needs the person: epics in human intervention, finished epics waiting to be tested, and engine problems, each with its action. It is not a status list; the sidebar already says which epics exist.
_Avoid_: inbox, notifications, to-do.

**Running epic card** - The Carrier home's card for an epic that is running: its progress and one row for each agent working on it. A dashed card after the running ones stands for free room and names the next queued epic.
_Avoid_: slot tile, agent list.

**Sidebar group** - A section of the Carrier section's list in the app's sidebar that collects epics by state (Needs you, Running, Up next, Ready for test, Done, Cancelled) or, when asked, by repository. Every group collapses; Done and Cancelled start collapsed.
_Avoid_: category, folder.

**Home** - The app's first page: a welcome with no status. The app opens on it and the sidebar's Home row selects it. Status lives elsewhere: the engine's on the Carrier card, a user session's on its own row.
_Avoid_: overview, dashboard, start page.

**Carrier home** - The page of the Carrier world, opened by selecting the Carrier section: what the Overview was (Your turn, the running epic cards, up next, the watched repositories) and the engine's controls (Check now, Pause, Stop). The Sessions world has its own, the Sessions home.
_Avoid_: Overview (its old name), dashboard.

**Sessions home** - The page of the Sessions world, opened by selecting the Sessions row. An empty state ("No sessions yet") until user sessions exist. The Carrier world has its own, the Carrier home.

**Archive page** - The page opened by the sidebar's Archive row, which stands on its own outside Sessions and shows the count of archived user sessions. An empty state until user sessions can be archived.

**Carrier section** - The sidebar section for the automation, drawn like every other: an icon, the title Carrier, the engine's state (Running, Paused, Stopped or Problem, or Connecting in grey while it has not answered yet), the search and group-by actions, and its slots as bars at full width, grey while nothing runs. It shows no counters: the groups under it carry their own counts. Selected, it unfolds into the sidebar groups and the Carrier home shows in the centre. Only one of the Sessions, Carrier and Archive sections is open at a time.
_Avoid_: Carrier card (its old name, when it was a filled card with counters), status bar, footer, pill (the pill is the engine's state inside the section).

**Sidebar section** - A destination of the sidebar that is drawn as an icon, a title and its actions, with no fill at rest and a light grey fill, never the system blue, only on that row when it is selected. Home, Sessions, Carrier, Archive and Settings are sidebar sections; Sessions, Carrier and Archive unfold a list under the row that has no fill of its own, a search field under the row, and an empty state when there is nothing to list or nothing matches.
_Avoid_: card, tab, panel.

**Attention colours** - The two colours the macOS app uses for an epic that cannot go on alone: orange when a person's input is needed (the review limit was reached, the agent asks for help), red when something failed (retries exhausted, a timeout, failed authentication, a workspace problem, an invalid pull request). A kind the app does not know is orange, because a person has to act either way. Cancelled is neither: nothing is asked and nothing failed, so it is grey. Both colours still sit under the same "Needs you" group; only the colour tells which of the two it is.
_Avoid_: warning colour, error orange, problem state.

**Settings group** - One heading of the Settings sidebar, by what its pages are about: App (how the app looks and behaves on this Mac: the app's preferences and what both processes share, the accounts of `providers.json`), Workspace (the chat and its sessions, sidebar and terminal), Carrier (who works on an epic and what it watches) and System (the engine, whether this Mac is ready, and About). App has no heading and comes first. A page belongs to one group.
_Avoid_: tab (a page is a row of the sidebar, not a tab), section (that is a part of a page, or a sidebar section), category.

**Legacy group** - The Settings group that held the pages that existed before the groups. It is gone: its last page, Health, is in the Carrier group.
_Avoid_: old settings, misc, other.

**Terminal owner** - The Carrier context that owns a group of embedded terminal tabs (`session` for a chat session, or `quick` for standalone quick terminals), defining their lifecycle boundary and default working folder.
_Avoid_: project workspace (in Carrier UI and docs, workspace means the project folder), thread, terminal parent.

**Terminal tab** - One named workspace item inside a terminal owner's strip that holds a binary split tree of one or more terminal panes, tracks its active and zoomed pane, and can be reordered, restored on launch, or closed as a unit.
_Avoid_: terminal session (session already refers to an agent conversation).

**Terminal pane** - One live shell surface and PTY inside a terminal tab, preserving its terminal state, scrollback, working directory, and running-process status while being split, resized, focused, moved across split edges or tabs, or closed.
_Avoid_: surface, panel, split (when naming the leaf terminal itself).

**Keep awake** - Holding the Mac from sleeping on its own, with the system's power assertions and no password, so a long job is not cut by sleep.
It is asked for by hand (a length, or no end) or, with its switch on, by the agents working (an epic running or a chat session working, and for a grace after).
It pauses on a low battery as the person set it, and it does not stop the lid or Sleep in the Apple menu.
See [keep-awake](../macos/keep-awake.md).
_Avoid_: caffeinate (the command it replaces), prevent sleep, wake lock.
