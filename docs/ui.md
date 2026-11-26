# The look of Carrier

How the pieces of Carrier are drawn, so that a new screen or a change reuses what is there and looks like the rest, on the Mac now and in any front-end after it.
It was written down while polishing Settings (Providers and Repos first); the pieces live in `macos/Sources/CarrierUI/`.
**Before adding a button, a field, a select, a row or a line, look at the catalog below, then at the file it names, and reuse it.
Do not draw a new one, and do not use the system's plain control where a piece exists.**
When a piece is missing, add it next to the others, with its catalog entry and its place in the gallery, in the same change.

**What belongs here**: how to use the pieces and the rules that keep the app looking like one product (sizes, colours, which piece for which job, what not to do, mistakes already made).
What does not: what a screen shows and why (that is [`docs/macos/`](macos/app-shell.md)), where the code lives and what is tested (that is [`macos/AGENTS.md`](../macos/AGENTS.md)), and what changed (that is the CHANGELOG and the PR).
When a rule needs a reason to not be broken again, give it one sentence under it.

Nothing here is checked by a test: a piece is looked at, in the gallery below and in the screens that use it, not only compiled.
What a script does check is that every piece has its entry in the gallery (`macos/scripts/check-structure.sh`).

## The rules of the look

They hold for every front-end; the sections after the catalog say how the Mac applies them.

- **The theme gives the colours.** The twelve themes, the accents and the semantic colours come from `design/tokens.json`; a piece takes them from its environment and never writes a colour of its own.
  A second front-end that wrote its own would drift from the first in a week.
- **The words are copy keys.** Every text a person reads is a key of `design/copy/` with an English and a Spanish value, read through `Copy`; a piece shows the text it is given.
- **A state is never the colour alone.** A word, an icon or a shape says it too (a `StatusChip` has its word; with "Tell states apart by shape" on, the state pieces draw their symbol).
- **The text follows the person's size.** Sizes are a base scaled by the text size, never a fixed size; the system's own styles do not follow it.
- **Light and dark are both looked at.** Every piece is seen in both before a change is done; the gallery has a switch for it.
- **One main action.** A form or a row has one accent button (Save, Add); every other button is quiet.
- **A line is one whole point, and its padding is inside the row.** A half-point line over a translucent fill is drawn uneven on a Retina screen.
- **Spacing is 14 between blocks and 4 inside a block**, 12 between a tile and its text; a row is one line, and what does not fit goes to the group's footer.
- **A radius, a padding or a `spacing:` is a step of the scales in `design/tokens.json`** (`Tokens.Radius`, `Tokens.Space`), never a number; a frame size and an opacity stay literals.
  A value that has a step is that step (3 is `s3`, 5 is `s5`, 18 is `s18`, 22 is `s22`); a value between two steps takes the nearest, by at most one point (7 is `s8`, 9 is `s10`, 11 is `s12`, 13 is `s14`, 25 is `s24`).
  The one exception is 26, which is `s24` too and moves two points: it had no step of its own, and the spacing scale stays one set of steps rather than gaining an `s26` for the two places that drew it (the gap between the sections of the Epics panel and the trailing padding of the background-work card's rows).
  A value no step is near is a step of its own with a name for what it is (`bubbleMargin`, `timelineTop`, `Radius.hair`, `Radius.roomy`, `Radius.sheet`).
- **Under the pointer a piece answers**: a faint fill in 0.12 s, a stronger one while pressed, dimmed and no fill when disabled.
- **Motion stops when nobody looks**: a motion runs only while the window can be seen and Reduce Motion is off.

## The words

How a screen reads a text, so every area does it the same way.

- A key is named `<area><What>` in camel case (`lifecycleStepQueued`, `healthDoctorNoChecks`, `awakeStatusOff`), one flat entry in `design/copy/en.json` and in `es.json`; `pnpm design` writes `Copy.<key>(...)` and the catalog, `pnpm design:check` fails when they are out of step.
- A view passes the call to what it draws: `Text(Copy.lifecycleRunning())`, `OverviewTitle(title: Copy.lifecycleRunning(), detail: Copy.lifecycleSlotsInUse(busy: 2, total: 4))`.
  A text that needs a person's data takes it as labelled arguments (`{busy, number}`, `{branch}`); a sentence is never joined from pieces with `+`.
- A count that changes the words is a `plural` with `one` and `other` (`{hours, plural, one {# hour} other {# hours}}`), and a `=0` case when zero has words of its own; Spanish declares the same cases.
  A choice among kinds is a `select`; a number that only shows is `{n, number}`, which groups for the locale.
- A select holds every argument its branches use inside the branches (`{state, select, open {Pull request {number}, open} merged {Pull request {number}, merged}}`); an argument written outside the select is lost by the generator.
- An ordinal is a `select` on its kind, which the code works out (`queuePlaceLine`: 1st, 2nd, 3rd, 4th, 11th); a language whose ordinals do not change declares every branch alike.
- A model never lets a front-end choose by the words of a label: what a view tells apart (the icon of a Details row) is an identifier the model carries (`DetailsRow.field`).
- A list of whole phrases, each its own key, may be joined with `, `, `. ` or ` · ` (a VoiceOver label of several facts, a line of counts); a sentence is never built by joining its words.
- A pure function of `CarrierCore` that builds a sentence takes `bundle: Bundle? = nil, locale: Locale = .current` last and hands both to `Copy`; a function a view reads as a property becomes a method for it.
- A test asserts English with `english` and Spanish with `spanish` (`Tests/CarrierCoreTests/Copy/Languages.swift`: `Copy.bundle("en")` and `en_US`, `Copy.bundle("es")` and `es_AR`), passing `bundle: spanish.bundle, locale: spanish.locale`; every plural a function uses has its Spanish case asserted.
- A text Node sends (a doctor check's detail and fix, a preparation step's detail) is shown through its text code and is not a key of the area.
- A value never keeps a sentence it built in English: it keeps the data, and a method that takes `bundle:` and `locale:` says the words (`ToolCall.result`, `Subagent.words`), or the function that builds the value takes them (`chatFeed`).
- What a provider or the host says in its own words (a model's label, a call's summary, a tool's output) is shown as it came, in its language.

## The scales

A radius, a padding, a `spacing:` and a colour that is not a theme's are tokens of `design/tokens.json` (`Tokens.Radius`, `Tokens.Space`, and the semantic groups), never a number or a `Color(red:)` in a view; frame sizes and opacities of one view stay literals.
The scales were taken from the literals the views had, so a token is exact or one point from what a view drew; a token is added only when a literal's nearest token would show the difference, with its reason here.
A space token is named by its value (`s8` is 8) so that two areas that add the same step add the same name.

**Radius**

- `hair` (2): the squares of a file's diff and the stopped mark of a subagent, whose corner was 1.5 or 2; `tiny` would change a mark of eight points by a visible amount.
- `tiny` (3): the bars of a skeleton and the small blocks of a preview; the 4 that was there is this one, and the 2 is `hair`.
- `small` (6): chips and the smallest controls.
- `control` (8): buttons, fields, tiles in a grid and the rows that answer the pointer; the most used radius, and the 7 that was there is this one.
- `tile` (10): the square marks of a provider and an agent, a hovered Agents row and a box on the General page; the 9 that was there is this one.
- `card` (12): a card and the group of a sheet.
- `roomy` (14): the corner of the conversation's surface, which has no step next to it to share.
- `panel` (16): the cards of the starting and running windows, and the icon tiles of the stopped window and the Engine page.
- `sheet` (18): the approval card of the conversation, drawn at that corner.

**Space** (padding and `spacing:`)

- `none` (0): a stack whose children touch.
- `s1` (1) and `s2` (2): the gap between a title and its caption, and the nudge that lines a glyph up with its text.
- `s3` (3), `s4` (4) and `s5` (5): inside a chip and between the lines of a block.
- `s6` (6): between an icon and its words, and the vertical padding of a chip.
- `s8` (8): the standard gap between two controls; the 7 and the 9 that were there are this one.
- `s10` (10): between the lines of a row, and a row's own padding; the 9 that was there is this one.
- `s12` (12): inside a card, and between a tile and its text; the 11 that was there is this one.
- `s14` (14) and `s16` (16): between blocks and a page's side margin; the 13 that was there is `s14`.
- `s18` (18), `s20` (20), `s22` (22) and `s24` (24): between the groups of a page and the sections of a sheet; the 25 and the 26 that were there are `s24`.
- `s28` (28) and `s30` (30): the margin of the stopped window and the gap between the sections of the Pieces gallery.
- `s32` (32) and `s34` (34): the side margin of the Usage page and the 33 that indented a notice's lower line (`s32`); the indent of a provider's accounts under its row.
- `s40` (40): the side margin of the gallery pages.
- `s54` (54): the indent of the context button's text when it shows a share, so it starts under the figure.
- `s74` (74) and `s110` (110): the indent of an open history row's detail, and of a field's error under a label 110 wide; each lines up with a column beside it.
- `s90` (90): the inset that makes the second skeleton bar of the cleanup shorter than the first.
- `bubbleMargin` (120): the empty margin at the leading side of a person's message bubble and of a subagent's answer, so they do not run the width of the conversation.
- `timelineTop` (160): the room above the first message of the conversation, under the header that floats over it.

**Semantic colours**

- `tile.terminal` (`#404040`): the dark grey tile of the Terminal page in Settings' sidebar, the same in light and dark.
- `projectColor.*` (red, orange, yellow, green, teal, blue, purple, pink): the eight muted hues of a project's tile, the same in light and dark; `ThemeTests` pins each to the hue it was drawn from.
  White initials stay readable over every one of them.
- `status.*`, `toolCall.*` and `attention.approval`: the kinds of tool call, the slow call, the working, background and done marks and the approval, as light and dark pairs where they differ; the Sessions and Chat views read them, never a `Color(red:)`.
- `pullRequest.merged` (`#b86bf2`): the purple of a merged pull request's chip and dot.
- `attachment.*` (image, pdf, folder, log, data, archive, other): the tint of an attachment's chip by kind, the same in light and dark.
- `console.*` (text, added, removed, background): the dark terminal of a conversation's console and the added and removed lines on it, the same in light and dark.
- `harness.claude` and `harness.other`: the grey of a harness's name in a session row (Claude or another).
- `status.thought` (`#c9a1ff`): the violet of the agent's thinking and of the ring of a working session, the same in light and dark (`toolCall.thought` is the deeper one of the transcript's chips).
- `resultMark.*` (green, red): the disc of the check button's result, deeper than the system's colours so its white mark is not lost at 14 pt.
- `syntax.*` (keyword, string, number, comment, function, type): the colours of a code block's words, as light and dark pairs.
- `provider.*` (claude, codex, antigravity): the colour of each provider's bars in the Usage chart.
- `projectIcon.p01` to `p24`: the 24 muted colours a project's icon takes, 12 hues each in a fuller and a greyer tone, kept to the hue and brightness the white initials need for 4.5:1.
- `milestone.plain` (`#6e6e6e`): the grey of the transcript's marker for the plain steps (read, search, shell, other, mcp).

## The nine rules of a piece

A piece is a reusable building block of the look, named here and drawn once.
[ADR 0052](adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md) has the reasons; each rule has one example.

1. **It is presentational: it takes values and actions, and never reads a store, a singleton, a file or a socket.**
   `AccountMark(symbol:initials:tool:tint:size:)` draws what it is given; the area that shows an account asks the account's identity and passes it.
2. **It keeps only passing visual state (hover, pressed, focus, an animation).**
   `SegmentedChoice` keeps which segment the pointer is over; the choice itself is a `Binding` the area owns.
3. **Its look comes only from design tokens, through the environment.**
   `PrimaryCapsuleButtonStyle` reads the accent from `pieceTheme` and the text size from `textScale`, never from `AppTheme.shared` or `TextSize.shared`.
   Every view does the same: the size comes from `.scaledFont(...)` and the accent from `.tint` (or `pieceTheme.accent` where a `Color` is needed); `Font.scaled` and `Color.themeAccent` no longer exist.
4. **Its API is small: an enum for its variants, a slot for content, a style or modifier over the system's control where one fits.**
   `CheckButton(skin:phase:)` takes a `Skin` and a `Phase`, not a handful of booleans; `NoticeCard` takes its `actions` as a slot.
5. **Its states are listed in its catalog entry and drawn in the gallery.**
   The entry of `BannerView` lists error, warning and record; the gallery draws those three.
6. **Its accessibility is part of it: a label, the text size, contrast and keyboard focus.**
   `IconButton` always has a name, which is also its tooltip, and `CardChevron` is hidden from VoiceOver because its row says it.
7. **What it shows that is more than layout comes from a pure function in `CarrierCore`, and that function is tested.**
   `sliceCard(lane:)` makes the words and marks of a slice's card and `SliceCardTests` checks them; the view draws the result.
8. **It has one file, one catalog entry and the name it will have in every front-end.**
   `NoticeCard(symbol:tint:title:detail:actions:)` in Swift is `<NoticeCard symbol tint title detail actions />` on the web.
9. **It moves to `UI/` when a second area needs it; a piece used by one area stays in that area.**
   `FilterChip` stays in `Features/Projects/` because only the Projects page draws it; `SelectMenu` is in `UI/Selects/` because most areas use it.

## The gallery

Open Carrier Dev (`./build-app.sh` with no version, [CONTRIBUTING](../CONTRIBUTING.md#developing-against-a-throwaway-folder)) under `--fixture`, and the sidebar lists a session called Pieces.
It draws every piece of the catalog in each state its entry lists, under the name of the piece, by kind, with made-up data and a Light and Dark switch.
The switch passes that scheme's surfaces to the pieces, and keeps its state in the page, never in the preferences.
Hover and pressed are the live pieces' own: point at one and press it.
The language is the app's, and the page's own words are copy keys: to see it in Spanish, open Carrier Dev again with `-AppleLanguages (es)`.
It is for looking at, not a test, and it never shows outside `--fixture`.
The page is `Carrier/Features/Settings/PiecesGalleryView.swift` and one file per kind beside it; its data is `CarrierCore/Fixtures/PiecesGalleryData.swift`.
A new piece gets a `GalleryEntry("<Name>")` in the file of its kind, or `check-structure.sh` fails and names the piece's file.

## The catalog

One entry per piece: every type declared at the top level of a file under `CarrierUI/`, outside `Tokens/` and `Modifiers/`, and the pieces that are modifiers (`SettingsField`, `HoverCard`, `WorkCard`) or families of one file.
`Kind` is the folder, `File` is where it lives, `Web` is its name in a web front-end, `Takes` is its API, `States` are the ones the gallery draws (hover and pressed are the live piece's, where a piece has them).
Detail on how a screen uses a piece is in the sections after the catalog.

### IconButton
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/IconButton.swift` · Web: `<IconButton>`
Takes: `icon`, `name` (the accessible name and the tooltip), `enabled`, `why` (the tooltip while disabled), `shortcut`, `pressed`, `action`.
States: normal; open (`pressed`, while what it opened is open); disabled; hover and pressed (live).
Use for: a 24 pt glyph that acts: close, fold, a toolbar of a row. Not for: a button with words (that is a capsule or a `HoverTextButtonStyle`).

### HoverFillButtonStyle
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/HoverFillButtonStyle.swift` · Web: `<Button variant="fill">`
Takes: `open` (the middle fill while what it opened is open), `radius`.
States: normal; open; disabled; hover and pressed (live).
Use for: the face of a sidebar or icon button: no fill at rest, a faint one on hover, a stronger one while pressed. Not for: a button that is its words (that is `HoverTextButtonStyle`).

### HoverTextButtonStyle
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/HoverTextButtonStyle.swift` · Web: `<Button variant="text">`
Takes: `tint` (nil is quiet grey), `danger` (turns red under the pointer).
States: normal; tinted; danger; disabled; hover and pressed (live).
Use for: an action of a page header or beside a message: only its text until the pointer is over it. Not for: the main action of a form (that is `PrimaryCapsuleButtonStyle`).

### PrimaryCapsuleButtonStyle
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/PrimaryCapsuleButtonStyle.swift` · Web: `<Button variant="primary">`
Takes: `large` (the one button a screen is about); smaller under `.controlSize(.small)`.
States: normal; small; large; disabled (grey); pressed (live).
Use for: the one main action of a form, a footer or a row: Save, Add, Update. Not for: a second button of the same form (that is `SecondaryCapsuleButtonStyle`).

### SecondaryCapsuleButtonStyle
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/SecondaryCapsuleButtonStyle.swift` · Web: `<Button variant="secondary">`
Takes: Nothing; smaller under `.controlSize(.small)`.
States: normal; small; disabled; hover and pressed (live).
Use for: every other button of a form: Cancel, Remove, Sign in. Not for: the main action (that is the accent capsule).

### NoticeActionStyle
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/NoticeActionStyle.swift` · Web: `<NoticeCard.Action>`
Takes: `quiet` (the secondary action); the colour comes from the `NoticeCard` it is in (`noticeTint`).
States: normal; quiet; disabled; hover and pressed (live).
Use for: an action inside a `NoticeCard`, in the card's own colour. Not for: a button outside a notice.

### CheckButton
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/CheckButton.swift` · Web: `<CheckButton>`
Takes: `skin` (toolbar, capsule or text), `title` (nil says the piece's own "Check again"; a screen passes its own), `phase` (idle, checking, done, failed), `action`. The words of the three other faces are copy keys of the piece (`pieceChecking`, `pieceUpToDate`, `pieceCheckFailed`).
States: idle; checking (the arrows turn); done; failed; the text skin.
Use for: the button that asks again, wherever the app has one (Check again, Check now). Not for: a button that does anything else.

### ToolbarPillButton
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/ToolbarPillButton.swift` · Web: `<ToolbarPillButton>`
Takes: `title`, `icon` or `mark`, `badge` (a count), `spinning`, `iconTint`, `action`; its height is `ToolbarPillButton.height` (28).
States: normal; with a count; working (the icon turns); disabled; hover (live).
Use for: a word with its icon on a glass pill of the toolbar: Search, Filter, Stop. Not for: an action inside a page (that is a capsule).

### AccentGlassPillButton
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/ToolbarPillButton.swift` · Web: `<AccentGlassPillButton>`
Takes: `title`, `icon`, `action`.
States: normal; with an icon; disabled (dimmed, the glass stops answering the pointer).
Use for: the main action of a header or of an empty state, on accent glass: New session, Add. Not for: a form's Save (that is `PrimaryCapsuleButtonStyle`).

### ToolbarGlassIconButton
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/ToolbarPillButton.swift` · Web: `<ToolbarGlassIconButton>`
Takes: `icon`, `active` (what it opened is open), `name`, `action`.
States: normal; selected (`active`); disabled; hover (live).
Use for: an icon-only button of a glass strip of the toolbar. Not for: a button with words (that is `ToolbarPillButton`).

### ToolbarSearchField
Kind: Buttons · File: `macos/Sources/CarrierUI/Buttons/ToolbarPillButton.swift` · Web: `<ToolbarSearchField>`
Takes: `query` (nil while closed), `placeholder`, `focused`, `onDismiss`.
States: closed (the Search pill); open (the field and its close button).
Use for: the search of a toolbar, which opens inline into a 220 pt pill. Not for: a field of a form (that is `SettingsField`).

### NoticeCard
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/NoticeCard.swift` · Web: `<NoticeCard>`
Takes: `symbol`, `tint`, `title`, `detail`, `hint`, `tag`, `detailLines`, `account`, `onTap`, `actions` and `below` (slots).
States: each tint (info, warning, error); with and without detail; with actions; a disabled action.
Use for: a notice about the whole page or conversation, over the message box. Not for: a problem of one field (that is `ProblemLine`).

### OverviewCard
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/OverviewCard.swift` · Web: `<OverviewCard>`
Takes: `fullWidthDividers`, its rows as content.
States: normal; with dividers across the whole width.
Use for: the card of a Carrier home section: rows divided by hairlines. Not for: Settings groups (that is `SettingsGroup`).

### OverviewLinkRow
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/OverviewLinkRow.swift` · Web: `<OverviewLinkRow>`
Takes: `action` (nil makes it a plain row), its content.
States: with an action (a chevron); plain.
Use for: a row of an `OverviewCard` that goes somewhere. Not for: a row of Settings (that is `NavigationRow`).

### OverviewTitle
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/OverviewTitle.swift` · Web: `<OverviewTitle>`
Takes: `title`, `detail`.
States: normal; with detail.
Use for: the title of a Carrier home section, above its card. Not for: a group of Settings (that is `SettingsGroup`).

### SettingsGroup
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/SettingsGroup.swift` · Web: `<SettingsGroup>`
Takes: `id`, `title`, `footer`, `accessory` (a control at the right of the title), its rows as content.
States: normal; with a footer; with an accessory.
Use for: a group of rows of a Settings page: a small uppercase title over a card, or a section of a form. Not for: a list of things that open a screen of their own (that is a card of `NavigationRow`).

### SettingsTabCard
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/SettingsTabCard.swift` · Web: `<SettingsTabCard>`
Takes: Its rows as content.
States: normal (drawn inside `SettingsGroup`, and alone under Rows).
Use for: the card every group of rows sits on, rounded 14. Not for: a card in the feed (that is `WorkCard`).

### CardFactsGrid
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/CardFactsGrid.swift` · Web: `<CardFactsGrid>`
Takes: `facts` (label, value, kind: text, path, branch or account, and a detail line), `extra` (more rows, a slot).
States: each kind of fact; with extra rows.
Use for: the facts of a card that opens on a row: a path or branch cut in the middle on one line. Not for: the rows of a form (that is `SettingsTabRow`).

### CodeBlockView
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/CodeBlockView.swift` · Web: `<CodeBlockView>`
Takes: `name`, `file`, `code`, `copyText`, `isDiff`, `runs`, `diffLines`, `monospace`, `foldAfter`, `spare`.
States: normal; a diff; folded (a long block under Show more lines); hover (Copy shows, live).
Use for: a fenced block of an agent's message, coloured by what each piece of code is. Not for: a line of output (that is `MonoLines`).

### HoverCard
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/HoverCard.swift` · Web: `<HoverCard>` around a row
Takes: `.hoverCard { card }` on a view: the card to open.
States: normal (point at the row and rest; the card opens beside it).
Use for: a card that opens beside a row when the pointer rests on it. Not for: a menu (that is the system's).

### WorkCard
Kind: Cards · File: `macos/Sources/CarrierUI/Cards/WorkCard.swift` · Web: `<WorkCard>`
Takes: `.workCard()` on a view.
States: normal.
Use for: the shell of a card in the feed: a fill and glass, rounded 12 (the tool group, the epic's slices). Not for: a notice (that is `NoticeCard`).

### Badge
Kind: Chips · File: `macos/Sources/CarrierUI/Chips/Badge.swift` · Web: `<Badge>`
Takes: `text`, `icon`, `tint`.
States: normal; warning; info (each is a tint).
Use for: what a state of a thing is, in a word and an icon in its colour. Not for: a word with no icon (that is `StatusChip`).

### ChosenMark
Kind: Chips · File: `macos/Sources/CarrierUI/Chips/ChosenMark.swift` · Web: `<ChosenMark>`
Takes: Nothing.
States: selected.
Use for: the mark of the chosen row of a list: a white tick on the accent. Not for: a switch (that is a `Toggle`).

### PullRequestChip
Kind: Chips · File: `macos/Sources/CarrierUI/Chips/PullRequestChip.swift` · Web: `<PullRequestChip>`
Takes: `number`, `dot` (the state's colour), `link`.
States: plain; with a state dot; with a link (an arrow, opens GitHub).
Use for: "PR #736" with a dot for its state. Not for: a state in words (that is `StatusChip`).

### StatusChip
Kind: Chips · File: `macos/Sources/CarrierUI/Chips/StatusChip.swift` · Web: `<StatusChip>`
Takes: `text`, `tint`.
States: normal; warning; error (each is a tint).
Use for: a capsule with a word in it: the state is never the colour alone. Not for: a state with an icon (that is `Badge`).

### BannerView
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/BannerView.swift` · Web: `<Banner>`
Takes: `title`, `detail`, `hint`, `tint`, `account`, `copyDetails` (nil leaves the button out), `retry` (nil makes it a record).
States: error; warning; record (no retry).
Use for: a failed turn or a refused send, as a `NoticeCard`. Not for: a notice that is not a failure (that is `NoticeCard`).

### EmptyStateView
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/EmptyStateView.swift` · Web: `<EmptyState>`
Takes: `icon`, `title`, `line`, `action` (title and closure), `actionIcon`, `actionStyle` (secondary or accent glass).
States: empty; with an action; with an accent glass action and icon.
Use for: nothing to show: icon, title and a line, centred. Not for: a list that is loading (that is `LoadingStateView`).

### EmptyStateActionStyle
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/EmptyStateView.swift` · Web: `<EmptyState actionStyle>`
Takes: A value of `EmptyStateView`: `secondary` or `accentGlass`.
States: drawn with `EmptyStateView`.
Use for: which button an empty state's action wears. Not for: any other button.

### LoadingStateView
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/EmptyStateView.swift` · Web: `<LoadingState>`
Takes: `title`, `line`.
States: loading (it appears after a quarter of a second, so a quick load never flashes it).
Use for: the shape of an empty state while its content is on its way. Not for: a button that works (that keeps its label and shows a small spinner).

### GlowEdge
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/GlowEdge.swift` · Web: `<GlowEdge>`
Takes: `color`, `waiting`, `moves`, `cornerRadius`.
States: working (an arc goes round); waiting (the edge breathes); still (no motion).
Use for: the glow on a card's edge while an agent works or waits. Not for: a progress bar (that is `SegmentedProgress`).

### ProblemLine
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/ProblemLine.swift` · Web: `<ProblemLine>`
Takes: `text`, `font`, `announces` (says it to VoiceOver when it appears or changes).
States: error.
Use for: a line that says what went wrong, in orange. Not for: a problem of the whole page (that is `NoticeCard`).

### RollingTitle
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/RollingTitle.swift` · Web: `<RollingTitle>`
Takes: `text`, `waiting`.
States: normal; waiting (quiet, with a shimmer); the roll when the text changes (live).
Use for: a session's title in the sidebar, which rolls when it changes. Not for: a title that never changes.

### Shimmer
Kind: Feedback · File: `macos/Sources/CarrierUI/Feedback/Shimmer.swift` · Web: `<Shimmer>` around a text
Takes: `active`.
States: normal; working (a light sweeps over the text).
Use for: a light over a text that is being written. Not for: a spinner.

### NumberField
Kind: Fields · File: `macos/Sources/CarrierUI/Fields/NumberField.swift` · Web: `<NumberField>`
Takes: `key`, `value` and `unparsable` (bindings), `parse`, `format`, `step`.
States: normal; error (an orange ring, from the row's `problem`); focus (live).
Use for: a number with minus and plus buttons that Save follows as it is typed. Not for: a text (that is `SettingsField`).

### SettingsField
Kind: Fields · File: `macos/Sources/CarrierUI/Fields/SettingsField.swift` · Web: `<TextField>`
Takes: `.settingsField(width:icon:focused:)` on a `TextField`.
States: empty; with text; with an icon; error (an orange ring and a mark); focus (live).
Use for: a text field of a form: a quiet fill and the accent as its ring. Not for: a search of a sidebar (that is `SidebarSearchField`).

### SidebarSearchField
Kind: Fields · File: `macos/Sources/CarrierUI/Fields/SidebarSearch.swift` · Web: `<SidebarSearchField>`
Takes: `placeholder`, `text`, `focus`, `close`.
States: empty; with text (a clear button).
Use for: the search of a sidebar section, a row of its own. Not for: a toolbar search (that is `ToolbarSearchField`).

### SidebarEmptyBlock
Kind: Fields · File: `macos/Sources/CarrierUI/Fields/SidebarSearch.swift` · Web: `<SidebarEmptyBlock>`
Takes: `icon`, `title`, `line`, `action` (a slot).
States: empty; with an action.
Use for: what a section's list says when it has nothing. Not for: a page that is empty (that is `EmptyStateView`).

### SidebarNoResults
Kind: Fields · File: `macos/Sources/CarrierUI/Fields/SidebarSearch.swift` · Web: `<SidebarNoResults>`
Takes: `icon`, `title`, `line`, `clear`.
States: no results.
Use for: what a section's list says when a search matches nothing, with a button that empties the field. Not for: a list that is empty.

### Glyph
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/Icons.swift` · Web: `<Icon>`
Takes: `icon` (an `AppIcon`), `size`, `bold`, `label` (for an icon that is a state on its own); `Label(_:icon:)`; the effects `glyphSpinning`, `glyphBouncing`, `glyphKick`, `glyphPulsing`.
States: normal; large; bold (a white mark on a colour); working (turning); each icon set (Tabler, Lucide, SF Symbols).
Use for: an icon of the interface in the set the person chose. Not for: an icon the system draws (a menu's keeps its SF Symbol).

### IconImages
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/Icons.swift` · Web: the icon set's own image lookup
Takes: `image(_:set:weight:bold:pointSize:)`, `inline(_:side:set:weight:)`.
States: each icon set (drawn with `Glyph`).
Use for: the image of an icon where a view cannot go: an attachment, a layer, an inline text. Not for: a view (that is `Glyph`).

### AccountMark
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/AccountMark.swift` · Web: `<AccountMark>`
Takes: `symbol`, `initials`, `tool`, `tint`, `size`.
States: with a symbol; with initials; with the tool's mark.
Use for: the mark of an account. Not for: a provider (that is `ProviderMark`).

### BrandLogo
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/BrandLogo.swift` · Web: `<BrandLogo>`
Takes: Nothing; a dev build draws it in pink with a DEV MODE badge.
States: normal.
Use for: the logo over the sidebar's title bar. Not for: anywhere else.

### CardChevron
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/CardChevron.swift` · Web: `<CardChevron>`
Takes: `open`, `width`.
States: folded; open.
Use for: the chevron at the end of a card's line, right when folded and down when open. Not for: a row that opens a screen (that is the chevron of `NavigationRow`).

### Disc
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/Disc.swift` · Web: `<Disc>`
Takes: `color`, `mark`, `symbol`, `size`.
States: normal; told apart by shape (the symbol in its colour).
Use for: a state's disc: a filled circle with a white mark. Not for: a state with a word (that is `StatusChip`).

### ProjectIcon
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/ProjectIcon.swift` · Web: `<ProjectIcon>`
Takes: `initials`, `color`, `mark`, `image`, `working`, `background`, `finished`.
States: initials; a mark; an image; working (an arc goes round); waiting (cyan); finished (green).
Use for: a project's icon, glass tinted with its colour. Not for: an account (that is `AccountMark`).

### ProviderMark
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/ProviderMark.swift` · Web: `<ProviderMark>`
Takes: `name` (the tool), `size`.
States: each tool's mark; a tool with none (its first letter).
Use for: the mark of a provider in the text colour. Not for: an account's own mark (that is `AccountMark`).

### StateGlyph
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/StateGlyph.swift` · Web: `<StateGlyph>`
Takes: `look` (ring, disc or hollow), `label`.
States: working (a turning ring); done and error (a disc with a mark); waiting (a hollow circle).
Use for: the glyph of an epic's state, 20 points square. Not for: a one-off status (that is `StatusMark`).

### StateMark
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/StateMark.swift` · Web: `<StateMark>`
Takes: `text`, `symbol`, `size`, `weight`.
States: normal (its text); told apart by shape (its symbol).
Use for: what a state wears inside its glyph. Not for: a mark on its own.

### StatusMark
Kind: Icons · File: `macos/Sources/CarrierUI/Icons/StatusMark.swift` · Web: `<StatusMark>`
Takes: `symbol`, `color`, `label`.
States: done; warning; failed.
Use for: a state as a 16 pt round mark with a white symbol. Not for: a state of an epic (that is `StateGlyph`).

### FlowLayout
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/FlowLayout.swift` · Web: `<Flow>` (flex wrap)
Takes: `spacing`.
States: normal (a row that wraps).
Use for: chips of different widths that start a new row when the next does not fit. Not for: columns of equal width (that is `EqualWidthRow`).

### EqualWidthRow
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/EqualWidthRow.swift` · Web: `<EqualWidthRow>` (grid of equal columns)
Takes: Its children.
States: normal.
Use for: children side by side, each as wide as the widest. Not for: chips that wrap (that is `FlowLayout`).

### TickingTimeline
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/LookingTimeline.swift` · Web: `useTicker(every)`
Takes: `every` (seconds), `content`.
States: working (a clock that ticks); still (nobody looks: only its first tick).
Use for: a clock ("Working for 1m 23s") that stops while nobody can see the window. Not for: an animation (that is `MovingTimeline`).

### MovingTimeline
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/LookingTimeline.swift` · Web: `useFrames()`
Takes: `content`.
States: working (a moving dot).
Use for: an animation at most 30 frames a second that stops while nobody can see the window. Not for: a clock (that is `TickingTimeline`).

### LookingSchedule
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/LookingTimeline.swift` · Web: part of `useTicker`
Takes: `period`, `paused`.
States: drawn with `TickingTimeline`.
Use for: the schedule `TickingTimeline` runs on. Not for: a `TimelineView` of your own, which would keep drawing in a hidden window.

### SettingsDivider
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/SettingsDivider.swift` · Web: `<Divider>`
Takes: `vertical`.
States: horizontal; vertical.
Use for: the line between two rows: one whole point, quiet. Not for: the system's `Divider`, a grey hairline that stands out on dark themes.

### SettingsPageBody
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/SettingsPageBody.swift` · Web: `<SettingsPage>`
Takes: `reset` (what the toolbar's menu runs after asking), its groups as content.
States: normal (a column of cards here; a native form on a page that is one).
Use for: what a Settings page is made of. Not for: a screen of its own.

### SettingsPreview
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/SettingsPreview.swift` · Web: `<SettingsPreview>`
Takes: Its sample as content.
States: normal.
Use for: a sample of what the rows around it change, inside their group. Not for: a card on its own.

### UnderlineTabs
Kind: Layout · File: `macos/Sources/CarrierUI/Layout/UnderlineTabs.swift` · Web: `<Tabs>`
Takes: `items` (id, title, icon, count, count colour), `selection`, `fill`.
States: normal; with icons and counts; filling the width.
Use for: a row of tabs with no box and a line under the chosen one. Not for: a few choices that exclude each other (that is `SegmentedChoice`).

### QuotaBar
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/QuotaBar.swift` · Web: `<QuotaBar>`
Takes: `solid`, `hatched`, `height`.
States: empty; normal (solid and hatched); high (orange from 90 %).
Use for: a quota's track: the use that stays is solid, the use the next reset gives back is hatched. Not for: parts of one whole (that is a disk bar).

### QuotaPercent
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/QuotaPercent.swift` · Web: `<QuotaPercent>`
Takes: `used` (0 to 1).
States: normal; high (orange from 90 %).
Use for: the number of a quota, beside its bar. Not for: any other percent.

### SegmentedProgress
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/SegmentedProgress.swift` · Web: `<SegmentedProgress>`
Takes: `done`, `total`, `tint`.
States: some done; all done; more than 20 steps (it stays at 20 segments).
Use for: a progress bar of separate steps. Not for: a quota (that is `QuotaBar`).

### SpinningRing
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/SpinningRing.swift` · Web: `<SpinningRing>`
Takes: `diameter`, `lineWidth`, `color`; `RingLayer` and `RingHostView` are the layer and the AppKit view it is drawn with.
States: working (the arc turns, still under Reduce Motion or a hidden window); another colour.
Use for: a ring that turns by one Core Animation animation, for something that runs. Not for: a bar that fills.

### RingLayer
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/SpinningRing.swift` · Web: part of `<SpinningRing>`
Takes: `diameter`, `lineWidth`, `color`, `animate` (`RingLayer.make`).
States: drawn with `SpinningRing`.
Use for: the Core Animation layer of a ring: a faint track and an arc that turns with one animation. Not for: a view (that is `SpinningRing`).

### RingHostView
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/SpinningRing.swift` · Web: part of `<SpinningRing>`
Takes: `diameter`, `lineWidth`, `color` or a `symbol`; `reduceMotion`.
States: drawn with `SpinningRing` and `SpinningGlyph`.
Use for: the AppKit view that holds a `RingLayer` and stops it while nobody can see the window or Reduce Motion is on. Not for: a view (that is `SpinningRing`).

### SpinningGlyph
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/SpinningRing.swift` · Web: `<SpinningGlyph>`
Takes: `symbol`, `diameter`.
States: working.
Use for: an icon that turns by the ring's rule. Not for: an icon that does not move (that is `Glyph`).

### WorkingRing
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/WorkingRing.swift` · Web: `<WorkingRing>`
Takes: `finished`, `background`; `WorkingRingHostView` is the AppKit view it is drawn with.
States: working; waiting (cyan); finished (green).
Use for: the arc that goes round a project icon while an agent works. Not for: a ring on its own (that is `SpinningRing`).

### WorkingRingHostView
Kind: Meters · File: `macos/Sources/CarrierUI/Meters/WorkingRing.swift` · Web: part of `<WorkingRing>`
Takes: `size`, `radius`; `reduceMotion`, `background`, `finished`.
States: drawn with `WorkingRing`.
Use for: the AppKit view that draws the arc round a project icon and stops it by the rings' rule. Not for: a view (that is `WorkingRing`).

### HoverRow
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/HoverRow.swift` · Web: `<HoverRow>`
Takes: `action`, `fill`, `content` (it is told whether the pointer is over).
States: normal; selected (`fill`); disabled; hover (live).
Use for: a row that is a button. Not for: a row of Settings (that is `SettingsTabRow`).

### MonoLines
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/MonoLines.swift` · Web: `<MonoLines>`
Takes: `lines`, `redFirst`, `monospace` (wrap, line numbers).
States: wrapped; scrolling with line numbers; the first line red.
Use for: lines of output as the monospace settings draw them. Not for: a block of code (that is `CodeBlockView`).

### NavigationRow
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/NavigationRow.swift` · Web: `<NavigationRow>`
Takes: `title`, `detail`, `leading`, `first`, `action`, `trailing` (a slot).
States: normal; with a tile before the title and a value at the end; hover (live).
Use for: a row that opens a screen, a chevron at its end and clickable all over. Not for: a row with a control (that is `SettingsTabRow`).

### SettingsStackedRow
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/SettingsStackedRow.swift` · Web: `<SettingsStackedRow>`
Takes: `id`, `title`, `detail`, `first`, `control` (a slot).
States: normal.
Use for: a row whose control is wide: title and detail on top, the control under them. Not for: a row with a short control.

### SettingsTabRow
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/SettingsTabRow.swift` · Web: `<SettingsRow>`
Takes: `id`, `title`, `detail`, `first`, `mono`, `roomy`, `note`, `problem`, `wrapsDetail`, `leading`, `control` (a slot).
States: normal; with a note; with a tile; error (`problem` replaces the detail, in orange); disabled.
Use for: a row of a Settings card: title and detail at the left, the control at the right. Not for: a row that opens a screen (that is `NavigationRow`).

### SidebarSectionRow
Kind: Rows · File: `macos/Sources/CarrierUI/Rows/SidebarSectionRow.swift` · Web: `<SidebarSectionRow>`
Takes: `title`, `icon`, `selected`, `keepActions`, `action`, `actions`, `hoverActions` and `below` (slots).
States: normal; selected; with actions (always there) and hover actions (kept while `keepActions`); hover (live).
Use for: a sidebar section: an icon, a title and its actions. Not for: a session row.

### SelectMenu
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/SelectMenu.swift` · Web: `<Select>`
Takes: `items` (the words), `selection` (an index).
States: normal; disabled; open (the system's menu, live).
Use for: a choice among a few words, the app's one select. Not for: a few choices at once (that is `SegmentedChoice`).

### ChoicePopUp
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/ChoicePopUp.swift` · Web: `<Select>` over values
Takes: `label`, `options` (value and title), `selection` (the value).
States: normal; disabled.
Use for: `SelectMenu` over a value, so a page binds the value itself. Not for: an index.

### SegmentedChoice
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/SegmentedChoice.swift` · Web: `<SegmentedChoice>`
Takes: `options` (value, title, icon), `selection`.
States: normal; with icons; hover (live).
Use for: a few choices that exclude each other in one capsule; the chosen one slides. Not for: a filter that grows with the data.

### SelectButtonStyle
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/SelectButtonStyle.swift` · Web: `<SelectButton>`
Takes: Nothing.
States: normal; disabled; hover and pressed (live).
Use for: the face of a button that opens a choice: its words and `SelectChevron`, a box only under the pointer. Not for: a select in a form (that is `SelectMenu`).

### SelectChevron
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/SelectChevron.swift` · Web: `<SelectChevron>`
Takes: Nothing.
States: normal.
Use for: the up and down chevrons of a select in their small circle. Not for: a row that opens a screen.

### ThemeGallery
Kind: Selects · File: `macos/Sources/CarrierUI/Selects/ThemeGallery.swift` · Web: `<ThemeGallery>`
Takes: `cells` (`ThemeCell`: an id, the name it goes by and the theme drawn), `chosen` (a cell's id), `action` (the id picked).
States: normal (the chosen cell with the accent's edge); long (forty cells: three rows, half a column cut at the right edge, the forward arrow); at the end (the last column whole, the back arrow only); hover and focus (live).
Use for: choosing one theme among many: cells of a light and a dark preview with the name under them, in three fixed rows that fill column by column and scroll sideways, so the page's height does not change with the number of themes; the arrows at the sides scroll by three columns and hide at the ends; up and down move a cell inside a column and left and right one column (`themeGalleryMove`), choosing as they go and scrolling until the cell is whole. Not for: a choice among a few words (that is `SelectMenu` or `SegmentedChoice`).

## What only macOS does

A web front-end does not copy these; it draws the nearest thing its platform has.

- **Glass.** The toolbar's pills, the accent pill (`AccentGlassPillButton`), the cards of the feed (`NoticeCard`, `WorkCard`, `CodeBlockView`) and the project icon are `glassEffect` surfaces.
  A front-end without glass draws the flat surface that Settings > Chat > Surfaces already offers: the window's colour under a quiet fill and a fine edge.
- **The window's furniture.** The toolbar and its pills, the sidebar `List`, the Settings window's native `Form` pages and the sheets and alerts are the system's; [the page](#the-page) and [Buttons](#buttons) say how they are used.
- **System controls with the app's tint.** `SelectMenu` is the system's pop-up, and the switches, sliders and `ProgressView` take the window's `tint`; a web front-end draws its own with the same accent.
- **AppKit inside a piece.** The rings (`SpinningRing`, `WorkingRing`), the card that opens on a row (`HoverCard`, an `NSPopover`) and the middle-click close are AppKit; the environment (text size, `PieceTheme`) reaches them through the four `NSHosting*` roots (the Settings window, the main window, the dictation widget and the hover card).
- **SF Symbols is an icon set only the Mac has**; Tabler and Lucide are drawn the same everywhere ([Icons](#icons)).
- **Things with no web counterpart**: the Dock and the menu bar, global shortcuts, the dictation widget panel ([the widget](#the-dictation-widget)), Quick Look and Show in Finder.

## The page

A Settings page is groups of rows under the window's toolbar, which says what page it is (`SettingsWindow.swift`; the rows, groups, selects and fields it is made of are under `CarrierUI/`, General, Appearance and Notifications are files of `Features/Settings/`, the Sidebar page is `Carrier/Features/Sessions/SidebarTab.swift` and the Chat page `Carrier/Features/Chat/ChatTab.swift`).
Settings is a window of its own with a native sidebar (`List` in `.sidebar` style, a colored tile before each name, `SettingsTile`) and a toolbar: the page's name is the title and its line the subtitle, ‹ › go back and forward, the page's note (`SettingsNoteView`) and, only on a page that has a Reset, the ⋯ menu are at the right. A page with screens of its own (Providers) sets its screen's title and subtitle (`SettingsTitle`), a screen that edits something (an account) asks the toolbar for its Save or Add (`SettingsSave`), on an accent glass pill with the verb's own icon (Save a check, Add a plus), and a screen with a toggle in its header (Pin on a project's page) asks for a `SettingsHeaderAction` pill (`ToolbarPillButton`). There is no header inside the page and no close button: ⌘W closes the window.

| Piece | What it is |
|---|---|
| `SettingsPageBody(reset:)` | What a page is made of. A page in `SettingsPage.usesForm` gets a native `Form` (`.formStyle(.grouped)`: its groups are sections, its rows labeled content, and the form scrolls by itself); the others (the repos, the checks) keep a column of cards in the window's scroll. Give it `reset` and the toolbar's ⋯ menu runs it after asking "Reset <page>?": a page does not draw its own Reset card. |
| `SettingsGroup(title:)` | A small uppercase title over a card, or a `Section` of a form. `footer:` is the longer word about the whole group (under the card or the section), so a row's own line stays short; `SettingsGroup(title:accessory:content:)` puts a control at the right of the title (the models table's recognizer chips). |
| `StatusChip(text:tint:)` (`CarrierUI/Chips/StatusChip.swift`) | A capsule with a word in it, its colour at 16 % under the same colour; the word carries the state, never the colour alone (Dictation's models table: Live, When you stop; Usage's Stale). |
| `DiskBar(shares:color:)` | A bar of parts of one whole (`DiskBar.swift`): one segment for each part, as wide as its share, 1 pt apart on a `primary` 12 % track, 8 pt high and hidden from VoiceOver, so the rows under it say what it draws. The colour of a part is also a 7 pt dot before its figure in its row, or the bar would be a picture with no key (a project's Worktrees and disk group). It is not a meter: a percentage of a limit is `QuotaBar`. The shares are a pure function with a test (`diskShares`). |
| A worktree's two chips | A worktree's row in a project's Worktrees and disk group ends in an activity and an integration, each a `StatusChip` and read apart, then its pull request as a `PullRequestChip` (no dot: the integration says the state; its number opens GitHub). The activity is there only when one applies: Session open (the accent) or Uncommitted changes (orange). The integration is always there, one word: Merged (purple, as a merged pull request is everywhere), In main (green), Not pushed (orange), PR open (blue), PR closed and Pushed (secondary); In main is git's word (the work is already in the remote default branch) and Merged is only for a pull request GitHub says is merged. The activity sits over the integration (the row has one line more only when there is one), and the chips, the link and the Remove button keep their width at the narrowest window: the branch and the session's words give way. Remove is the trash icon alone (a 24 pt glyph in `HoverFillButtonStyle`, `secondary`, no word): its tooltip is "Remove this worktree's folder", or "Its session is open" while it is disabled, and its accessibility label names the branch (`IconButton` is not used because its name is both the tooltip and the label). |
| `Badge(text:icon:tint:)` | `StatusChip` with a symbol before the word (`CarrierUI/Chips/Badge.swift`). As the label of a plain `Button` it is a small action that is also a state: Usage's `Unpriced · Map` (orange) and `Custom` (secondary) open the price sheet; give the button an `accessibilityLabel` that says what it does. |
| `SettingsTabCard` | The card: 14 pt side padding, rounded 14, `secondary` at 7 %. |
| `SettingsTabRow` | A row of a card (a `LabeledContent` in a form): title, detail (and `note`, a quiet monospaced third line, cut in the middle to one line, with its whole text as a tooltip and selectable to copy), the control at the right. `leading:` is a tile at the left of the title (Providers' `AccountTile`: the account's mark, 22 pt, in a 38 pt rounded square at `primary` 7 %, so it reads as an avatar); the rest of the row keeps its place. `id:` is what the search finds the row by (see `settingsIndex`). `first: true` on the first row (no line above it). `roomy: true` for a form with many stacked fields (14 pt above and below instead of 10). `wrapsDetail: true` lets the detail run over as many lines as it has instead of two, for a report whose every line is to be read (a clean-up's skipped worktrees). |
| The Finished worktrees row | The row of a project's Worktrees and disk group that holds Clean up: the title is "Finished worktrees", the detail says what it takes ("Merged or already in main, nothing blocks them: 3 worktrees, 1.2 GB", the count and size as the host's preview gives them), and the button is Clean up, with its question and its report. It takes the worktrees that have a session, are Merged or In main and have no activity, never one with no session; it is drawn only when the host says any can be taken. |
| `.settingsCard()` | The card's background as a modifier (rounded 14, `secondary` at 7 %), for a list, a note or a card that is not a group of rows. Never write the fill out again. |
| `.sectionLabel()` | The type and colour of the small uppercase title (`caption2`, semibold, `secondary`, upper case by `textCase`), for a title that cannot be a `SettingsGroup` (a list's label, the owners of a picker). The caller adds the padding its place needs; write the text as a normal sentence, not in capitals. |
| `SettingsDivider` | The line between two rows: 1 pt, `primary` at 7 %. `SettingsDivider(vertical: true)` is the line between two columns (Usage's four figures); give their `HStack` `.fixedSize(horizontal: false, vertical: true)` so the line takes the height of the tallest. |
| `EmptyStateView` | Icon, title and one line, centred. For nothing to show: not installed, not running, no model. Give it `.frame(minHeight: 260)` inside a page, or the height of what it stands for inside a card (Usage's chart, 220, so the card does not jump). Its `action` is the way out (Clear filters), a `SecondaryCapsuleButtonStyle` capsule by default or an `AccentGlassPillButton` (`actionStyle: .accentGlass`) with `actionIcon` before its words. `LoadingStateView` is its twin while something loads. |
| `ShortcutRecorderRow` | A row to record a global shortcut (`GlobalDictationGroup.swift`, used by Dictation's and Keep awake's pages): the keys in a cap, Record (Esc cancels) and, with `emptyText`, Clear. Every parameter that belongs to a consumer is required (`current`, `save`, `taken`, its words), so a new consumer cannot write over Dictation's by leaving one out; `problem` is why a recorded shortcut is not registered and `taken` refuses keys another feature has. While it listens it lets go of both global shortcuts, or pressing the old keys would run them instead of recording. |
| `SettingsPreview` | A sample of what the rows around it change, inside their group (the terminal's, the time format's, Dictation's widget style). |

Spacing: **14 between blocks, 4 inside a block** (a name and its version), 12 between a tile and its text. A row's line is one line: what does not fit goes to the group's `footer`.
A page of full-width lists (Health, the Projects list) has `isColumn` false, and a screen of its own that such a page opens (a project's) is a column all the same: `SettingsPlace.isColumn` says which, so the list takes the window and the screen is read as a line.
A list of things that open a screen (the projects) is a card of `NavigationRow`s, the first with `first: true` so no line is above it, each with its tile before the name; the empty list is an `EmptyStateView` in the same card with its one action as an `accentGlass` pill, and Add project over a list that has rows is a small Secondary button at the right above the card.
A row that stands for work that is not a place yet (a clone) is the same row with no chevron and cannot be clicked: its name with a `StatusChip` (Cloning in the accent, Failed in orange), the progress line or the reason under it (orange when failed) and, for a failure, a small Secondary Dismiss button at the end.
A page that is a column (`SettingsPage.isColumn`, `settingsColumnWidth`) is centered by `.contentMargins(.horizontal, _, for: .scrollContent)` on its scroll view and never by narrowing the view: the scroll bar stays at the window's edge and what scrolls under the toolbar reaches both sides of it.

**What can be searched is `settingsIndex`** (`CarrierCore/Settings/SettingsIndex.swift`): a new row or group is added there in the same change, with its page, its group and the copy keys of the words it says (the keys its page reads for the row, in English and in Spanish), and the row (`SettingsTabRow(id: "icon-style", title: …)`, also `SettingsStackedRow` and `SettingsGroup`) carries the same identifier; `SettingsIndexDriftTests` pairs them by identifier and fails for a row drawn with no entry and for an entry no view draws. A row is found by the identifiers of its page, group and row, never by a title, so a title can be changed or translated without the index; a row that is not searched (a value, an account) is drawn with no `id`. The test reads identifiers only, not descriptions: when a setting changes what it does (a text size that stops reaching the messages, a density that stops setting their gap), grep the old words in `settingsIndex`, the row's own detail, `docs/macos/settings.md` and the specs, and fix each description that now says otherwise.

## Cards in the feed

One shell for every card that is "a line on top and rows under it": **`.workCard()`** (`WorkCard.swift`), a `primary` fill at 4.5 % under glass, rounded 12.
The tool group of a session, a markdown table, a slice, a review's findings and a closing line wear it, so the look is changed there once; never write the fill and the glass out again.
A surface of the conversation (that shell, the person's bubble, a code block, an attachment, a notice, an approval, the message box and its buttons) takes its glass from **`.chatSurface(_:flat:in:)`** (`ChatSurface.swift`), never from `glassEffect`: Settings > Chat > Surfaces turns it flat (a quiet fill over the window's solid color and a 1 pt edge: solid so what scrolls under it is not seen through it; the fill is added first because a later `background` is drawn behind an earlier one). The message box's flat fill is a notch darker than the window in the dark scheme (black at 22 %), not a lighter one.
Work the agent did (calls, thoughts, messages, an error) is drawn with the chat's views (`ChatToolGroupView`, `MarkdownView`, `FailureBannerView`) wherever it shows; do not draw a second tool card.

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
  Its **header** is the window's toolbar (`PanelView`, in `PanelToolbar.swift`): the sidebar's round button, a round ‹ Back button (one level up) in the place of the window's own ‹ › (back and forward through the places chosen, which a subagent view does not draw, so there are never two ‹), then `SubagentTitle` (the description, 13 pt semibold, over "<type> · Subagent of <session title>", 11 pt `secondary`), and where the worktree pill is `SubagentStatePill` (Running with a timer, Finished · duration, Failed or Stopped); the panel button stays; a slice card's has the epic's title in the subtitle ("Builder · <epic>") and the pill where the epic's links are, and no Stop.
  While the subagent runs, a Stop `ToolbarPillButton` (red stop icon, on its own glass capsule) follows the state pill; it is gone once the subagent ended and never drawn for a host that does not list `stopTask`, nor for a slice card's subagent.
  `SubagentTitle` is 34 pt high (the round buttons') and cuts a long title on one line, so the header is as high as the conversation's at any width (`SubagentHeaderTests`, 480, 560 and 900 pt, four states, a 120-character title; a slice card's, Builder and Reviewer, three states).
  Its two lines follow the text size up to 14 and 12 pt and no further, because at 130 % they would be 39 pt and spill out of the toolbar (`theTitleLinesFitTheHeaderAtEveryTextSize`).
- **Rows hang under the line** behind a `SettingsDivider`, edge to edge.
- **A row that opens or links is one click target as a whole**: a 4 % fill under the pointer, and no lone small icon as the only way in.
  A `Button` or a `Link`, never only `.onTapGesture`: a tap gesture is not reachable with the keyboard.
- **An arrow that says "this opens GitHub" shows under the pointer**, not all the time.
- **A notice about an account wears its mark before the title** (`NoticeCard(account:)`, which takes an `AccountMark`; the failed turn's banner), only when the account has an icon, a color or a label; one with none shows the title alone, as the footer of an answer does.
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
- **The text of a message (the agent's answer, the person's bubble) takes `.chatText()`, not `.scaledFont`**: its size and line spacing are the chat's own, which the app's text size does not multiply (the person's bubble and a subagent's brief pass `bubble: true`: they add no room between lines at Normal), and the gap between messages is `MessageSpacing.gap`, not the density. A font outside `ScaledFont.swift` still cannot be built from a number: use `Font.chat` / `NSFont.chat`.
- **What ends a feed (a stop that needs a person) is a `NoticeCard` as its last element**, never pinned: orange for what needs a person and red for what failed.
- **A row of a session's feed (`FeedRowView`) is `Equatable` and its `==` lists everything it draws**: a new input goes into `==`, or its change is not drawn.
  What a row asks of the conversation (Continue, Try again) comes from `\.feedActions`, a value that is equal at every pass, never from a closure made in the parent's body: a different closure each pass draws every row again.
- **Every `NoticeCard` is glass filled with its own colour** (the closed-session notice's look) and nothing else: no edge, no neutral dark variant; the colour and the badge say what it is (red for what failed, orange for what needs a person, cyan for what waits in the background). It goes through `chatSurface`, so Flat draws it as a quiet fill.
- **A problem the person is told of in a session or in a new one is `ProblemNotice`** (orange for what is theirs to solve: a refusal of the host, a name that cannot be used, no provider ready, a host older than the app; red for what failed: a session that could not be read, a dictation, a folder), or `BannerView` for a refused send or a failed turn (it adds Try again and the line that says where to sign in); never a plain coloured line under the box. Every message of the conversation that is not a message is one `NoticeCard`. `splitNotice` breaks a sentence into title and detail. `--fixture` has the session "Notices" (`NoticesGalleryView`) with all of them at once, to look at a change to one beside the rest. What is left as a line on purpose: Settings' `ProblemLine`, the dictation widget's own notices, the sidebar's blocks (a narrow column) and the text inside a row of a list.
- **The actions of a `NoticeCard` are `NoticeActionStyle`, never the accent**: the accent the person chose does not read on the card's glass (violet on grey was 2.7:1). The main action is the card's own colour (lighter on dark, deeper on light) on a pill of that colour; the quiet one (Copy details, the cross that drops a queued message) is near-primary words with a pill under the pointer. The card hands its colour down in `noticeTint`. Its detail and hint are `primary` at 78 %, not `secondary`.
- **Links in a toolbar are `ToolbarPillButton`s on one glass capsule**; the item hides the toolbar's own glass (`sharedBackgroundVisibility(.hidden)`).
- **A screen with several actions puts them in the toolbar through `SettingsHeaderButtons`** (`settingsHeaderButtons` in the environment: `set(owner, [(button, run)])` when it appears and whenever a button's state changes, `clear(owner)` when it goes), which draws one glass capsule with a `ToolbarPillButton` for each (Watching's Check now and Watch a project…); a single toggle is `SettingsHeaderAction` (Pin). Not buttons in the page's first row.

## Lines

Always `SettingsDivider`, never `Divider()`: the system's is a grey hairline that stands out on the dark themes. It is one whole point on purpose; **a half-point line over a translucent fill is drawn uneven on a Retina screen, so do not use `lineWidth: 0.5`.** Put the line in the row's `.overlay(alignment: .top)` and **put extra padding inside the row, never outside it**, or the line stops being halfway between two rows.

## Icons

The interface's own icons are named by what they mean (`AppIcon`, `CarrierCore/Shell/AppIcon.swift`: `.check`, `.close`, `.search`…).
They are drawn in the set the person chose in Appearance › Icon set (`IconSet`, `IconSets.swift`): Tabler (the default), Lucide or SF Symbols.
`iconAsset(_:in:)` says which SVG or symbol each icon is in each set.
They are drawn by `Glyph(.check, size: 14)` (`CarrierUI/Icons/Icons.swift`) and, with words, by `Label("Save", icon: .check)`.
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
| Main | `PrimaryCapsuleButtonStyle` | The one action of a form or of a row: Save, Add, Update (Settings > About, the step of an update found); `.controlSize(.small)` inside compact popovers (`TabRenamePopover`). Accent fill, white label; dim when disabled. | `CarrierUI/Buttons/PrimaryCapsuleButtonStyle.swift` |
| Secondary | `SecondaryCapsuleButtonStyle` | Cancel, Remove, Open Agents, Add account, Sign in. A grey capsule; `.controlSize(.small)` inside a row. | `CarrierUI/Buttons/SecondaryCapsuleButtonStyle.swift` |
| Text | `HoverTextButtonStyle(tint: nil)` | Actions of a page header (Update, Open on GitHub) and the chevron. No pill until the pointer is over it. | `CarrierUI/Buttons/HoverTextButtonStyle.swift` |
| Icon | `IconButton` (`HoverFillButtonStyle`) | A 24 pt glyph with a tooltip and an accessible name: close, fold. | `CarrierUI/Buttons/IconButton.swift` |
| Toolbar pill | `ToolbarPillButton`, `AccentGlassPillButton`, `ToolbarGlassIconButton` or `ToolbarSearchField` on `.glassEffect(.regular, in: .capsule)`, its item with `sharedBackgroundVisibility(.hidden)` | An action or inline search pill in the window's title bar (Search, Filter, Check again, Stop, New session, New Terminal) or a compact glass pill strip (floating pane controls), plus the sidebar's Update (`UpdatePill`, for the states of a download). An item of the sidebar column's `.toolbar` goes after the window's buttons with `placement: .automatic`; `.navigation` puts it on the detail's side. | `ToolbarPillButton.swift`, `UpdatePill.swift` |

- **A button that does something has an icon** with its words: `Label("Save", icon: .check)`. Used: Save `.check`, Cancel `.close`, Remove `.trash`, Add `.plus`, Check again `.refresh`, Open on GitHub `.externalLink`, Reveal clone `.folder`, Reveal `.folder` and Open `.fileText` (a file), Detect `.refresh`, Use another… `.folderPlus`, Use the Homebrew one `.undo`. Outside a `Menu` give the label `.labelStyle(.titleAndIcon)` when it sits in a text or icon style.
- **A row that acts on a file or folder** (the Engine page's Files) has a Secondary button, Reveal or Open. While the path is missing the button is disabled and reads "Not created yet" with `.folderQuestion`. Its `.accessibilityLabel` is the verb and the row ("Reveal: Logs"), so VoiceOver can tell three such buttons apart.
- **A button that works for a while** (Detect) keeps its label and its size and is disabled while it runs, with a small `ProgressView` beside it that has an `.accessibilityLabel` ("Detecting"); when it ends, the result is announced to VoiceOver. Swapping the label for the spinner makes the row jump and leaves an unnamed button.
- **A button that asks again is `CheckAgainButton`** (`Carrier/Features/Health/CheckAgainButton.swift`, its states in `CheckPhase`, drawn by the piece `CheckButton`, `CarrierUI/Buttons/CheckButton.swift`, which takes the phase as a value): Check again and Check now, in every place. At rest it has the refresh icon and its words; while it checks the arrows turn and it says "Checking…"; a check the person asked for ends in a green mark that draws itself and "Up to date" (a red cross and "Check failed" when it failed, pass `failed:`), for 3 seconds, and rests. A check the page ran by itself (when it opens) ends at rest, claiming nothing. The four faces share one cell, so the button keeps its size and nothing beside it moves; it is never `.disabled` (that dims it): a click while it runs or shows its result does nothing, and one after a failure tries again. The skin is the place's: `.toolbar` (the item adds the glass), `.capsule` (a row of a form, the default) or `.text` (a page's header). Give it `checking:` from the state that already says so; do not draw a spinner beside it.
- A form that is a card has its buttons in a row: Remove on the left, then a `Spacer`, then Cancel and Save, with 10 pt more above than the fields have between them. A form that is a screen of the Settings window (the account editor) has none: Save (or Add) is the toolbar's, Remove is the last row of the form and asks first (its ellipsis is that question, an alert), and Cancel is the window's back.
- **Remove with more than one answer is a `confirmationDialog`, and what stops it is an alert**: a project Carrier made asks Remove from Carrier, Also delete from disk (destructive) or Cancel, with what each does in the message; an alert then names what stops the delete (a session of the project open, a failed move to the Trash) with OK, or, for unsaved work only, offers Move to the Trash anyway beside Cancel. A project the person added keeps the plain Remove alert. An idle session whose folder was deleted gets a grey `NoticeCard` (`FolderGoneNotice`, the trash mark) in place of the closed-session notice.
- Destructive is `role: .destructive`; a plain capsule does not turn red by itself. When a screen has one destructive action, say so with colour (`HoverTextButtonStyle(danger: true)` turns red under the pointer).
- Do not use the system's bordered, borderless or `.glass` buttons in Settings. (`EmptyStateView` uses `.glass` for its one button; leave it.)
- **Middle-click close on tabs or rows uses `.onMiddleClick(perform:)` (`MiddleClickModifier.swift`)** so middle-button events are handled within the view's visible bounds without interfering with SwiftUI left-clicks, hover tracking or context menus.

## Rows that open something

A row that opens an editor or a form shows **a chevron `.chevronRight` at its right and is clickable all over**:

- The chevron is a `Button` in `HoverTextButtonStyle(tint: nil)` with `.accessibilityLabel("Edit …")` and a `.help`; it is dimmed (`.disabled`) while that row is the one open.
- The row has `.contentShape(Rectangle()).onTapGesture { … }` (guard it so a second click on the open row does nothing). A button inside the row (Sign in, Reset, Use in an agent…) keeps its own click: a `Button` takes the click before the row's gesture.
- When the row opens a form below it, the chevron **sits in a fixed 26 × 26 slot and turns 90°** (`rotationEffect`); it must not move or resize. (`RoleRailRow` in `AgentsParts.swift`; Watching's list rows are drawn the same.)

## Fields and selects

- **A text field is `TextField(…).settingsField(width:)`** (`CarrierUI/Fields/SettingsField.swift`): a quiet fill with rounded corners of 8, no line while idle, the theme's accent as a 1.5 pt ring while it has the focus, and a click anywhere in the box puts the cursor in it. `width: 240` for a short value, no width to fill the space given (a multi-line field too). Do not use `.textFieldStyle(.roundedBorder)` in a form. In a form that is a page of the window a field is `TextField("", text:, prompt: Text("…"))` with an `.accessibilityLabel`: a form takes the title of a field for its label (at the left of it, with its text at the trailing edge) and `settingsField` hides it, so a title left as the title would show no prompt and leave the field with no name for VoiceOver.
- **A slider of a row is `settingsSliderWidth`** (210 pt, the width of a field, so the tracks begin on the same line) **with `.labelsHidden()`**: in a form the track is otherwise drawn at about half of its frame, right-aligned in it.
- A search field is the same field with `icon: .search` (`settingsField(icon:)` draws the symbol inside the box) and a prompt that says what it searches ("Search repos").
- A field that saves as the person leaves it (Agents) passes its own focus: `settingsField(width:focused: $focused)`, so the ring and the save follow the same state.
- **A few fixed filters are a `SegmentedChoice`, a filter that grows with the data is a row of `FilterChip`s** (`SegmentedChoice.swift` in `UI/Selects/`, `FilterChip.swift` in `Features/Projects/`: only the Projects page uses it): the recognizer of the speech models, the outcome of a dictation and the visibility of the repositories are segmented ("All" is one more segment, there is no second click to go back to it); the tags of the projects are chips, small capsules that are on (the person's accent, as the piece of the segmented: a 24 % fill, a fine edge and the text lifted or deepened by `accentInk`) or off (a quiet fill and a fine edge), in a row under the search. `SegmentedChoice` is a few exclusive choices in one quiet capsule, the chosen one a piece tinted with the person's accent (`.tint`) that slides to the next, every choice as wide as the widest and with the same type and padding so nothing changes size (Usage's metric and range); the system's segmented `Picker` is not used: it is flat in a view (glass only in a toolbar) and takes the Mac's accent, not the theme's. Chips that exclude each other start with "All" and a second click on the one that is on goes back to it (the projects' tags); an on/off filter ("Hide watched") is a chip of its own at the right of the row; a filter with many values (the owner) is a `SelectMenu`. The filtering is a pure function in `CarrierCore` with a test (`repoGroups`), not logic in the view.
- **The two sides of a branch are drawn the same everywhere** (`WorktreeStart` in `BranchSheet.swift`): Remote is a cloud, `teal`, and Local is a drive, `indigo`.
  The branch picker of a new worktree puts them as a `SegmentedChoice` (with the number of rows of each side in its title) under the search field, full width, one list under it at a time.
  The "from" chip of the sentence and the ref of the summary wear the colour of the side the worktree is cut from, so the ref says where it comes from before it is read.
  A row of the Local tab whose branch is not on `origin` has a `Badge` "not on origin" in `secondary`.
  A row of the Local tab whose branch differs from its copy on `origin` has a `Badge` "N behind origin" (arrow down) and "N not pushed" (arrow up) in orange, each only when it is not zero.
  The summary's warning about the choice (behind with Local, not pushed with Remote) is a `ProblemLine` under the "from" line, inside the same quiet box.
  The footer's "Could not reach origin" is an orange line under when the branches were last fetched, with no button and no error card: the fetch that runs on choosing a project asks nothing of the person.
  The picker of a folder session and of a repository to clone has no tabs, only the two sections it always had.
- **A column title that sorts is a plain `Button` over the title's own text** (the Projects list's Project, Last active and Disk, in `sectionLabel`'s type): the sorted one adds an 8 pt bold `chevronUp` or `chevronDown` after its word, a click on another title sorts by it and a second click on the same reverses it, and the order is a pure `ProjectOrder` with a test, not logic in the view. The titles that do not sort are plain text, hidden from VoiceOver.
  The Project column keeps at least `ProjectColumns.project` points and the others give way by the width the card has, Tags first and then Carrier (`ProjectColumns(contentWidth:)`, with a test); Last active and Disk, the ones that sort, always stay. Fixed widths for every column left the name 40 points wide at the window's first size and none at its smallest.
- **A choice among a few words is `SelectMenu`** (`UI/Selects/`), the one select of the app: the system's own pop-up (a SwiftUI `Picker` in the menu style, `.labelsHidden()` and `.fixedSize()`), which in a form is drawn as the Mac draws it, the chosen word at the right of the row with the up and down chevrons in a small circle, and opens the system's menu with its own check. Outside a form (Usage's filters, a card page) the system would draw a boxed pop-up, so `SelectMenu` draws the same face by hand there (the word and `SelectChevron`, `SelectButtonStyle`) over the same system menu and check: a select looks alike wherever it is. It takes the room of its word: **give it no width**. The model picker's button (`ModelPickerButton`) is the same face (`SelectButtonStyle` and `SelectChevron`: no box, the words and the circle after them) over a popover, so every select looks alike. For a value (an enum, a stored string) use `ChoicePopUp(label:options:selection:)`, which wraps it: the choices are `(value, title)` pairs and the binding is the value itself. Do not use AppKit's `NSPopUpButton` or a hand-made menu button; the first draws badly in a form and the second has its own check and highlight. The first item is "Use default" (the empty value, nothing written) or "Same as everywhere (value)" when it inherits; where the choice is among several rows and at most one holds it (Providers' Text generators, one select a server), it is "Not used", and choosing it on the row that holds the choice clears it. A value already stored that is no longer on the list stays on it, so opening the editor never changes it.
- A text of several lines (an instruction, a prompt) takes the width of the card: `SettingsStackedRow` puts the title and the detail on top and the control under them, and the box is a `TextEditor` in `settingsField()`. Turn the system's writing tools off on it (`.writingToolsBehavior(.disabled)`), or its "Write with Siri" button sits on the box.
- A box of several lines in a row (`TextEditor`, "Launch arguments"): `scrollContentBackground(.hidden)`, 4 pt padding, the same fill, and **the size goes last, around the padding**, so the row grows with it.
- Turn off the system's writing tools on a form of paths and arguments: `.writingToolsBehavior(.disabled)`.
- **A form's controls are one width**, whatever they are (a field, a box, a grid of choices; a select is the exception, it takes its word's): they end on the same line down the card, so the form reads as a column. The account editor's is `AccountEditor.controlWidth`, which is `settingsSelectWidth`; its icon and color choices are not in the form but behind a Change… button that opens them in a popover, in eight 30 pt tiles per row (`AccountEditor.gridWidth`). Do not give each field the width of its value.

## Lists and menus

- **A file of a message is looked at in `AttachmentPreview`** (a sheet of the window's size, `windowSheetSize`): its name and "n of m" and a Secondary `Show in Finder` (`folder`, small) and the `IconButton` close on top, Quick Look under, a glass circle with a chevron at each side (and ← →) only where there is a file further. A chip opens it with `AttachmentChip(open:)`, and only for a file that goes and is not a folder (`canPreview`); the others reveal in Finder.
- **The card that opens on a row (a session's `SessionPeekView`, an epic's `EpicCardView`) draws its facts with `CardFactsGrid`**, by the fact's `kind` (`CardFact`): words wrap, but a folder or a branch is one monospaced line cut in the middle with the whole of it in its tooltip (a long path never breaks over four lines), and an agent is its account's mark and short name; a fact may have a `detail` line under its value (smaller, monospaced, wrapped: a worktree's whole path, the branch it was cut from). The state under the title wears the row's own colour (orange for what needs the person, green for Done), and says Done, as the row does, for a turn that ended unread.
- A row of a form that opens a screen (a provider, an account, a screen of Dictation, with what it holds at the right) is a `NavigationRow`: the whole row is a button with a chevron at its end, and the state it says goes before the chevron; an account's row (`AccountRow`) puts its usage at the right and, when that does not fit, under its text. A list of things to choose from (the repos) is a card with rows of 8 pt side and 6 pt top padding, a rounded 9 fill for the chosen one (`secondary` at 18 %), and a dot or a mark at the right for its state. A last row of the same shape, with a dashed tile and a plus, adds one (`AddRepoRow`).
- A tile for a thing is its mark in a rounded square: the project's `ProjectIcon` (32 pt, radius 9, its chosen image from `project-icons` when present, else its chosen colour and `AppIcon` mark when set, or its initials on a colour made from the name) for a repo or project (`ProjectIcon(base:name:colorKey:)` from a session's base folder and `ProjectIcon(repo:name:colorKey:)` from an epic's repository look the project up in `ProjectsModel.shared` (`projectTile`), so every place that draws a project's icon draws the same one, and what is not a project draws from `name` and `colorKey` as it did before; `ProjectIcon(tile:)` is for a row of the project list itself), `ProviderMark(name:)` for a provider (its bundled icon in the text colour; `accountIcons` in `RepoRoleSave.swift` gives each account its provider's icon).
- **On the Agents page a role is its identity's picture, `RoleAvatar`** (`RoleAvatar.swift`): the bot's own logo (a rounded square of radius 28 % of its side, 38 pt in the rail, 64 pt on a role's screen) or its initials on a color made from its name, with the mark of the account the role runs on in the corner (`AccountMark` in a circle of the window's color and a 1 pt edge, as `AgentAvatar` has it); a person is a person symbol and an identity that is not there a dashed square with a question mark.
  The picture is only help, so a picture that cannot be fetched is never an error: the initials stay.
- **The roles of an epic are `EpicRail`** (`AgentsParts.swift`): one row of the form, the roles as buttons (a 5 % fill under the pointer) and between them a 2 pt line through the middle of the avatars' column with what passes on written beside it (dashed while the Lead reviewer is off).
  It is one row on purpose: separate rows would break the line at every edge.
  A value that is shown and cannot be changed yet (the Skills of a role) is a quiet box in the monospaced face with a `StatusChip` "Default" before it, never a disabled field.
- **An agent role in a list that is not the Agents page (the repos') is drawn with `RoleTile`** (the provider's mark in a 34 pt tile, a power symbol when the role is off) and its settings with `roleSummary` (`Identity gh · Account pro · Model sonnet · Effort high`, the label quiet and the value in the text colour). In a list that is narrow, the model and the effort go on the first line in the text colour and the account and the identity under it. The mark follows the account's harness (`accountIcons`).
- **The model of a role (or of a failover step) is chosen with `ModelPickerButton`** (`Carrier/Features/Chat/ModelPicker.swift`), never typed: a pill with the provider's mark, the model and the reasoning that opens the chat's panel (the providers that can work as tabs, a search, the models, the `ScaleRow` slider for reasoning). Its choices are `ModelPick` values, and the logic of what it lists (`pickerAccounts`, `modelOptions`, `effortSteps`) is in `CarrierCore/Chat/ModelPicker.swift` with tests. A role runs on its own, so the panel shows its access as full, not as a choice. The Repos page uses the same picker for a repo's own roles, with `inherited:` (the first row of the list, and of the slider, is "Same as everywhere", and the pill says what that is) and `fill: true` (the pill takes the width of the form). Settings > Sessions uses it for what a new session starts with, over the chat host's agents and with `showsAccess: false`, since the person chooses the access in the message box.
- **A list that can hold thousands of rows (the dictations of History) draws a page and ends with a Secondary `Show N more`** (small, centred, in the group of the count line), not a `LazyVStack`.
  The page sits in a form inside a `ScrollView`, and the cap is what keeps its cost bounded and testable.
  The cap and what is left are a pure function in `CarrierCore` (`dictationHistory`).
  A new search or filter goes back to the first page; a new or a deleted entry leaves the list where it was.
  Rows that the engine already caps (the files of a section at 500, a diff at 1000 rows) may be a `LazyVStack` instead, since their cost is bounded by that cap.
- **A menu's items have an icon, and a `Label` in a `Menu` or a `contextMenu` needs `.labelStyle(.titleAndIcon)` to show it**; this SwiftUI draws a menu's labels title only otherwise.
- Small facts of a status card are `SettingsTabRow`s: the label as the title, the value as its line under it (monospaced for a path), the action at the right; none draws its own divider. A page of this kind is a `Form` (`SettingsPage.usesForm`), so Agents' pieces (`EpicRail`, `RoleHero`) and the kit's rows keep their own margins.
- A state is shown by a green, orange or grey dot, or by `StatusMark` (`CarrierUI/Icons/StatusMark.swift`, a 16 pt round mark: `.check` green, `.exclamation` yellow, `.close` orange), at the right of a row that has no button or before one. While something runs, **each row turns its own `ProgressView` and says "Checking…"**; the page does not say it once in a corner.

## A value that is not valid

Orange, not red, and nothing moves. This is the default of every row and field: pass the message once, `SettingsTabRow(…, problem: "what is wrong")`, and the row puts it in the place of its detail line, in orange with a warning mark (the title keeps its colour), while every `settingsField` and `NumberField` inside it draws an orange ring and a warning mark in the box, the same size as without them (the row tells them through `\.settingsInvalid`). A new field needs nothing for it; do not pass a flag to the field, and do not colour a whole row red. A message that has no row of its own (a refused save, a page that could not load) is a `ProblemLine`, never a bare orange `Label` or `Text`: only `ProblemLine` is read aloud. Under a field of a sheet that is not a `SettingsTabRow` (Usage's price sheet) it is `ProblemLine(text:font: .caption)`. A page that failed to load shows the problem alone, not its empty state too: "No accounts to show" under an error reads as if there were none. A refused save that belongs to one row (the Engine page's GitHub identity) is that row's `problem`, next to the control that was changed, and the code that saved posts an `AccessibilityNotification.Announcement` with it, since a row's problem is not read aloud by itself.

## What the engine answers to a save

A page that writes `engine.json` or `providers.json` does not wait for Carrier: it writes, asks the engine in the background (`ReloadStatus.ask`, in `CarrierCore/Settings/Engine/EngineReload.swift`) and shows the answer when it comes; an answer older than the last save is dropped. A refusal or a missing answer is a problem and is orange: `ProblemLine` (`CarrierUI/Feedback/ProblemLine.swift`) is the line with the warning mark that VoiceOver reads when it appears, and `ReloadNote` (`Carrier/Features/Settings/ReloadNote.swift`; the page passes it the engine's words) is the page's line for the last answer, with "Ask Carrier again" to ask without saving (the Behavior header offers it too; the doctor's "Check again" is another button). A running Carrier that is too old to reload is not told at all: it reads the file when it starts, and the next one applies it live. A page that is a header note (`SettingsHeaderNoteKey`) wraps it under the title when it does not fit beside it (`ViewThatFits`). The last answer lives in `ReloadStatus.shared`, not in the page's `@State`, so it is still there when the person comes back to the page, and it goes when Carrier starts or stops.

## Meters and charts

- **A quota is a `QuotaBar`** (`CarrierUI/Meters/QuotaBar.swift`), with `QuotaPercent` (`CarrierUI/Meters/QuotaPercent.swift`: its number, bold, orange from 90 %) and `QuotaMeter` (`Carrier/Features/Usage/QuotaMeter.swift`, only the Usage page draws it: name, percent and bar, for a row's header): an 8 pt capsule track, `primary` at 12 % with a 1 pt edge; the use that stays is solid, the use the next reset gives back is `Hatch`ed after it (diagonal 1.5 pt lines every 4 pt over the tint at 30 %). The tint is the theme's accent, orange from 90 %. Its numbers (the shares, the percent, the reset) come from `MeterShape` in `CarrierCore`, and the bar is hidden from VoiceOver: the percent beside it is the text.
- A chart (Swift Charts) sits in a `SettingsTabCard` under a `.sectionLabel()` title, one colour a provider, the legend at the bottom. Hovering a day shows **the chart tooltip** (`Tooltip` in `UsageDailyChart.swift`): 170 pt wide, 8 pt padding, `.regularMaterial` rounded 8 with a 1 pt `primary` at 12 % border, a line per provider with its colour dot, and a `SettingsDivider` before the total; a click keeps it, a second click lets go. The words of the tooltip are a pure function (`usageTooltip`). Every mark has its own `accessibilityLabel` (day and provider) and `accessibilityValue`, so the numbers never depend on the pointer.
- Keep a chart's expressions small and typed (a mark in its own `@ChartContentBuilder` function, `PlottableValue` written out): CI's compiler times out on a big one.
- Usage's provider rows only open and close their drawer (the whole row is the button, its chevron a round 24 pt slot); the filter by provider is a `ChoicePopUp` in the filters row, with the search at its right. A table's total is a `UsageFooter`: a band of its own (`primary` at 7 %) that reaches 8 pt past the rows' text, so it reads as a sum.

## Text

- Titles `fontWeight(.medium)`, details `.scaledFont(11)` in `secondary`, a path or a command `.scaledFont(11, design: .monospaced)`. Use `.scaledFont` (`ScaledFont.swift`), not a fixed size, so the person's text size applies: it reads the size from the environment, which the window's root sets. The system's styles (`.caption`, `.callout`, `.body`, `.title3`) do not follow it: use `.scaledFont(11)` for a detail, `.scaledFont(12)`, `.scaledFont(13)` and `.scaledFont(15)` for the others (`.scaledFont(10)` is for an uppercase label or a pill). A font that has to be a value (an attributed string's run) is `@Environment(\.textScale)`'s `font(_:weight:design:)`, and a sidebar level is `.sidebarFont(_:)` (`SidebarMetrics.Level`).
- Do not put copy-on-hover (`copyOnHover`) on text that says nothing to copy ("Not checked yet", "Checking…"); keep it on a path, a reason and a fix.
- Texts are English, short, and say what the control does, not how it works.

## The dictation widget

The widget of the global dictation (`DictationWidget.swift`) is a floating panel, not a view of the window; [dictation](macos/dictation.md#the-widget-style-and-position) says what it shows.

- **The panel takes the pointer so it can be dragged**: a drag that begins on the box moves it (`WidgetPanel.sendEvent`, from 3 points on so a click does not nudge it), except in the state that holds a copied text, where the text is the person's to select and only the box's margins drag it (the system's `isMovableByWindowBackground`). Where it is let go is kept as a `DictationWidgetSpot` (the centre across the display, the nearer edge and the gap from it, so a box that grows opens away from its edge).
- **A box has one height per style** (2, 3 and 4 lines at 340, 420 and 540 pt, text at 12, 14 and 17 pt through `.scaledFont`), so it never jumps while the text grows: the text scrolls inside it. The Pill is a 76 by 38 capsule with an icon and no text.
- **It wears `WidgetSurface`** (`.chatSurface` tinted by the theme, never its own fill) and is drawn once by `WidgetBox` and `PillIcon`, which the Preview in Settings and the theme picker's swatches use too. The themes are `DictationWidgetTheme`: Default is the accent at 12 % in light and the accent mixed 60 % into black at 55 % in dark, so the text reads over a white window; Black, Dark glass and Theme glow force their text's dark appearance (`DictationWidgetTheme.appearance`: the panel's hosting view takes it, the Preview and the swatches set the colour scheme), so the text reads over their own colour whatever the app's is; Clear glass is the system's glass with no tint at all and its text follows the system's appearance. Glow is the listening line's own colours (`DictationIndicator.accentColors(_ color: Color)`: the accent and two neighbouring hues) as a gradient from the left edge to the right one (never from the centre: a wide box would show a wedge), at 60 % over dark glass, with a 1 pt light edge and an accent shadow that fits in the panel's `glow` margin. These are first numbers, to be checked by hand over a white and a dark window in light and dark appearance and then written here as the ones that hold.
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
- A switch is the size a native `Form` gives it (what `.controlSize(.mini)` draws, 36 pt wide) on every settings page. The pages that are not a `Form` (Projects, Watching, Health) draw it at 54 pt unless the switch says `.controlSize(.mini)`.
- The system's switches and sliders take the `tint` of the window (`.themed()`); a view draws the accent with `.tint` as a shape style (`.fill(.tint)`, `.foregroundStyle(.tint.opacity(0.2))`), and with `@Environment(\.pieceTheme)`'s `accent` where it needs a `Color` (a ternary between colors, `mix`, an AppKit bridge); `.themed()` reads the theme while the view draws, so it must stay a modifier and not read it once when it is applied: the Settings window is built once and a color picked later has to reach it.
- A `contentShape` row with a gesture and a button inside is fine; two gestures on the same view are not.
- A row that opens on `.onTapGesture` alone is invisible to the keyboard and to Full Keyboard Access: make it a `Button` (`.buttonStyle(.plain)`).
- The window's size does not matter to a build that only compiles. **Open the app and look** at the state with a long value, a missing value, an error and the empty state.
- A bare `TimelineView(.animation)` or `.periodic` keeps drawing with the window minimized. In the window use `MovingTimeline` for a motion (30 frames a second at most) and `TickingTimeline` for a clock: both stop while nobody can see the window (`Viewing`). The Settings window, the dictation widget and the previews outside the window have no `Viewing` and keep a plain timeline.
