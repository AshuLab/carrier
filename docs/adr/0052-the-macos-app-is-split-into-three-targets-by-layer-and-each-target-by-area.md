# 0052 - The macOS app is split into three targets by layer, and each target by area

- Status: proposed
- Date: 2026-11-24

## Context

`macos/Sources` has two targets: `CarrierCore` (193 files, about 30,500 lines, Foundation only) and `Carrier` (170 files, about 33,000 lines, SwiftUI and AppKit).
The split by layer already holds: `CarrierCore` imports no SwiftUI or AppKit, and it already keeps what a view shows as pure, tested functions (`agentsPage(config:)`, `sliceCard(lane:)`, `findingsCard(_:stage:round:)`).
Inside each target nothing is grouped: both are one flat folder.
In `Carrier`, 101 files are views, 23 bridge to AppKit, 7 mix a view and a model, and the rest are models, services and helpers, side by side.
The pieces the rest of the app reuses live inside the screens that first needed them: `SettingsTabs.swift` (1,494 lines) holds five pages and about 25 pieces that 40 files use (`SelectMenu`, `SegmentedChoice`, `FilterChip`, `SettingsGroup`, `NavigationRow`); `BehaviorTab.swift` holds `PrimaryCapsuleButtonStyle` and `NumberField`, used by 33 files; `SidebarView.swift` holds `IconButton` and `ChoiceMenu`.
Some views reach the machine themselves: `StartController` starts processes, `ModelPicker` runs one, and `ProjectsTab`, `WatchingTab` and `AgentsTab` read or write files.
A web front-end is planned, and it has to reproduce the app's areas, pieces and rules; today it would have to dig them out of screens.

## Decision

The app has three targets, and a dependency only points down: `Carrier` -> (`CarrierUI`, `CarrierCore`), `CarrierUI` -> `CarrierCore` (for the design tokens only), `CarrierCore` -> Foundation.

- `CarrierCore` is the logic, with no SwiftUI or AppKit, as today: the socket clients, the models, the rules, what each view shows as pure functions, the protocols a platform implements, the design tokens as values, and helpers with no domain.
- `CarrierUI` (new) is the pieces of [`docs/ui.md`](../ui.md) and the SwiftUI side of the tokens. A piece takes values and actions; it knows no session, epic, project or socket. Being its own target, the compiler refuses a piece that reaches into an area.
- `Carrier` is the app: its composition root (`App/`), one folder per app area (`Features/<Area>/`), and the platform adapters (`Platform/`), the only code that calls Ghostty, the recognizers, IOKit, Carbon, UserNotifications, Sparkle or the clipboard.

Inside each target, files are grouped by app area, the same areas as `docs/macos/`, and the tests mirror the tree of the sources.
A view does not start a process and does not read or write a file: it asks a model in `CarrierCore` or an adapter in `Platform/`.

`CarrierUI` starts as a folder, `Carrier/UI/`, while the pieces are taken out of the screens and cleaned, and becomes its own target in the last step, once no piece reads the app's state; from then on the compiler keeps the boundary, and until then a check in CI fails when a file under `UI/` names a type declared outside `UI/`, `CarrierCore/Theme` and `CarrierCore/Copy`.

A piece follows these rules, which [`docs/ui.md`](../ui.md) carries with an example each:

1. It is presentational: it takes values and actions (closures), and never reads a store, a singleton, a file or a socket, nor knows a session, an epic or a project.
2. It keeps only passing visual state (hover, pressed, focus, an animation); what a person chooses lives in a model.
3. Its look comes only from design tokens; the theme, the text size and the accent reach it through SwiftUI's `Environment`, set once at the root, never through a shared instance such as `AppTheme`, `TextSize` or `ProviderIdentityStore`.
4. Its API is small: an enum for its variants rather than a set of `Bool`s, a `@ViewBuilder` slot for content rather than many parameters, and a `ButtonStyle` or `ViewModifier` over the system's control where one fits, so keyboard and accessibility come with it.
5. Its states (normal, hover, pressed, disabled, loading, error, empty) are listed in its catalog entry and drawn in the gallery under `--fixture`.
6. Its accessibility is part of it: a label from a copy key, the text size, contrast and keyboard focus.
7. What it shows that is more than layout comes from a pure function in `CarrierCore`, and that function is what is tested.
8. It has one file, one catalog entry and the name it will have in every front-end (`NoticeCard(kind:title:actions:)` in Swift is `<NoticeCard kind title actions />` on the web).
9. It moves to `UI/` when a second area needs it; a piece used by one area stays in that area.

```
macos/Sources/
  CarrierCore/  Connection/ Lifecycle/ Sessions/ Chat/ Epics/ Terminal/ Dictation/ Projects/ Usage/ Settings/ Health/ Platform/ Theme/ Support/
  CarrierUI/    Tokens/ Buttons/ Fields/ Selects/ Rows/ Cards/ Chips/ Meters/ Feedback/ Layout/ Modifiers/ Icons/
  Carrier/      App/ Features/<Area>/ Platform/
```

## Alternatives considered

Leave the app as it is and let the web front-end be born organized, reading the app's code and docs as reference.
It moves nothing that works, but every piece, rule and word would then be decided twice and drift apart, and the app keeps its 1,500-line files and its pieces hidden in screens.

Folders only, no new target.
It is a pure move, but nothing stops a piece from importing an area again, and the rule decays; a check in CI holds it, but a module of its own is what a design system is everywhere else (`packages/ui` on the web, a design system module in a Swift app), and its `public` API is the piece's documented contract.

`CarrierUI` as a target from the first step.
A prototype on 2026-11-24 moved 16 pieces into a real target: the build took the same time either way (a clean build 21-24 s, touching a piece about 1.8 s), but the 16 pieces dragged 11 more files with them, needed 174 `public` and 27 hand-written initializers, and made the app's shared instances (`AppTheme`, `TextSize`, `IconAppearance`, `ProviderIdentityStore`) public API, because the pieces read them.
The cost was the pieces breaking rules 1 and 3, not the target; cleaning them first leaves the target with only the pieces' own API to make public.

A target per area (a package per feature).
It enforces more, but it multiplies `public` and the build graph for an app of one team, and the areas share most of `CarrierCore`.

## Consequences

Everything `CarrierUI` exposes becomes `public` in the last step, with hand-written initializers, about four `public` per piece once the pieces are clean.
The move touches every file of the app at once, so it lands while no other change to the app is open (the spec says how).
A web front-end copies the same layers: `CarrierCore` maps to a core package, `CarrierUI` to a package of pieces, `Features/` to its areas and `Platform/` to its adapters.
