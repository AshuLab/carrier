# The look of the macOS app

How the pieces of `Carrier.app` are drawn, so that a new screen or a change reuses what is there and looks like the rest. It was written down while polishing Settings (Providers and Repos first); the pieces live in `macos/Sources/Carrier`. **Before adding a button, a field, a select, a row or a line, look here, then at the file named, and reuse it. Do not draw a new one, and do not use the system's plain control where a piece below exists.** When a piece is missing, add it next to the others and add it here.

Nothing here is checked by a test: a view is looked at in the app (`macos/build-app.sh --open`, see [the app's README](../macos/README.md#build-and-open)), not only compiled.

## The page

A Settings page is a header and groups of rows (`SettingsSheet.swift`, `SettingsTabs.swift`).

| Piece | What it is |
|---|---|
| `SettingsPageHeader` | The page's tile (38 pt, the theme's accent at 16 %), its name and its line, at the top of the scroll under `safeAreaBar`. |
| `SettingsGroup(title:)` | A small uppercase title over a card. |
| `SettingsTabCard` | The card: 14 pt side padding, rounded 14, `secondary` at 7 %. |
| `SettingsTabRow` | A row of a card: title, detail (and `note`, a quiet monospaced third line), the control at the right. `first: true` on the first row (no line above it). `roomy: true` for a form with many stacked fields (14 pt above and below instead of 10). |
| `.settingsCard()` | The card's background as a modifier (rounded 14, `secondary` at 7 %), for a list, a note or a card that is not a group of rows. Never write the fill out again. |
| `.sectionLabel()` | The type and colour of the small uppercase title (`caption2`, semibold, `secondary`, upper case by `textCase`), for a title that cannot be a `SettingsGroup` (a list's label, the owners of a picker). The caller adds the padding its place needs; write the text as a normal sentence, not in capitals. |
| `SettingsDivider` | The line between two rows: 1 pt, `primary` at 7 %. |
| `EmptyStateView` | Icon, title and one line, centred. For nothing to show: not installed, not running, no model. Give it `.frame(minHeight: 260)` inside a page. `LoadingStateView` is its twin while something loads. |
| `SettingsPreview` | A sample of what the rows around it change, inside their group. |

Spacing: **14 between blocks, 4 inside a block** (a name and its version), 12 between a tile and its text. The close button of the sheet is an `IconButton` (`xmark`) at the top right of the header; there is no footer, and Esc closes.

## Lines

Always `SettingsDivider`, never `Divider()`: the system's is a grey hairline that stands out on the dark themes. It is one whole point on purpose; **a half-point line over a translucent fill is drawn uneven on a Retina screen, so do not use `lineWidth: 0.5`.** Put the line in the row's `.overlay(alignment: .top)` and **put extra padding inside the row, never outside it**, or the line stops being halfway between two rows.

## Buttons

Four kinds. Pick by what the button is, not by taste.

| Kind | Style | For | Where |
|---|---|---|---|
| Main | `PrimaryCapsuleButtonStyle` | The one action of a form: Save, Add. Accent fill, white label; dim when disabled. | `BehaviorTab.swift` |
| Secondary | `SecondaryCapsuleButtonStyle` | Cancel, Remove, Open Agents, Add account, Sign in. A grey capsule; `.controlSize(.small)` inside a row. | `BehaviorTab.swift` |
| Text | `HoverTextButtonStyle(tint: nil)` | Actions of a page header (Update, Check again, Open on GitHub) and the chevron. No pill until the pointer is over it. | `NoticeCard.swift` |
| Icon | `IconButton` (`HoverFillButtonStyle`) | A 24 pt glyph with a tooltip and an accessible name: close, fold. | `SidebarView.swift` |

- **A button that does something has an icon** with its words: `Label("Save", systemImage: "checkmark")`. Used: Save `checkmark`, Cancel `xmark`, Remove `trash`, Add `plus`, Check again `arrow.clockwise`, Open on GitHub `arrow.up.right.square`, Reveal clone `folder`. Outside a `Menu` give the label `.labelStyle(.titleAndIcon)` when it sits in a text or icon style.
- A form's buttons sit in a row: Remove on the left, then a `Spacer`, then Cancel and Save, with 10 pt more above than the fields have between them.
- Destructive is `role: .destructive`; a plain capsule does not turn red by itself. When a screen has one destructive action, say so with colour (`HoverTextButtonStyle(danger: true)` turns red under the pointer).
- Do not use the system's bordered, borderless or `.glass` buttons in Settings. (`EmptyStateView` uses `.glass` for its one button; leave it.)

## Rows that open something

A row that opens an editor or a form shows **a chevron `chevron.right` at its right and is clickable all over**:

- The chevron is a `Button` in `HoverTextButtonStyle(tint: nil)` with `.accessibilityLabel("Edit …")` and a `.help`; it is dimmed (`.disabled`) while that row is the one open.
- The row has `.contentShape(Rectangle()).onTapGesture { … }` (guard it so a second click on the open row does nothing). A button inside the row (Sign in, Reset, Use in an agent…) keeps its own click: a `Button` takes the click before the row's gesture.
- When the row opens a form below it, the chevron **sits in a fixed 26 × 26 slot and turns 90°** (`rotationEffect`); it must not move or resize. (`ReposTab.swift`, `roleRow`.)

## Fields and selects

- **A text field is `TextField(…).settingsField(width:)`** (`SettingsTabs.swift`): a quiet fill with rounded corners of 8, no line while idle, the theme's accent as a 1.5 pt ring while it has the focus, and a click anywhere in the box puts the cursor in it. `width: 240` for a short value, no width to fill the space given (a multi-line field too). Do not use `.textFieldStyle(.roundedBorder)` in a form.
- A search field is the same field with `icon: "magnifyingglass"` (`settingsField(icon:)` draws the symbol inside the box) and a prompt that says what it searches ("Search repos").
- A field that saves as the person leaves it (Agents) passes its own focus: `settingsField(width:focused: $focused)`, so the ring and the save follow the same state.
- **Filters are `FilterChip`s** (`SettingsTabs.swift`): small capsules that are on (the theme's accent) or off (a quiet fill), in a row under the search. Chips that exclude each other start with "All" and a second click on the one that is on goes back to it; an on/off filter ("Hide watched") is a chip of its own at the right of the row; a filter with many values (the owner) is a `NativePopUp`. The filtering is a pure function in `CarrierCore` with a test (`repoGroups`), not logic in the view.
- **A choice among a few words is `NativePopUp`** (`SettingsTabs.swift`), the Mac's own pop-up, neutral; SwiftUI's menu `Picker` takes the accent for its fill and reads as a main action. For a value (an enum, a stored string) use `ChoicePopUp(label:options:selection:)`, which wraps it: the choices are `(value, title)` pairs and the binding is the value itself. Do not use SwiftUI's `Picker` with the menu style in Settings; the pages that still do are to be moved. Give it `.frame(width: 160)` in a row, or let it fill in a form grid. The first item is "Use default" (the empty value, nothing written) or "Same as everywhere (value)" when it inherits. A value already stored that is no longer on the list stays on it, so opening the editor never changes it.
- A text of several lines (an instruction, a prompt) takes the width of the card: `SettingsStackedRow` puts the title and the detail on top and the control under them, and the box is a `TextEditor` in `settingsField()`. Turn the system's writing tools off on it (`.writingToolsBehavior(.disabled)`), or its "Write with Siri" button sits on the box.
- A box of several lines in a row (`TextEditor`, "Launch arguments"): `scrollContentBackground(.hidden)`, 4 pt padding, the same fill, and **the size goes last, around the padding**, so the row grows with it.
- Turn off the system's writing tools on a form of paths and arguments: `.writingToolsBehavior(.disabled)`.

## Lists and menus

- A list of things to choose from (the Providers tools, the repos) is a card with rows of 8 pt side and 6 pt top padding, a rounded 9 fill for the chosen one (`secondary` at 18 %), and a dot or a mark at the right for its state. A last row of the same shape, with a dashed tile and a plus, adds one (`AddRepoRow`).
- A tile for a thing is its mark in a rounded square: the project's `ProjectIcon` (32 pt, radius 9, a colour made from the name) for a repo, `ProviderMark(name:)` for a provider (its bundled icon in the text colour; `accountIcons` in `RepoRoleSave.swift` gives each account its provider's icon).
- **An agent role (Author, Reviewer, Lead reviewer) is drawn with `RoleTile`** (the provider's mark in a 34 pt tile, a power symbol when the role is off) and its settings with `roleSummary` (`Identity gh · Account pro · Model sonnet · Effort high`, the label quiet and the value in the text colour). In a list that is narrow, the model and the effort go on the first line in the text colour and the account and the identity under it. The mark follows the account's harness (`accountIcons`).
- **The model of a role (or of a failover step) is chosen with `ModelPickerButton`** (`ModelPicker.swift`), never typed: a pill with the provider's mark, the model and the reasoning that opens the chat's panel (the providers that can work as tabs, a search, the models, the `ScaleRow` slider for reasoning). Its choices are `ModelPick` values, and the logic of what it lists (`pickerAccounts`, `modelOptions`, `effortSteps`) is in `CarrierCore/ModelPicker.swift` with tests. A role runs on its own, so the panel shows its access as full, not as a choice. The Repos page uses the same picker for a repo's own roles, with `inherited:` (the first row of the list, and of the slider, is "Same as everywhere", and the pill says what that is) and `fill: true` (the pill takes the width of the form).
- **A menu's items have an icon, and a `Label` in a `Menu` or a `contextMenu` needs `.labelStyle(.titleAndIcon)` to show it**; this SwiftUI draws a menu's labels title only otherwise.
- Small facts of a status card (`fact` in `ReposTab.swift`): a label of 84 pt in `secondary` and the value; **every row is at least 40 pt**, taller than any chip, so a row with a badge and one without are the same height.
- A state is shown by a green, orange or grey dot, or by `StatusMark` (`SettingsTabs.swift`, a 16 pt round mark: `checkmark` green, `exclamationmark` yellow, `xmark` orange), at the right of a row that has no button or before one. While something runs, **each row turns its own `ProgressView` and says "Checking…"**; the page does not say it once in a corner.

## A value that is not valid

Orange, not red, and nothing moves. This is the default of every row and field: pass the message once, `SettingsTabRow(…, problem: "what is wrong")`, and the row puts it in the place of its detail line, in orange with a warning mark (the title keeps its colour), while every `settingsField` and `NumberField` inside it draws an orange ring and a warning mark in the box, the same size as without them (the row tells them through `\.settingsInvalid`). A new field needs nothing for it; do not pass a flag to the field, and do not colour a whole row red. A message that has no row of its own (a refused save) is a `ProblemLine`, never a bare orange `Label` or `Text`: only `ProblemLine` is read aloud.

## What the engine answers to a save

A page that writes `config.json` or `providers.json` does not wait for Carrier: it writes, asks the engine in the background (`ReloadStatus.ask`, in `CarrierCore/EngineReload.swift`) and shows the answer when it comes; an answer older than the last save is dropped. A refusal or a missing answer is a problem and is orange: `ProblemLine` (`SettingsTabs.swift`) is the line with the warning mark that VoiceOver reads when it appears, and `ReloadNote` is the page's line for the last answer, with "Ask Carrier again" to ask without saving (the Behavior header offers it too; the doctor's "Check again" is another button). A running Carrier that is too old to reload is told quietly, in the secondary colour and with no announcement, because it is a normal state after an update. A page that is a header note (`SettingsHeaderNoteKey`) wraps it under the title when it does not fit beside it (`ViewThatFits`). The last answer lives in `ReloadStatus.shared`, not in the page's `@State`, so it is still there when the person comes back to the page, and it goes when Carrier starts or stops.

## Text

- Titles `fontWeight(.medium)`, details `.caption` in `secondary`, a path or a command `.scaled(11, design: .monospaced)`. Use `Font.scaled` (`ScaledFont.swift`), not a fixed size, so the person's text size applies.
- Do not put copy-on-hover (`copyOnHover`) on text that says nothing to copy ("Not checked yet", "Checking…"); keep it on a path, a reason and a fix.
- Texts are English, short, and say what the control does, not how it works.

## Mistakes seen

- A `Spacer` inside a view that sits in `safeAreaBar` (the page header) takes all the height the bar offers: the header filled the window. Size such a view by what it holds.
- `frame` before `padding` and `background` lets a `TextEditor` spill over the row above it. Size last.
- A page-wide `.buttonStyle(…)` reaches inside menus and forms; a control that must differ sets its own style.
- A `contentShape` row with a gesture and a button inside is fine; two gestures on the same view are not.
- The window's size does not matter to a build that only compiles. **Open the app and look** at the state with a long value, a missing value, an error and the empty state.
