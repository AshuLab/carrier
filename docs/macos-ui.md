# The look of the macOS app

How the pieces of `Carrier.app` are drawn, so that a new screen or a change reuses what is there and looks like the rest. It was written down while polishing Settings (Providers and Repos first); the pieces live in `macos/Sources/Carrier`. **Before adding a button, a field, a select, a row or a line, look here, then at the file named, and reuse it. Do not draw a new one, and do not use the system's plain control where a piece below exists.** When a piece is missing, add it next to the others and add it here.

**What belongs here**: how to use the pieces and the rules that keep the app looking like one product (sizes, colours, which piece for which job, what not to do, mistakes already made).
What does not: what a screen shows and why (that is [`docs/macos/`](macos/app-shell.md)), where the code lives and what is tested (that is [`macos/AGENTS.md`](../macos/AGENTS.md)), and what changed (that is the CHANGELOG and the PR).
When a rule needs a reason to not be broken again, give it one sentence under it.

Nothing here is checked by a test: a view is looked at in the app (`macos/build-app.sh --open`, see [the app's README](../macos/README.md#build-and-open)), not only compiled.

## The page

A Settings page is groups of rows under the window's toolbar, which says what page it is (`SettingsWindow.swift`, `SettingsTabs.swift`).
Settings is a window of its own with a native sidebar (`List` in `.sidebar` style, a colored tile before each name, `SettingsTile`) and a toolbar: the page's name is the title and its line the subtitle, ‹ › go back and forward, the page's note (`SettingsNoteView`) and, only on a page that has a Reset, the ⋯ menu are at the right. A page with screens of its own (Providers) sets its screen's title and subtitle (`SettingsTitle`), a screen that edits something (an account) asks the toolbar for its Save or Add (`SettingsSave`), on an accent glass pill with the verb's own icon (Save a check, Add a plus), and a screen with a toggle in its header (Pin on a project's page) asks for a `SettingsHeaderAction` pill (`ToolbarPillButton`). There is no header inside the page and no close button: ⌘W closes the window.

| Piece | What it is |
|---|---|
| `SettingsPageBody(reset:)` | What a page is made of. A page in `SettingsPage.usesForm` gets a native `Form` (`.formStyle(.grouped)`: its groups are sections, its rows labeled content, and the form scrolls by itself); the others (the repos, the checks) keep a column of cards in the window's scroll. Give it `reset` and the toolbar's ⋯ menu runs it after asking "Reset <page>?": a page does not draw its own Reset card. |
| `SettingsGroup(title:)` | A small uppercase title over a card, or a `Section` of a form. `footer:` is the longer word about the whole group (under the card or the section), so a row's own line stays short; `SettingsGroup(title:accessory:content:)` puts a control at the right of the title (the models table's recognizer chips). |
| `StatusChip(text:tint:)` | A capsule with a word in it, its colour at 16 % under the same colour; the word carries the state, never the colour alone (Dictation's models table: Live, When you stop; Usage's Stale). |
| `Badge(text:icon:tint:)` | `StatusChip` with a symbol before the word (`SheetParts.swift`). As the label of a plain `Button` it is a small action that is also a state: Usage's `Unpriced · Map` (orange) and `Custom` (secondary) open the price sheet; give the button an `accessibilityLabel` that says what it does. |
| `SettingsTabCard` | The card: 14 pt side padding, rounded 14, `secondary` at 7 %. |
| `SettingsTabRow` | A row of a card (a `LabeledContent` in a form): title, detail (and `note`, a quiet monospaced third line, cut in the middle to one line, with its whole text as a tooltip and selectable to copy), the control at the right. `leading:` is a tile at the left of the title (Providers' `AccountTile`: the account's mark, 22 pt, in a 38 pt rounded square at `primary` 7 %, so it reads as an avatar); the rest of the row keeps its place. `first: true` on the first row (no line above it). `roomy: true` for a form with many stacked fields (14 pt above and below instead of 10). |
| `.settingsCard()` | The card's background as a modifier (rounded 14, `secondary` at 7 %), for a list, a note or a card that is not a group of rows. Never write the fill out again. |
| `.sectionLabel()` | The type and colour of the small uppercase title (`caption2`, semibold, `secondary`, upper case by `textCase`), for a title that cannot be a `SettingsGroup` (a list's label, the owners of a picker). The caller adds the padding its place needs; write the text as a normal sentence, not in capitals. |
| `SettingsDivider` | The line between two rows: 1 pt, `primary` at 7 %. `SettingsDivider(vertical: true)` is the line between two columns (Usage's four figures); give their `HStack` `.fixedSize(horizontal: false, vertical: true)` so the line takes the height of the tallest. |
| `EmptyStateView` | Icon, title and one line, centred. For nothing to show: not installed, not running, no model. Give it `.frame(minHeight: 260)` inside a page, or the height of what it stands for inside a card (Usage's chart, 220, so the card does not jump). Its `action` is the way out (Clear filters), a `SecondaryCapsuleButtonStyle` capsule by default or an `AccentGlassPillButton` (`actionStyle: .accentGlass`) with `actionIcon` before its words. `LoadingStateView` is its twin while something loads. |
| `ShortcutRecorderRow` | A row to record a global shortcut (`GlobalDictationGroup.swift`, used by Dictation's and Keep awake's pages): the keys in a cap, Record (Esc cancels) and, with `emptyText`, Clear. Every parameter that belongs to a consumer is required (`current`, `save`, `taken`, its words), so a new consumer cannot write over Dictation's by leaving one out; `problem` is why a recorded shortcut is not registered and `taken` refuses keys another feature has. While it listens it lets go of both global shortcuts, or pressing the old keys would run them instead of recording. |
| `SettingsPreview` | A sample of what the rows around it change, inside their group (the terminal's, the time format's, Dictation's widget style). |

Spacing: **14 between blocks, 4 inside a block** (a name and its version), 12 between a tile and its text. A row's line is one line: what does not fit goes to the group's `footer`.
A page of full-width lists (Repos, Health, the Projects list) has `isColumn` false, and a screen of its own that such a page opens (a project's) is a column all the same: `SettingsPlace.isColumn` says which, so the list takes the window and the screen is read as a line.
A list of things that open a screen (the projects) is a card of `NavigationRow`s, the first with `first: true` so no line is above it, each with its tile before the name; the empty list is an `EmptyStateView` in the same card with its one action as an `accentGlass` pill, and Add project over a list that has rows is a small Secondary button at the right above the card.
A row that stands for work that is not a place yet (a clone) is the same row with no chevron and cannot be clicked: its name with a `StatusChip` (Cloning in the accent, Failed in orange), the progress line or the reason under it (orange when failed) and, for a failure, a small Secondary Dismiss button at the end.
A page that is a column (`SettingsPage.isColumn`, `settingsColumnWidth`) is centered by `.contentMargins(.horizontal, _, for: .scrollContent)` on its scroll view and never by narrowing the view: the scroll bar stays at the window's edge and what scrolls under the toolbar reaches both sides of it.

**What can be searched is `settingsIndex`** (`CarrierCore/SettingsIndex.swift`): a new row or group is added there in the same change, with its page, its group and the words it says; `SettingsIndexDriftTests` fails when a title a page draws is missing. A row is found by its page, group and title, so the group a row is in and its title are not renamed without the index. The test reads titles only, not descriptions: when a setting changes what it does (a text size that stops reaching the messages, a density that stops setting their gap), grep the old words in `settingsIndex`, the row's own detail, `docs/macos/settings.md` and the specs, and fix each description that now says otherwise.

## Cards in the feed

One shell for every card that is "a line on top and rows under it": **`.workCard()`** (`WorkCard.swift`), a `primary` fill at 4.5 % under glass, rounded 12.
The tool group of a session, a markdown table, a slice, a review's findings and a closing line wear it, so the look is changed there once; never write the fill and the glass out again.
A surface of the conversation (that shell, the person's bubble, a code block, an attachment, a notice, an approval, the message box and its buttons) takes its glass from **`.chatSurface(_:flat:in:)`** (`ChatSurface.swift`), never from `glassEffect`: Settings > Chat > Surfaces turns it flat (the window's color under a quiet fill and a 1 pt edge, solid so what scrolls under it is not seen through it).
Work the agent did (calls, thoughts, messages, an error) is drawn with the chat's views (`ChatToolGroupView`, `MarkdownView`, `BannerView`) wherever it shows; do not draw a second tool card.

- **The line on top is 30 pt**: a 16 pt lead (`Disc`: green tick, orange or red "!", a turning ring, a hollow ring), a bold title, a quiet summary (12.5 pt, `secondary`), what is at the right that never moves (a time in `tertiary`, a `PullRequestChip`) and a `CardChevron` (9 pt, right when folded, 90° when open).
- **Kind chip (`KindChipView`)**: a small capsule on the live line of a call group (`ChatToolGroupView`) that names what the agent is waiting on (Thinking, Read, Search, Edit, Shell, an MCP server's name, subagents, or Needs you).
  Thinking uses the thought tint; Read, Search and Edit share the files tint; Shell, MCP, subagents and Needs you each take their own colour, and a long server name is cut on one line so the line stays 30 pt.
- **Two timers on the live line, and the slow call**: the timer at the right is the running call's own (`ToolGroup.liveTimer`), and the turn's time stands beside it in `quaternary` while it is longer; while no call runs (the agent is thinking) it is the turn's alone.
  A Shell or MCP call that has run for more than 30 seconds (`slowCallMs`; exactly 30 is not slow) draws its timer in amber (`Color.slowCall`) until it ends, and a Read, Search or Edit never does; nothing else of the line changes, and both timers are fixed-size so the line stays 30 pt at every width.
- **Subagent row (`SubagentRowView`)**: one subagent of a run, a card of its own under the run's line (6 pt below it, one per subagent in the order they started), built on `.workCard()` and so on `chatSurface` (flat when Settings > Chat > Surfaces says so).
  It is one line as high as the card's line (30 pt) at any width: a 16 pt lead (a turning ring while it runs, a green tick, a red mark, a square when stopped), the type as a `KindChipView`, the title (12.5 pt, semibold; it is the one that gives way last), the step it is on (`tertiary`; Finished, Failed or Stopped once it ended), "N steps" and its timer, those two never cut.
  A long title or step is cut, never wrapped, so the row does not change height.
  Where a conversation or a subagent view draws it, it is a `Button` as a whole (a 4 % fill under the pointer, a `CardChevron` at its end, the same 30 pt) that opens the subagent's view.
  While a subagent of a run is running the run's line reads "N subagents · Waiting for them…" (the chip is the count of those running) whether or not the turn has ended.
- **Subagent view (`SubagentView`)**: what replaces the conversation when a subagent row is tapped, one component that takes `SubagentWork` (header description, brief and flow items) and so serves the epic's slice card (`SliceCardView`, a row that opens it) unchanged.
  It is the brief as a bubble on the right with the label "Brief from the main agent" (`chatSurface`, tinted), then `FlowItemView` for the subagent's own groups, thoughts and messages (the same live line and chip, and the rows of the subagents it launched, which open in turn), and in the message box's place `SubagentNote`: a `workCard()` with "Subagent work is read-only." and a ‹ Back to chat button (‹ Back to Agent output from a slice card).
  All three are on `chatSurface` or the work card shell, so Settings > Chat > Surfaces applies.
  Its **header** is the window's toolbar (`PanelView`): the sidebar's round button, a round ‹ Back button (one level up) in the place of the window's own ‹ › (back and forward through the places chosen, which a subagent view does not draw, so there are never two ‹), then `SubagentTitle` (the description, 13 pt semibold, over "<type> · Subagent of <session title>", 11 pt `secondary`), and where the worktree pill is `SubagentStatePill` (Running with a timer, Finished · duration, Failed or Stopped); the panel button stays; a slice card's has the epic's title in the subtitle ("Builder · <epic>") and the pill where the epic's links are, and no Stop.
  While the subagent runs, a Stop `ToolbarPillButton` (red stop icon, on its own glass capsule) follows the state pill; it is gone once the subagent ended and never drawn for a host that does not list `stopTask`, nor for a slice card's subagent.
  `SubagentTitle` is 34 pt high (the round buttons') and cuts a long title on one line, so the header is as high as the conversation's at any width (`SubagentHeaderTests`, 480, 560 and 900 pt, four states, a 120-character title; a slice card's, Builder and Reviewer, three states).
  Its two lines follow the text size up to 14 and 12 pt and no further, because at 130 % they would be 39 pt and spill out of the toolbar (`theTitleLinesFitTheHeaderAtEveryTextSize`).
- **Rows hang under the line** behind a `SettingsDivider`, edge to edge.
- **A row that opens or links is one click target as a whole**: a 4 % fill under the pointer, and no lone small icon as the only way in.
  A `Button` or a `Link`, never only `.onTapGesture`: a tap gesture is not reachable with the keyboard.
- **An arrow that says "this opens GitHub" shows under the pointer**, not all the time.
- **A notice about an account wears its mark before the title** (`NoticeCard(account:)`, the failed turn's banner), only when the account has an icon, a color or a label; one with none shows the title alone, as the footer of an answer does.
- **Say a kind in a word, not in a dot** (`BLOCKER`, `SUGGESTION`): a colour alone is not read by everyone.
- **Open and fold a card with `flipCard`**: smooth, and none with Reduce Motion.
- **One thing, one card**: what a card's rows were checked by is its foot (a line under a divider), not a second card under it.

## The ring beside the microphone

`ContextUsageButton` (`ContextUsageButton.swift`), in the message box's row of an open session, left of the microphone and in the same 36 pt frame with the same round hover, so the two read as a pair; the draft has none (nothing to count yet), and Settings > Chat > Message box > Context and limits turns it off.
Two rings in the colors of `QuotaBar`: outside the context (`ContextUse.share`, what the last turn ended with over the model's window), inside the account's 5h (or Weekly, or Monthly, when it has no 5h); the theme's accent, orange from 90 % and no other color, over a `primary` 12 % track.
A share that is not known (no turn yet, a host that does not send the window, an account that is signed out) leaves that ring as its track alone, and the numbers of a stale check stay at half strength.
A click opens the system popover, which is glass without drawing anything: the context as a `UsageMeterLine` with its tokens under it, then the account's `AccountUsageMeters` (the Providers page's own, the bars hatched where the next reset gives the use back, the `Stale` chip, `Resets in …`), then Open Usage.
It does not repeat the account: the box's own pill names it.
Do not draw a third kind of meter for a percentage: the popover reuses `UsageMeterLine` and `AccountUsageMeters`.

## Rows of a feed

A feed that is a column of the window (the Agent output of an epic) is not made of boxes.

- **A header that folds what is under it is a centred row on the window with nothing behind it**: no background, tint or border, a one-point hairline that fades out on each side, and the whole row is the button (a `contentShape` over the row, with an `accessibilityLabel` and a hint that say what a click does).
  Do not draw a second kind of header for the same thing.
- **A row is the same size open or folded**; only its words change.
- **Gaps are a scale, nothing else** (`SessionMetrics`): each row carries its own gap above it, so the lazy stack stays flat (a nested stack would build every row of a long session at once).
- **Nothing is pinned over a feed that has no background**: the rows would scroll under its text.
- **The column is as wide as the chat's message width** (`appearance.messageWidth`), never a fixed one.
- **The text of a message (the agent's answer, the person's bubble) takes `.chatText()`, not `.scaled`**: its size and line spacing are the chat's own, which the app's text size does not multiply (the person's bubble and a subagent's brief pass `bubble: true`: they add no room between lines at Normal), and the gap between messages is `MessageSpacing.gap`, not the density. A font outside `ScaledFont.swift` still cannot be built from a number: use `Font.chat` / `NSFont.chat`.
- **What ends a feed (a stop that needs a person) is a `NoticeCard` as its last element**, never pinned: orange for what needs a person and red for what failed.
- **Every `NoticeCard` is glass filled with its own colour** (the closed-session notice's look) and nothing else: no edge, no neutral dark variant; the colour and the badge say what it is (red for what failed, orange for what needs a person, cyan for what waits in the background). It goes through `chatSurface`, so Flat draws it as a quiet fill.
- **A problem the person is told of in a session or in a new one is `ProblemNotice`** (orange for what is theirs to solve: a refusal of the host, a name that cannot be used, no provider ready, a host older than the app; red for what failed: a session that could not be read, a dictation, a folder), or `BannerView` for a refused send or a failed turn (it adds Try again and the line that says where to sign in); never a plain coloured line under the box. Every message of the conversation that is not a message is one `NoticeCard`. `splitNotice` breaks a sentence into title and detail. `--fixture` has the session "Notices" (`NoticesGalleryView`) with all of them at once, to look at a change to one beside the rest. What is left as a line on purpose: Settings' `ProblemLine`, the dictation widget's own notices, the sidebar's blocks (a narrow column) and the text inside a row of a list.
- **The actions of a `NoticeCard` are `NoticeActionStyle`, never the accent**: the accent the person chose does not read on the card's glass (violet on grey was 2.7:1). The main action is the card's own colour (lighter on dark, deeper on light) on a pill of that colour; the quiet one (Copy details, the cross that drops a queued message) is near-primary words with a pill under the pointer. The card hands its colour down in `noticeTint`. Its detail and hint are `primary` at 78 %, not `secondary`.
- **Links in a toolbar are `ToolbarPillButton`s on one glass capsule**; the item hides the toolbar's own glass (`sharedBackgroundVisibility(.hidden)`).

## Lines

Always `SettingsDivider`, never `Divider()`: the system's is a grey hairline that stands out on the dark themes. It is one whole point on purpose; **a half-point line over a translucent fill is drawn uneven on a Retina screen, so do not use `lineWidth: 0.5`.** Put the line in the row's `.overlay(alignment: .top)` and **put extra padding inside the row, never outside it**, or the line stops being halfway between two rows.

## Icons

The interface's own icons are named by what they mean (`AppIcon`, `CarrierCore/AppIcon.swift`: `.check`, `.close`, `.search`…).
They are drawn in the set the person chose in Appearance › Icon set (`IconSet`, `IconSets.swift`): Tabler (the default), Lucide or SF Symbols.
`iconAsset(_:in:)` says which SVG or symbol each icon is in each set.
They are drawn by `Glyph(.check, size: 14)` (`Carrier/Icons.swift`) and, with words, by `Label("Save", icon: .check)`.
Never write `Image(systemName:)` for a new icon of ours.
Add the case to `AppIcon`, its entry for all three sets (the `switch` does not build without them) and the SVGs (each set's `SOURCE.txt` says how).
`IconsTests` fails when a set lacks an icon or its file, and `build-app.sh` when the app lacks one.

Size is in points at the base text size.
`Glyph` scales it by the person's text size, so a `.font` after it does nothing.
The color is the one of its text (`foregroundStyle`).
A small white mark on a color (a state's check, a sidebar tile) is `bold: true`, three quarters thicker, or the weight would be too thin to read.
An icon that says something on its own (a tick that means "Pasted") takes `label:`, and one drawn in a circle or a capsule is wrapped in `.accessibilityElement(children: .ignore)` with its label; an icon beside words says nothing.

The weight is the person's too, Appearance › Icon weight (`IconWeight`, 1.5 by default, from 1 to 2.5).
For the two SVG sets the `stroke-width` is rewritten when the image is made, and the image is kept by set, icon and weight.
Every `Glyph` is drawn again when either changes; for SF Symbols the weight is the weight of the font (1.5 is the regular one).
A solid icon (`.warningFilled`, `.playFilled`) is a filled file where the set has one (Tabler), a filled outline where that stays readable (Lucide's play and stop) and an outline where it does not.

What the system draws stays in SF Symbols whatever the set is, so that it looks like the rest of the Mac.
That is the window's toolbar (‹ ›, ⋯ and the Back and Forward of Settings), the items of any menu (the status item's, a context menu, the composer's pop-ups), the menu bar's icon, the check and chevrons of a select and the disclosure of a list.
The item of a menu and the native button of the window's toolbar are `Label("Reveal", systemIcon: .folder)`.
The system draws their images, so they take the icon's SF Symbol, and a `Label(icon:)` there would lose its image.
The glass pills of the toolbar (`ToolbarPillButton`, `ToolbarGlassIconButton`) are ours and use `AppIcon`.
Provider marks (LobeHub) and file icons (Material Icon Theme) are their own sets.
The icons of an account (`AccountIcon.symbol`) are SF Symbols, since the host offers them by name.

The components that take an icon (`IconButton`, `EmptyStateView`, `NoticeCard`, `ToolbarPillButton`, `Badge`, `FilterChip`, `SegmentedChoice`, `StateGlyph`…) take an `AppIcon`.
What the model says of an icon (`EmptyState.icon`, `ToolKind.icon`, `FileCategory.symbol`, `stateSymbol`, `SendStep.icon`) is an `AppIcon` too, so the core stays free of the names of any set.
An effect an SF Symbol had is a modifier of `Glyph`: `.glyphSpinning(_:)`, `.glyphBouncing(_:)`, `.glyphPulsing(_:)` and `.glyphKick(_:)`.
None of them moves with Reduce Motion on, and `glyphPulsing` is only for what lasts a moment, since its animation does not stop while the window is hidden.
An icon inside a `Text` is `Image(inline:)`.
For an `NSImage` (a text attachment, a layer) use `IconImages.image(_:)` and `.tinted(_:)`; a layer reads `IconAppearance` in `updateNSView` so it is drawn again when the set changes.
A fourth set is a folder of SVGs with its licence, a column in `iconNames` and a case of `IconSet`.
Keep the sets few, since every new icon of the app has to be found in each.

## Buttons

Four kinds. Pick by what the button is, not by taste.

| Kind | Style | For | Where |
|---|---|---|---|
| Main | `PrimaryCapsuleButtonStyle` | The one action of a form or of a row: Save, Add, Update (Settings > About, the step of an update found); `.controlSize(.small)` inside compact popovers (`TabRenamePopover`). Accent fill, white label; dim when disabled. | `BehaviorTab.swift` |
| Secondary | `SecondaryCapsuleButtonStyle` | Cancel, Remove, Open Agents, Add account, Sign in. A grey capsule; `.controlSize(.small)` inside a row. | `BehaviorTab.swift` |
| Text | `HoverTextButtonStyle(tint: nil)` | Actions of a page header (Update, Open on GitHub) and the chevron. No pill until the pointer is over it. | `NoticeCard.swift` |
| Icon | `IconButton` (`HoverFillButtonStyle`) | A 24 pt glyph with a tooltip and an accessible name: close, fold. | `SidebarView.swift` |
| Toolbar pill | `ToolbarPillButton`, `AccentGlassPillButton`, `ToolbarGlassIconButton` or `ToolbarSearchField` on `.glassEffect(.regular, in: .capsule)`, its item with `sharedBackgroundVisibility(.hidden)` | An action or inline search pill in the window's title bar (Search, Filter, Check again, Stop, New session, New Terminal) or a compact glass pill strip (floating pane controls), plus the sidebar's Update (`UpdatePill`, for the states of a download). An item of the sidebar column's `.toolbar` goes after the window's buttons with `placement: .automatic`; `.navigation` puts it on the detail's side. | `ToolbarPillButton.swift`, `UpdatePill.swift` |

- **A button that does something has an icon** with its words: `Label("Save", icon: .check)`. Used: Save `.check`, Cancel `.close`, Remove `.trash`, Add `.plus`, Check again `.refresh`, Open on GitHub `.externalLink`, Reveal clone `.folder`, Reveal `.folder` and Open `.fileText` (a file), Detect `.refresh`, Use another… `.folderPlus`, Use the Homebrew one `.undo`. Outside a `Menu` give the label `.labelStyle(.titleAndIcon)` when it sits in a text or icon style.
- **A row that acts on a file or folder** (the Engine page's Files) has a Secondary button, Reveal or Open. While the path is missing the button is disabled and reads "Not created yet" with `.folderQuestion`. Its `.accessibilityLabel` is the verb and the row ("Reveal: Logs"), so VoiceOver can tell three such buttons apart.
- **A button that works for a while** (Detect) keeps its label and its size and is disabled while it runs, with a small `ProgressView` beside it that has an `.accessibilityLabel` ("Detecting"); when it ends, the result is announced to VoiceOver. Swapping the label for the spinner makes the row jump and leaves an unnamed button.
- **A button that asks again is `CheckButton`** (`CheckButton.swift`, its states in `CheckPhase`): Check again and Check now, in every place. At rest it has the refresh icon and its words; while it checks the arrows turn and it says "Checking…"; a check the person asked for ends in a green mark that draws itself and "Up to date" (a red cross and "Check failed" when it failed, pass `failed:`), for 3 seconds, and rests. A check the page ran by itself (when it opens) ends at rest, claiming nothing. The four faces share one cell, so the button keeps its size and nothing beside it moves; it is never `.disabled` (that dims it): a click while it runs or shows its result does nothing, and one after a failure tries again. The skin is the place's: `.toolbar` (the item adds the glass), `.capsule` (a row of a form, the default) or `.text` (a page's header). Give it `checking:` from the state that already says so; do not draw a spinner beside it.
- A form that is a card has its buttons in a row: Remove on the left, then a `Spacer`, then Cancel and Save, with 10 pt more above than the fields have between them. A form that is a screen of the Settings window (the account editor) has none: Save (or Add) is the toolbar's, Remove is the last row of the form and asks first (its ellipsis is that question, an alert), and Cancel is the window's back.
- Destructive is `role: .destructive`; a plain capsule does not turn red by itself. When a screen has one destructive action, say so with colour (`HoverTextButtonStyle(danger: true)` turns red under the pointer).
- Do not use the system's bordered, borderless or `.glass` buttons in Settings. (`EmptyStateView` uses `.glass` for its one button; leave it.)
- **Middle-click close on tabs or rows uses `.onMiddleClick(perform:)` (`MiddleClickModifier.swift`)** so middle-button events are handled within the view's visible bounds without interfering with SwiftUI left-clicks, hover tracking or context menus.

## Rows that open something

A row that opens an editor or a form shows **a chevron `.chevronRight` at its right and is clickable all over**:

- The chevron is a `Button` in `HoverTextButtonStyle(tint: nil)` with `.accessibilityLabel("Edit …")` and a `.help`; it is dimmed (`.disabled`) while that row is the one open.
- The row has `.contentShape(Rectangle()).onTapGesture { … }` (guard it so a second click on the open row does nothing). A button inside the row (Sign in, Reset, Use in an agent…) keeps its own click: a `Button` takes the click before the row's gesture.
- When the row opens a form below it, the chevron **sits in a fixed 26 × 26 slot and turns 90°** (`rotationEffect`); it must not move or resize. (`ReposTab.swift`, `roleRow`.)

## Fields and selects

- **A text field is `TextField(…).settingsField(width:)`** (`SettingsTabs.swift`): a quiet fill with rounded corners of 8, no line while idle, the theme's accent as a 1.5 pt ring while it has the focus, and a click anywhere in the box puts the cursor in it. `width: 240` for a short value, no width to fill the space given (a multi-line field too). Do not use `.textFieldStyle(.roundedBorder)` in a form. In a form that is a page of the window a field is `TextField("", text:, prompt: Text("…"))` with an `.accessibilityLabel`: a form takes the title of a field for its label (at the left of it, with its text at the trailing edge) and `settingsField` hides it, so a title left as the title would show no prompt and leave the field with no name for VoiceOver.
- **A slider of a row is `settingsSliderWidth`** (210 pt, the width of a field, so the tracks begin on the same line) **with `.labelsHidden()`**: in a form the track is otherwise drawn at about half of its frame, right-aligned in it.
- A search field is the same field with `icon: .search` (`settingsField(icon:)` draws the symbol inside the box) and a prompt that says what it searches ("Search repos").
- A field that saves as the person leaves it (Agents) passes its own focus: `settingsField(width:focused: $focused)`, so the ring and the save follow the same state.
- **Filters are `FilterChip`s** (`SettingsTabs.swift`): small capsules that are on (the theme's accent) or off (a quiet fill), in a row under the search. `SegmentedChoice` (`SettingsTabs.swift`) is a few exclusive choices in one grey capsule, the chosen one a lighter capsule and never the accent, every choice the same type and padding so nothing changes size (Usage's metric and range); the system's segmented `Picker` is not used for filters. Chips that exclude each other start with "All" and a second click on the one that is on goes back to it; an on/off filter ("Hide watched") is a chip of its own at the right of the row; a filter with many values (the owner) is a `SelectMenu`. The filtering is a pure function in `CarrierCore` with a test (`repoGroups`), not logic in the view.
- **The two sides of a branch are drawn the same everywhere** (`WorktreeStart` in `BranchSheet.swift`): Remote is a cloud, `teal`, and Local is a drive, `indigo`.
  The branch picker of a new worktree puts them as a `SegmentedChoice` (with the number of rows of each side in its title) under the search field, full width, one list under it at a time.
  The "from" chip of the sentence and the ref of the summary wear the colour of the side the worktree is cut from, so the ref says where it comes from before it is read.
  A row of the Local tab whose branch is not on `origin` has a `Badge` "not on origin" in `secondary`.
  A row of the Local tab whose branch differs from its copy on `origin` has a `Badge` "N behind origin" (arrow down) and "N not pushed" (arrow up) in orange, each only when it is not zero.
  The summary's warning about the choice (behind with Local, not pushed with Remote) is a `ProblemLine` under the "from" line, inside the same quiet box.
  The footer's "Could not reach origin" is an orange line under when the branches were last fetched, with no button and no error card: the fetch that runs on choosing a project asks nothing of the person.
  The picker of a folder session and of a repository to clone has no tabs, only the two sections it always had.
- **A choice among a few words is `SelectMenu`** (`SettingsTabs.swift`), the one select of the app: the system's own pop-up (a SwiftUI `Picker` in the menu style, `.labelsHidden()` and `.fixedSize()`), which in a form is drawn as the Mac draws it, the chosen word at the right of the row with the up and down chevrons in a small circle, and opens the system's menu with its own check. Outside a form (Usage's filters, a card page) the system would draw a boxed pop-up, so `SelectMenu` draws the same face by hand there (the word and `SelectChevron`, `SelectButtonStyle`) over the same system menu and check: a select looks alike wherever it is. It takes the room of its word: **give it no width**. The model picker's button (`ModelPickerButton`) is the same face (`SelectButtonStyle` and `SelectChevron`: no box, the words and the circle after them) over a popover, so every select looks alike. For a value (an enum, a stored string) use `ChoicePopUp(label:options:selection:)`, which wraps it: the choices are `(value, title)` pairs and the binding is the value itself. Do not use AppKit's `NSPopUpButton` or a hand-made menu button; the first draws badly in a form and the second has its own check and highlight. The first item is "Use default" (the empty value, nothing written) or "Same as everywhere (value)" when it inherits. A value already stored that is no longer on the list stays on it, so opening the editor never changes it.
- A text of several lines (an instruction, a prompt) takes the width of the card: `SettingsStackedRow` puts the title and the detail on top and the control under them, and the box is a `TextEditor` in `settingsField()`. Turn the system's writing tools off on it (`.writingToolsBehavior(.disabled)`), or its "Write with Siri" button sits on the box.
- A box of several lines in a row (`TextEditor`, "Launch arguments"): `scrollContentBackground(.hidden)`, 4 pt padding, the same fill, and **the size goes last, around the padding**, so the row grows with it.
- Turn off the system's writing tools on a form of paths and arguments: `.writingToolsBehavior(.disabled)`.
- **A form's controls are one width**, whatever they are (a field, a box, a grid of choices; a select is the exception, it takes its word's): they end on the same line down the card, so the form reads as a column. The account editor's is `AccountEditor.controlWidth`, which is `settingsSelectWidth`; its icon and color choices are not in the form but behind a Change… button that opens them in a popover, in eight 30 pt tiles per row (`AccountEditor.gridWidth`). Do not give each field the width of its value.

## Lists and menus

- **A file of a message is looked at in `AttachmentPreview`** (a sheet of the window's size, `windowSheetSize`): its name and "n of m" and a Secondary `Show in Finder` (`folder`, small) and the `IconButton` close on top, Quick Look under, a glass circle with a chevron at each side (and ← →) only where there is a file further. A chip opens it with `AttachmentChip(open:)`, and only for a file that goes and is not a folder (`canPreview`); the others reveal in Finder.
- **The card that opens on a row (a session's `SessionPeekView`, an epic's `EpicCardView`) draws its facts with `CardFactsGrid`**, by the fact's `kind` (`CardFact`): words wrap, but a folder or a branch is one monospaced line cut in the middle with the whole of it in its tooltip (a long path never breaks over four lines), and an agent is its account's mark and short name. The state under the title wears the row's own colour (orange for what needs the person, green for Done), and says Done, as the row does, for a turn that ended unread.
- A row of a form that opens a screen (a provider, an account, a screen of Dictation, with what it holds at the right) is a `NavigationRow`: the whole row is a button with a chevron at its end, and the state it says goes before the chevron; an account's row (`AccountRow`) puts its usage at the right and, when that does not fit, under its text. A list of things to choose from (the repos) is a card with rows of 8 pt side and 6 pt top padding, a rounded 9 fill for the chosen one (`secondary` at 18 %), and a dot or a mark at the right for its state. A last row of the same shape, with a dashed tile and a plus, adds one (`AddRepoRow`).
- A tile for a thing is its mark in a rounded square: the project's `ProjectIcon` (32 pt, radius 9, its chosen colour and `AppIcon` mark when set, or its initials on a colour made from the name) for a repo or project, `ProviderMark(name:)` for a provider (its bundled icon in the text colour; `accountIcons` in `RepoRoleSave.swift` gives each account its provider's icon).
- **On the Agents page a role is its identity's picture, `RoleAvatar`** (`RoleAvatar.swift`): the bot's own logo (a rounded square of radius 28 % of its side, 38 pt in the rail, 64 pt on a role's screen) or its initials on a color made from its name, with the mark of the account the role runs on in the corner (`AccountMark` in a circle of the window's color and a 1 pt edge, as `AgentAvatar` has it); a person is a person symbol and an identity that is not there a dashed square with a question mark.
  The picture is only help, so a picture that cannot be fetched is never an error: the initials stay.
- **The roles of an epic are `EpicRail`** (`AgentsParts.swift`): one row of the form, the roles as buttons (a 5 % fill under the pointer) and between them a 2 pt line through the middle of the avatars' column with what passes on written beside it (dashed while the Lead reviewer is off).
  It is one row on purpose: separate rows would break the line at every edge.
  A value that is shown and cannot be changed yet (the Skills of a role) is a quiet box in the monospaced face with a `StatusChip` "Default" before it, never a disabled field.
- **An agent role in a list that is not the Agents page (the repos') is drawn with `RoleTile`** (the provider's mark in a 34 pt tile, a power symbol when the role is off) and its settings with `roleSummary` (`Identity gh · Account pro · Model sonnet · Effort high`, the label quiet and the value in the text colour). In a list that is narrow, the model and the effort go on the first line in the text colour and the account and the identity under it. The mark follows the account's harness (`accountIcons`).
- **The model of a role (or of a failover step) is chosen with `ModelPickerButton`** (`ModelPicker.swift`), never typed: a pill with the provider's mark, the model and the reasoning that opens the chat's panel (the providers that can work as tabs, a search, the models, the `ScaleRow` slider for reasoning). Its choices are `ModelPick` values, and the logic of what it lists (`pickerAccounts`, `modelOptions`, `effortSteps`) is in `CarrierCore/ModelPicker.swift` with tests. A role runs on its own, so the panel shows its access as full, not as a choice. The Repos page uses the same picker for a repo's own roles, with `inherited:` (the first row of the list, and of the slider, is "Same as everywhere", and the pill says what that is) and `fill: true` (the pill takes the width of the form). Settings > Sessions uses it for what a new session starts with, over the chat host's agents and with `showsAccess: false`, since the person chooses the access in the message box.
- **A list that can hold thousands of rows (the dictations of History) draws a page and ends with a Secondary `Show N more`** (small, centred, in the group of the count line), not a `LazyVStack`.
  The page sits in a form inside a `ScrollView`, and the cap is what keeps its cost bounded and testable.
  The cap and what is left are a pure function in `CarrierCore` (`dictationHistory`).
  A new search or filter goes back to the first page; a new or a deleted entry leaves the list where it was.
  Rows that the engine already caps (the files of a section at 500, a diff at 1000 rows) may be a `LazyVStack` instead, since their cost is bounded by that cap.
- **A menu's items have an icon, and a `Label` in a `Menu` or a `contextMenu` needs `.labelStyle(.titleAndIcon)` to show it**; this SwiftUI draws a menu's labels title only otherwise.
- Small facts of a status card (`fact` in `ReposTab.swift`): a label of 84 pt in `secondary` and the value; **every row is at least 40 pt**, taller than any chip, so a row with a badge and one without are the same height.
- A state is shown by a green, orange or grey dot, or by `StatusMark` (`SettingsTabs.swift`, a 16 pt round mark: `.check` green, `.exclamation` yellow, `.close` orange), at the right of a row that has no button or before one. While something runs, **each row turns its own `ProgressView` and says "Checking…"**; the page does not say it once in a corner.

## A value that is not valid

Orange, not red, and nothing moves. This is the default of every row and field: pass the message once, `SettingsTabRow(…, problem: "what is wrong")`, and the row puts it in the place of its detail line, in orange with a warning mark (the title keeps its colour), while every `settingsField` and `NumberField` inside it draws an orange ring and a warning mark in the box, the same size as without them (the row tells them through `\.settingsInvalid`). A new field needs nothing for it; do not pass a flag to the field, and do not colour a whole row red. A message that has no row of its own (a refused save, a page that could not load) is a `ProblemLine`, never a bare orange `Label` or `Text`: only `ProblemLine` is read aloud. Under a field of a sheet that is not a `SettingsTabRow` (Usage's price sheet) it is `ProblemLine(text:font: .caption)`. A page that failed to load shows the problem alone, not its empty state too: "No accounts to show" under an error reads as if there were none. A refused save that belongs to one row (the Engine page's GitHub identity) is that row's `problem`, next to the control that was changed, and the code that saved posts an `AccessibilityNotification.Announcement` with it, since a row's problem is not read aloud by itself.

## What the engine answers to a save

A page that writes `engine.json` or `providers.json` does not wait for Carrier: it writes, asks the engine in the background (`ReloadStatus.ask`, in `CarrierCore/EngineReload.swift`) and shows the answer when it comes; an answer older than the last save is dropped. A refusal or a missing answer is a problem and is orange: `ProblemLine` (`SettingsTabs.swift`) is the line with the warning mark that VoiceOver reads when it appears, and `ReloadNote` is the page's line for the last answer, with "Ask Carrier again" to ask without saving (the Behavior header offers it too; the doctor's "Check again" is another button). A running Carrier that is too old to reload is not told at all: it reads the file when it starts, and the next one applies it live. A page that is a header note (`SettingsHeaderNoteKey`) wraps it under the title when it does not fit beside it (`ViewThatFits`). The last answer lives in `ReloadStatus.shared`, not in the page's `@State`, so it is still there when the person comes back to the page, and it goes when Carrier starts or stops.

## Meters and charts

- **A quota is a `QuotaBar`** (`UsageView.swift`), with `QuotaPercent` (its number, bold, orange from 90 %) and `QuotaMeter` (name, percent and bar, for a row's header): an 8 pt capsule track, `primary` at 12 % with a 1 pt edge; the use that stays is solid, the use the next reset gives back is `Hatch`ed after it (diagonal 1.5 pt lines every 4 pt over the tint at 30 %). The tint is the theme's accent, orange from 90 %. Its numbers (the shares, the percent, the reset) come from `MeterShape` in `CarrierCore`, and the bar is hidden from VoiceOver: the percent beside it is the text.
- A chart (Swift Charts) sits in a `SettingsTabCard` under a `.sectionLabel()` title, one colour a provider, the legend at the bottom. Hovering a day shows **the chart tooltip** (`Tooltip` in `UsageConsumptionView.swift`): 170 pt wide, 8 pt padding, `.regularMaterial` rounded 8 with a 1 pt `primary` at 12 % border, a line per provider with its colour dot, and a `SettingsDivider` before the total; a click keeps it, a second click lets go. The words of the tooltip are a pure function (`usageTooltip`). Every mark has its own `accessibilityLabel` (day and provider) and `accessibilityValue`, so the numbers never depend on the pointer.
- Keep a chart's expressions small and typed (a mark in its own `@ChartContentBuilder` function, `PlottableValue` written out): CI's compiler times out on a big one.
- Usage's provider rows only open and close their drawer (the whole row is the button, its chevron a round 24 pt slot); the filter by provider is a `ChoicePopUp` in the filters row, with the search at its right. A table's total is a `UsageFooter`: a band of its own (`primary` at 7 %) that reaches 8 pt past the rows' text, so it reads as a sum.

## Text

- Titles `fontWeight(.medium)`, details `.scaled(11)` in `secondary`, a path or a command `.scaled(11, design: .monospaced)`. Use `Font.scaled` (`ScaledFont.swift`), not a fixed size, so the person's text size applies. The system's styles (`.caption`, `.callout`, `.body`, `.title3`) do not follow it: use `.scaled(11)` for a detail, `.scaled(12)`, `.scaled(13)` and `.scaled(15)` for the others (`.scaled(10)` is for an uppercase label or a pill).
- Do not put copy-on-hover (`copyOnHover`) on text that says nothing to copy ("Not checked yet", "Checking…"); keep it on a path, a reason and a fix.
- Texts are English, short, and say what the control does, not how it works.

## The dictation widget

The widget of the global dictation (`DictationWidget.swift`) is a floating panel, not a view of the window; [dictation](macos/dictation.md#the-widget-style-and-position) says what it shows.

- **The panel takes the pointer so it can be dragged**: a drag that begins on the box moves it (`WidgetPanel.sendEvent`, from 3 points on so a click does not nudge it), except in the state that holds a copied text, where the text is the person's to select and only the box's margins drag it (the system's `isMovableByWindowBackground`). Where it is let go is kept as a `DictationWidgetSpot` (the centre across the display, the nearer edge and the gap from it, so a box that grows opens away from its edge).
- **A box has one height per style** (2, 3 and 4 lines at 340, 420 and 540 pt, text at 12, 14 and 17 pt through `Font.scaled`), so it never jumps while the text grows: the text scrolls inside it. The Pill is a 76 by 38 capsule with an icon and no text.
- **It wears `WidgetSurface`** (`.chatSurface` tinted by the theme, never its own fill) and is drawn once by `WidgetBox` and `PillIcon`, which the Preview in Settings and the theme picker's swatches use too. The themes are `DictationWidgetTheme`: Default is the accent at 12 % in light and the accent mixed 60 % into black at 55 % in dark, so the text reads over a white window; Black, Dark glass and Theme glow force their text's dark appearance (`DictationWidgetTheme.appearance`: the panel's hosting view takes it, the Preview and the swatches set the colour scheme), so the text reads over their own colour whatever the app's is; Clear glass is the system's glass with no tint at all and its text follows the system's appearance. Glow is the listening line's own colours (`DictationIndicator.accentColors()`: the accent and two neighbouring hues) as a gradient from the left edge to the right one (never from the centre: a wide box would show a wedge), at 60 % over dark glass, with a 1 pt light edge and an accent shadow that fits in the panel's `glow` margin. These are first numbers, to be checked by hand over a white and a dark window in light and dark appearance and then written here as the ones that hold.
- **The listening line is `DictationIndicator`, reused with the look's `radius`**, only while it listens; the panel is `DictationWidget.glow` points larger than the box on every side so the line is not cut. A box fades its first line once the text is longer than its lines (`dictationTextFit`).
- **What it draws is `dictationWidgetLook`**, never a check on the state in the view. A state that needs text or a button opens the Pill as the Small box.
- **A reason sits over the text, not inside what scrolls** (`WidgetBox(notices:)`): a text that was only copied has three more lines than its style for it, and its scroll bar shows.
- **Its buttons are `SecondaryCapsuleButtonStyle` with a `Label`** and keep only their symbols (`ViewThatFits`) when the box is too narrow for the words.
- **A failure has no clock and no finish key**, only "Esc to dismiss".
- **The panel is key only while it holds a copied text and its buttons** (`WidgetPanel.keyable`); in every other state it never takes the keyboard from the app in front.
- **The Preview shrinks to the width it is given** (`scaleEffect`), so Large never overflows a card.

## Mistakes seen

- A `Spacer` inside a view that sits in `safeAreaBar` (the page header) takes all the height the bar offers: the header filled the window. Size such a view by what it holds.
- `frame` before `padding` and `background` lets a `TextEditor` spill over the row above it. Size last.
- A page-wide `.buttonStyle(…)` reaches inside menus and forms; a control that must differ sets its own style.
- A `contentShape` row with a gesture and a button inside is fine; two gestures on the same view are not.
- A row that opens on `.onTapGesture` alone is invisible to the keyboard and to Full Keyboard Access: make it a `Button` (`.buttonStyle(.plain)`).
- The window's size does not matter to a build that only compiles. **Open the app and look** at the state with a long value, a missing value, an error and the empty state.
- A bare `TimelineView(.animation)` or `.periodic` keeps drawing with the window minimized. In the window use `MovingTimeline` for a motion (30 frames a second at most) and `TickingTimeline` for a clock: both stop while nobody can see the window (`Viewing`). The Settings window, the dictation widget and the previews outside the window have no `Viewing` and keep a plain timeline.
