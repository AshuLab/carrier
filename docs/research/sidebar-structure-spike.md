# Spike: can the new sidebar live in the native `List(.sidebar)`?

Answers the open question of [the sidebar spec](../specs/sidebar-home-sessions-carrier.md) before the rest of epic #408 builds on it. The prototype is kept in [`spike-sidebar/`](spike-sidebar/); the design it follows is `macos-app-design/explorations/sidebar-w5-spec.html`.

## How it was tried

A SwiftUI `NavigationSplitView` in an `NSHostingController`, the shape of the app's window (`WindowController.makeWindow`), with the sidebar in `spike-sidebar/Sources/Sidebar.swift`: a Home row, a Sessions row with a chevron and three icon buttons (search, sort, new) and three session rows under it, an Archive row, the Carrier card with three epic rows under it, and Settings in a footer. The probe (`Probe.swift`) drives it from code: it finds each row and button in the AppKit views under the list (`ListTableRowView`, and a `KeyViewProxy` for each SwiftUI button, which carries the button's frame), sends real mouse events to the window, and prints the selection, the open section, what each button did, which rows carry the system's selection highlight and the popovers on screen. Run on macOS 26, Xcode 26.

Two things the probe cannot see: how it looks (the machine gives no screen-recording permission, and drawing the layers into an image leaves the sidebar's glass blank, so nothing below was checked by eye) and keyboard navigation. Both are on the checklist of the tickets that build the real thing.

## The five things

**A card that opens into a list and folds back to a summary.** It worked. The card is one row of the list (`SpikeCard`, tagged `.carrier`, 72 points high against 40 for a plain row) and the epics are rows that exist only while the card is open (`if model.open == .carrier { ForEach … }`). Clicking the card selected it and opened it (`selection=carrier open=carrier`), the three epic rows came after it and clicking one selected it (`selection=epic(1)`, highlight on that row). Folding it takes the epic rows out of the list and leaves the summary. One thing to know: the system draws its selection pill under a selected row, and `listRowBackground(Color.clear)` does not remove it (the card's row carries an `NSVisualEffectView` while selected, the same one the plain rows get). So a selected card has the system's highlight and the card's own grey fill on top of each other; the card should draw its fill only while it is not selected, or the next ticket should look at it and pick.

**A section that folds to a single row.** It worked two ways. As rows (the Sessions row is a tagged row and its sessions are rows that exist while `open == .sessions`) the chevron is a plain button of ours: clicking it took the list from 7 rows to 4 and back, without changing the selection. As a `Section(isExpanded:)` with the buttons in its header, the system draws the disclosure chevron and folding also worked (7 to 4 rows), but a header is not a selectable row: it takes no highlight (`highlighted rows=[]` after selecting Sessions) and the click that selects Sessions has to be a tap gesture of ours (`onTapGesture`), with the highlight drawn by hand. The row version does what the spec asks of the Sessions row (clicking it selects the Sessions home and the system highlights it); the section version does not. I did not try animating the fold; the rows come and go with the list's default animation.

**A row with three icon buttons at its right that do not select the row.** It worked. Inside a tagged `HStack`, `Button { … } label: { Image … .frame(width: 22, height: 22).contentShape(Rectangle()) }` with `.buttonStyle(.plain)`, `.help` and `.accessibilityLabel`. Clicking the magnifier, the three dots or the plus ran the button's action (`log=["search","sort","plus"]`) and the selection stayed where it was (`selection=home`, highlight still on Home), while clicking the row's label or the empty space beside the buttons selected the row (`selection=sessions`, highlight on row 1). The buttons are separate focus targets of the row (four `KeyViewProxy`s in it, at x 16, 182, 206 and 230). The first click on a window that was not key only activates it and selects nothing, as on any Mac window; the probe sends one before it starts.

**Popovers anchored to one of those buttons.** It worked. `.popover(isPresented: $model.sortPopover, arrowEdge: .trailing)` on the button itself opened an `_NSPopoverWindow` (127 x 138) whose edge was 0 points from the button's right edge and centred on it; the same on the plus button gave a 158 x 69 one, 24 points (one button) further right. Opening a popover did not change the selection, and a popover over a list row did not disturb the list (7 rows before and after). The native `Menu` was not tried: a popover is what the design draws for the sort menu, and it lets the new-session tooltip and the sort choices share one approach.

**One selection across the Home row, the Sessions list, the Carrier card's list and Settings.** It worked with one catch. One `List(selection:)` bound to one `Selection?` moved across Home, the Sessions row, a session, the card, an epic and Archive, each click highlighting exactly its row and un-highlighting the previous one. Settings is not in the list: it is a button in a `safeAreaInset(edge: .bottom)` (what the app's `SidebarFooterRow` already is) that sets the same selection; with `selection == .settings` the list has no highlighted row (`highlighted rows=[]`), which is right, and the footer draws its own highlight by hand. Selecting a session or the card also set the open section (`open=sessions`, `open=carrier`), because the binding's setter goes through one `select(_:)` that applies the spec's rules.

Not a limit of the native list but the reason this was a question: the `.inspector` loop the app hit is about the right panel, which the app already replaced with its own. The prototype has no inspector. As a check that the list adds no layout loop of its own, the probe resizes the window between 1100 and 1400 wide and folds and unfolds Sessions at the same time, 40 rounds: it survived, with no AppKit message.

## Decision

The sidebar is built on the native `List(.sidebar)`, not on a list of our own. Nothing in the five things needed to leave it; the two rough edges (the card's double fill, the footer's hand-drawn highlight) are small and known, and a list of our own would mean redoing the sidebar's material, selection, keyboard navigation, scrolling under the title bar and the collapse with the toggle, which the native one gives for free. What the following tickets build on:

- Card: one tagged row (`SpikeCard`) with `listRowBackground(.clear)` and its own grey fill, drawn only while it is not selected so it does not stack on the system's pill; the epics are rows after it while it is open.
- Fold: rows that exist while the section is open, driven by `WindowShell.open`, with the chevron a plain button of ours; not `Section(isExpanded:)`, whose header cannot be selected.
- Icon-button row: a tagged `HStack` of a label and plain 22-point buttons that have `.help`, an accessibility label and a `contentShape`; the spec's row selects, the buttons do not.
- Popover: `.popover(isPresented:)` on the button that opens it, arrow on the trailing edge.
- Selection: one `List(selection:)` over the plain `Selection` of the spec, a single setter that also sets the open section, and Settings as a footer button with its own highlight, as `SidebarFooterRow` does today.

## The prototype

`spike-sidebar/` is a SwiftPM package of its own, outside `macos/Package.swift`, so no shipping target builds it.

```
cd docs/research/spike-sidebar
swift run                                  # the window
swift run SpikeSidebar --probe             # clicks through the five things and prints what happened
swift run SpikeSidebar --probe --variant section   # the Section(isExpanded:) version of Sessions
```

The probe needs the window in front; when it is not key (another app took the focus) the row clicks do nothing and the output says `key=false`, so run it again.

`Sidebar.swift` is self-contained (SwiftUI only, every type prefixed `Spike`) so it can be dropped into the app's window. To check the chosen approach in the real window with the dev fixtures: copy it to `macos/Sources/Carrier/`, replace the `SidebarView(…)` in `PanelView.swift` with `SpikeSidebar(model: SpikeModel())`, run `./build-app.sh` in `macos/` and then:

```
./Carrier.app/Contents/MacOS/Carrier --fixture $PWD/DevFixtures --smoke-window
```

Run that way it exited 0 and printed `column: x 0 width 268` and `column: x 0 width 1100`, so no column wider than 1100, with the rest of the structure as without it (min content size 1100 x 600, the epic's scroll pocket, the toolbar, `transcript: lazy stack, pinned section headers`). The temporary edit was taken out again; the shipping app is untouched.
