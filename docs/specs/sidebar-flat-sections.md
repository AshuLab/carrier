# The sidebar's sections lose their cards and open flat

Status: spec

## Problem

Diego uses the macOS app's sidebar all day, and what it draws is inconsistent and hard to read. Home and Sessions are plain rows, Archive is a plain row with a count, and the Carrier is a grey filled card with a state pill, the slots as bars and four counters; the same kind of destination is drawn three ways. The selected row is the system's blue, and white text over that blue is hard to read in the card and in the lists. The row icons are large next to the text. The card never says what it is: it shows a pill that reads `Running` and no title.

Two things are said twice. The card's counters (needs you, running, next, ready) repeat what the list right under it says, because the epics are grouped by exactly those states. And Sessions has an orange count of the sessions that wait for the person: orange is the colour of an alarm and a session waiting is a normal state, and the count says nothing of how many conversations there are.

It also leaves no place for what a section needs once it is real: where a search field shows up when the magnifier is clicked, and what a section says when it has no sessions, no epics, nothing archived, or no match. Diego knows it is fixed when every section looks like the same thing, reads well when chosen, and answers the empty and the no-result cases with a sentence and not a blank.

## Solution

Every destination of the sidebar becomes one kind of row, a sidebar section ([glossary](../glossary.md)), and the Carrier card goes away. The interactive design is `docs/research/macos-app-design/explorations/sidebar-flat-sections.html`, light and dark.

A section is an icon of 15 points, a title and, when it has them, its actions on the right. At rest it has no fill and no border; hover is a faint grey and the selected row is a light neutral grey with no border, so the text stays readable. The list's own selection (the system's blue) is turned off for these rows and the view draws the fill. The fill covers only the row itself (icon, title, actions and, for Carrier, the slots) and never what unfolds under it; the rows of that list are filled only when chosen, and the list has no side margin. At most one of Sessions, Carrier and Archive is open at a time, as today, and the open one is still remembered between launches.

Home is a normal row. Sessions shows a count badge of the open conversations, every session except the archived ones, in a soft neutral grey and not orange, with the actions search, sort and new session. Selected, the sessions unfold under it with the grouping and the three orders that exist today: by workspace by default, by age and by status, with the group headers carrying their count and the + on a workspace header that appears on hover. Archived sessions are never in this list, searching included. Carrier shows its title, the engine's state, the search and group-by actions and the slots bar at full width with no `2/3` text, and that is all, selected or not: no counters, and no line about the next check, since the Carrier home already has what the engine is doing. The epic groups keep today's names (Needs you, Running, Up next, Ready for test, Done, Cancelled, the last two folded) with a count on each header. A stopped engine shows the pill `Stopped` and the same slots bar in grey, because nothing is running; there is no extra empty state or Start button for it. Settings is alone at the foot under the divider, and Archive is a fixed row above that divider with its count and a magnifier; selecting it does not replace the list, the row moves up and its archived sessions open under it, up to about five before they scroll, newest first under the age groups that exist today.

The search is the same in the three sections. The magnifier, or ⌘F for the open section, opens a field directly under the row and above its list and gives it the keyboard; the magnifier stays pressed while it is open. The list filters as the person types, keeping its groups and hiding the ones with no match; the field gets a clear button once it has text, and esc or a second click on the magnifier closes it and clears it. Sessions and Archive match the title, the workspace and the agent; Carrier matches as it does today. When nothing matches, the list is replaced by a no-results state: a struck magnifier, `No results`, `Nothing matches “query”` and a `Clear search` button.

The empty states use the same shape. Sessions with none says `No sessions yet` with a `New session` button (disabled, with its reason, while starting sessions is not available), Carrier with no epics says `No epics yet` and that an issue labelled `solve:epic:ready` is what starts one, and Archive with nothing says `Nothing archived`. While a section is empty its count is hidden and its magnifier is dimmed, because there is nothing to search.

The exploration draws only the by-status grouping of Sessions, which is one of the three orders; the by-workspace default is what is built and tested, so the page's list is not the final default.

What was cut. Keeping the Carrier as a card with counters: five ways of showing the four counters were drawn (rows with dots, tinted chips, number columns, a pipeline bar and a sentence) and then the counters were dropped altogether, since the grouped list under the card says every number. Showing the counters only while the card is selected, for the same reason. The orange badge on Sessions, which reads as an error. A card for every row (each destination boxed alike) and navigation split from work with headers: the first fills the sidebar with boxes, the second splits what Diego reads as one list. Replacing the sidebar's list with Archive's when it is selected, which would hide the other sections while one reads the archive. A Start button and an empty state for a stopped engine.

## Scope

1. As Diego, I see Home, Sessions, Carrier, Archive and Settings as the same kind of row, an icon, a title and actions, with no fill at rest.
2. As Diego, a selected row is a light grey I can read the text on, not blue, with no border, and the fill covers only the row (and, for Carrier, its slots), never what unfolds under it.
3. As Diego, I see the Carrier named, with its state, the search and group-by actions and its slots bar at full width, and no counters, whether it is selected or not.
4. As Diego, with the engine stopped I see `Stopped` and the slots bar in grey, not an empty gap.
5. As Diego, I see on Sessions the number of open conversations, archived ones left out, in a soft grey badge, and nothing orange.
6. As Diego, selecting Sessions or Carrier unfolds its list with no side margin and only one of the two is open at a time; the sessions keep the order by workspace, age and status with the headers' counts and the + on a workspace header.
7. As Diego, I open the search of Sessions, Carrier or Archive from its magnifier or with ⌘F, I type in a field right under the row, the list filters live keeping its groups, and esc, a second click on the magnifier or the clear button closes or empties it.
8. As Diego, when a search matches nothing I see a no-results state with the text I typed and a Clear search button.
9. As Diego, when there are no sessions, no epics or nothing archived, I see an empty state for that section that says so, its count is hidden and its magnifier is dimmed.
10. As Diego, I see Archive above the foot's divider with its count, and Settings alone under it; selecting Archive opens its sessions under the row, up to about five before it scrolls, and the archived ones appear nowhere else in the list.
11. As Diego, everything above works in light and dark.

## Decisions

The model keeps deciding what each row says, and the views stay a mapping. What changes, in `macos/Sources/CarrierCore`:

- `Sessions` gains `open`, the count of the rows that are not archived, for the badge. `waiting` stays for the grouping and the row dot; `waitingLabel` and the orange capsule in `SessionsRows` go. The accessible name of the badge is the count in words (`1 open session`).
- `sessionGroups` with a query keeps the groups of the chosen order filtered to the matches, and lists no archived row. Archive has its own `archivedGroups(_:query:now:calendar:)` over the archived rows only, by the age buckets, newest first, with the same match on title, workspace and agent; today's flat `Results` group and the dimmed, tagged archived rows in the Sessions search go.
- `carrierCounters`, `CarrierCounters` and their line leave `CarrierCard`. `CarrierCardState` keeps the pill word and the slots; its slots are present for a stopped engine too, taken from the last total the engine reported and remembered in `SidebarStore` between launches, drawn in grey; with no total ever known no bars are drawn, as today, and while connecting there are none. The group counts are `SidebarGroup`'s own (its rows' count), for the header.
- A `SidebarListState` value for what a section's list says: has rows, empty, or no match for a query. The three sections draw their empty and no-results states from it. `EmptyState` (`EmptyStates.swift`) grows the cases for no epics and for no results, with the icon, title and line of the exploration.

The views: one `SidebarSectionRow` for icon, title, actions and optional slots, with the fill drawn on it and not by the list's selection, which is what makes the fill stop at the row. `SessionRowView` is reused by the Archive list. The search field, its clear button and the no-results and empty blocks are one view shared by the three sections.

Testing seams. Stories 5, 6 (order and counts), 7 (what the filter returns), 8 and 9 (which state a list is in) go through the model seams the sidebar already has: `SessionsSidebarTests.swift` for `Sessions.open`, `sessionGroups` with and without a query, `archivedGroups` and `SidebarListState`, `SidebarTests.swift` for the group counts, the stopped state's slots and the removal of the counters, and `EmptyStatesTests.swift` for the new cases (it pins the number of states and that icons and titles are unique, so its counts change). Stories 1 to 4 and 10 and 11 are visual: the fill, its reach, the grey bars, the margin, the field's place, the Archive row moving up and the readability in light and dark have no automated test; Diego checks them against the exploration page, in light and dark, at the narrowest and the widest sidebar. The existing view test in `Tests/CarrierTests/EmptyStateViewTests.swift` covers that each empty state draws something.

## Out of scope

The Carrier home, the Sessions home and the Archive page in the centre. What the second line of a session or an epic row says (see [rows with the title first](sidebar-rows-title-first.md)). Starting a session and the engine's behaviour. A Start button or its own empty state for a stopped engine. New orders for the sessions.
