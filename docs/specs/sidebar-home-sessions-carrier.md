# The sidebar keeps Home, Sessions and Carrier apart

Status: spec

Superseded in part by [the flat sections](sidebar-flat-sections.md): the look of every row and of the selection, the Carrier card (now the Carrier section, with no counters), the Sessions badge (the count of open sessions, in grey), the place of Archive and the search and empty states. The rest of this spec stands.

## Problem

The macOS app is about to have two worlds: the automation Carrier already is (epics the engine runs on its own) and conversations the person starts with an agent of their choice, called user sessions (see [the research](../research/in-app-sessions.md) and [ADR 0012](../adr/0012-sessions-and-epics-are-two-separate-worlds.md)). Its sidebar has room for one: an Overview row that is both the landing page and the engine's page, a Status | Repository switch that is always on screen, the epic groups as the whole body of the list, the engine's status as a card pinned at the foot, and Settings and About rows (`SidebarView.swift`; story 11 of [the macOS redesign](macos-app-redesign.md)). There is nowhere to put sessions, nothing says which part is the automation, and the first screen is the engine's page even for someone who opens the app to talk to an agent.

Two epics will work in parallel, this one on the sidebar and another on the sessions themselves. If the sidebar is not settled first, or at least in step, the second one rebuilds it. We know because the sessions epic has to add a row, a list, a search, a sort menu, an archive and a new-session button to a sidebar whose structure and selection model were not made for them.

## Solution

The final sidebar is built now, as designed in `docs/research/macos-app-design/explorations/sidebar-w5-spec.html` (every element, its click behaviour, its states), and its Sessions half is left ready for the next epic to fill: it draws from plain values that this epic defines and fills from a dev fixture, because the engine and the chat do not exist yet.

The sidebar, top to bottom. A Home row: a house and the word, nothing else, no status. A Sessions row as clear as Home, with a chevron, a search button, a three-dots menu to sort by workspace, by age or by status, and a + for a new session; under it the list of sessions, grouped by workspace by default. An Archive row, its own item, outside Sessions, with the count of archived sessions. The Carrier card: grey, no border, with the engine's state (Running, Paused, Stopped or Problem), the slots as bars and counters for what needs the person, is running, is next and is ready; selected, it opens into the epic groups that exist today (Needs you, Running, Up next, Ready for test, Done, Cancelled), with a search and the same choice of Status or Repository, now behind a three-dots menu instead of the always-visible switch. Settings at the bottom. About leaves the sidebar and goes to the menu bar item's menu, which is the app's menu, opening the same sheet.

At most one of Sessions or the Carrier card is open at a time, so neither is squeezed: opening one folds the other to its row. Selecting a session or the Sessions home opens Sessions; selecting an epic or the Carrier home opens the card; Home, Archive and Settings leave it as it is. The chevron of the Sessions row folds it, and then both can be folded. A folded Sessions row shows an orange count of sessions that wait for the person; the folded card shows its counters. Which one is open is remembered between launches, and Sessions is open the first time.

There are seven destinations and each has a page in the centre. Home is a welcome with nothing in it yet, and the app opens on it, with or without Carrier answering. The Sessions home and the Archive page are empty states until the sessions epic. The Carrier home is the old Overview with a new name (Your turn, the running epic cards, up next, the watched repositories, and the Check now, Pause and Stop buttons) and is opened by selecting the Carrier card; its content is not redesigned here. A session, an epic and Settings open as they do or will. Home is ⌘1, the Sessions home ⌘2 and the Carrier home ⌘3, and ⌘F opens the search of the section that is open. Opening the window from the menu bar item lands on Home; a notification or an epic row in the menu opens that epic.

The Carrier card's search matches the epic's title, its #number and its repository, in every group including Done and Cancelled (within their finished window), opens the group that matches, and keeps the groups, filtered, in both groupings; it is not remembered and esc closes and clears it. The Sessions search matches a session's title, workspace and agent, and lists the results flat with the archived ones dimmed and tagged. The choice of Status or Repository, the order of the sessions and the open section are remembered between launches.

The card's state maps what the engine already tells the app: running, paused when intake is paused, stopped when it does not answer, and a problem when the snapshot reports one or the engine's version is incompatible; while connecting it says so in neutral grey, with no slots. The line that says when the next check is moves to the card's hover, with the uptime and the rate limit, and stays on the Carrier home's subtitle.

What this epic leaves ready for the sessions epic: the plain values the Sessions half reads, the selection cases for a session, the Sessions home and the Archive page, and a dev fixture with sample sessions so the design can be checked. Until that epic lands the Sessions list shows its empty state, "No sessions yet", the + is disabled with a tooltip that says so, and the search and the sort menu work on whatever the list holds.

What was cut. Shipping the Carrier card open-only, without its folded form or the accordion, and leaving those to the sessions epic: Diego wants the final visual now, in step with the sessions work. Hiding the Sessions and Archive rows until they have content: it would mean a second pass over the sidebar. A rail of icons with a list beside it, a split with a draggable divider, a switch between the two worlds, and the drawer variants were all drawn and tried in `explorations/` (`sidebar-chats-options.html`, `sidebar-rail-options.html`, `sidebar-sessions-options.html`) and lost: the rail was too different from today's sidebar, the switch hides one world, the split halves both. Landing on the Carrier home until Home has content: Diego chose the empty Home.

## Scope

1. As Diego, I open the app on Home, a welcome with no status, whether or not Carrier is running, and the Home row in the sidebar is only a house and its name.
2. As Diego, I see the Sessions row with its chevron, a search button, a three-dots menu and a +, and clicking the row opens the Sessions home and unfolds the list.
3. As Diego, I see the sessions grouped by workspace, and I can change the order from the three-dots menu to by age (Today, Yesterday, Last 7 days, Older) or by status (Waiting for you, Working, Idle, Done); the choice is still there after a relaunch.
4. As Diego, I search the sessions from the magnifier or with ⌘F: a field opens under the row, the matches are one flat list with the archived ones dimmed and tagged, and esc closes and clears it.
5. As Diego, while there are no sessions I read "No sessions yet", the + is disabled and its tooltip says why; with the dev fixture I see sample sessions, one waiting for me, one done, and archived ones.
6. As Diego, with Sessions folded I see an orange count of the sessions that wait for me, and nothing when none does.
7. As Diego, I see the Archive row, outside Sessions, with the count of archived sessions, and it opens the Archive page.
8. As Diego, I see the Carrier card, grey and with no border, with the engine's state, the slots as bars and the counters Needs you, Running, Next and Ready; clicking it opens the Carrier home and the card opens into the epic groups.
9. As Diego, with the card open I search the epics from its magnifier or with ⌘F by title, #number or repository, including Done and Cancelled, and the groups that match open.
10. As Diego, I change how the epics are grouped, Status or Repository, from the card's three-dots menu, and it is remembered between launches as it is today.
11. As Diego, opening Sessions folds the card and opening the card folds Sessions, and the sidebar remembers which was open when I relaunch.
12. As Diego, I see the engine's state as Running, Paused, Stopped, Problem, or Connecting in grey, and hovering the card shows when the next check is, the uptime and the rate limit.
13. As Diego, I find Settings at the bottom of the sidebar and About in the menu bar item's menu, where it opens the window if it was closed and shows the same sheet.
14. As Diego, I see the old Overview as the Carrier home, titled Carrier, with its cards and its Check now, Pause and Stop buttons, and they appear only there.
15. As Diego, I move between Home, the Sessions home and the Carrier home with ⌘1, ⌘2 and ⌘3 while the window is in front.
16. As Diego, every icon button in the sidebar has an accessible name and a tooltip, the counters are read out as words, and none of it depends on colour alone.

## Decisions

The sidebar's content is plain values in `CarrierCore` that the views map one to one, as `Sidebar.swift` already does; nothing here touches AppKit or SwiftUI. The selection and the open section, trimmed to the decision:

```swift
public enum Selection: Hashable {
    case home
    case sessions                       // the Sessions home
    case session(id: String)
    case archive
    case carrier                        // the Carrier home, the old Overview
    case epic(repo: String, issue: Int)
    case settings
}

public enum OpenSection: String { case sessions, carrier }   // WindowShell.open: OpenSection? , nil when both are folded
```

A new window and `reset()` select `.home`. Selecting `.session` or `.sessions` sets `open = .sessions`; `.epic` or `.carrier` sets `open = .carrier`; `.home`, `.archive` and `.settings` leave it. Opening one section by its header folds the other.

The values the Sessions half reads, which the sessions epic feeds and may extend:

```swift
public enum SessionSort: String, CaseIterable { case workspace, age, status }
public enum SessionState { case working, waiting, idle, done }
public struct SessionRow: Equatable {
    public var id: String; public var title: String; public var workspace: String   // the folder's name
    public var agent: String; public var state: SessionState; public var updatedAt: Date; public var archived: Bool
}
public struct SessionGroup: Equatable { public var title: String; public var rows: [SessionRow] }
public func sessionGroups(_ rows: [SessionRow], by: SessionSort, query: String, now: Date, calendar: Calendar) -> [SessionGroup]
```

The rules of `sessionGroups`. Archived rows are never in the lists, only in search results. By workspace: groups ordered by name ignoring case, rows newest first. By age: the groups Today, Yesterday, Last 7 days and Older, counted from the start of today in `calendar`, empty ones hidden, rows newest first. By status: Waiting for you, Working, Idle and Done in that order, empty ones hidden, rows newest first. With a non-empty query the result is one group of the matches, ignoring case, over title, workspace and agent, the active ones newest first and then the archived ones. The count of waiting sessions and of archived ones are derived from the rows.

The epics' side. `sidebarGroups` takes a `query` and keeps its groups, filtered, with the empty ones hidden; a query matches the title, the issue number with or without `#`, and the repository's `owner/name`, ignoring case, and the view treats a collapsed group that has matches as open while the query is not empty. The counters come from the snapshot: Needs you are the epics in `needsHuman`, Running the running ones, Next the queue, Ready the epics ready for test; Done and Cancelled are not counted. The card's state is a pure function of the `ConnectionState`. The remembered values go in `SidebarStore` next to `groupBy`: `sidebar.sessionSort` and `sidebar.open`.

The Sessions + is enabled by a flag on the Sessions values that is false until the sessions epic sets it. The dev fixture is a sample set of `SessionRow`s shown only in `--fixture` mode; without it the list is empty.

The pages without content use the empty-state pattern (icon, title, one line) by adding cases to `EmptyState`, which the empty-states gallery lists: Home ("Welcome", "Pick Sessions or Carrier in the sidebar."), the Sessions home ("No sessions yet", "Sessions you start are listed here."), the Archive page ("Nothing archived", "Archived sessions are kept here."). Home does not depend on the engine: with Carrier stopped Home shows its welcome, and the Carrier home shows what the Overview showed when stopped.

The shortcuts are handled by the window, not by the menu bar item's menu, so they work only while the window is key: a pure mapping from the key to a `Selection` (or to "search") in `CarrierCore`, bound in the view. About is an item of the menu bar item's menu (the app becomes a regular app only while the window is open); it opens the window if it is closed, then calls `WindowShell.showAbout()`. The sidebar's About row, the Status | Repository `UnderlineTabs` in the sidebar and the status card at the foot are removed, not hidden.

No behaviour of the engine, the snapshot, the control socket or the menu bar item's other entries changes. Story 11 and story 31 of `docs/specs/macos-app-redesign.md` get a line saying this spec supersedes the part about the sidebar and the entry point of the About sheet.

Testing seams. Stories 3, 4, 6, 9, 10, 11, 12 and 15 are pure code in `CarrierCore` with Swift Testing in `macos/Tests/CarrierCoreTests/`: `SidebarTests.swift` for the epic groups with a query, the counters, the card's state and the remembered values; a new `SessionsSidebarTests.swift` for `sessionGroups` (the three orders, the buckets around midnight, the query, archived rows); `WindowShellTests.swift` for the selection, the open section and `reset()`, which already assert `.overview` and change to `.home` and `.carrier`. Stories 1, 2, 5, 7, 8, 13, 14 and 16 are the views and the menu: no unit tests, because they map the values one to one; each ticket carries a checklist run with `./Carrier.app/Contents/MacOS/Carrier --fixture $PWD/DevFixtures` and `--smoke-window`, checking the column widths, in light and dark, with the "many" case (ten sessions, six workspaces, seventeen epics) and with a long title, as the macOS UI workflow already does.

## Out of scope

The content of Home beyond an empty welcome; the content of the Sessions home and the Archive page; real sessions, the conversation view, the new-session draft and the workspace picker; the chat host and anything in the engine; redesigning the Carrier home (it is renamed, not changed); the Settings screen; Take over; changes to the menu bar item beyond where it opens the window and the new About entry; a change to the About sheet's content.

## Open questions

Whether the card, the accordion, the rows with icon buttons and the popovers can be built inside the native sidebar list, or need a custom list; the app already ran into AppKit limits with the inspector, so this wants a small prototype in the first ticket before the rest is built on it.
