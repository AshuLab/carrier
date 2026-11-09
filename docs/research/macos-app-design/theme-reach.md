# Spike: how far a theme and an accent reach under Liquid Glass

Answers the open question of epic #677 ("Settings has a base and an App group") before the theme slice builds the gallery: the accent and the surfaces the app draws itself can be colored, but how the Liquid Glass buttons, the sidebar's selection, the sheets and the popovers take a color could not be shown in the HTML prototype. Issue #685.

## How it was tried

A SwiftUI prototype in [`../spike-theme-reach/`](../spike-theme-reach/), a SwiftPM package of its own outside `macos/Package.swift` (so nothing that ships builds it, and it is not part of the app). It is a window shaped like the app's (`NavigationSplitView` in an `NSHostingController` with `sceneBridgingOptions = .all` and `.fullSizeContentView`, as `WindowController.makeWindow`). The sidebar has a native `List(.sidebar)` with a selection and, under it, rows the app draws itself in the way `SidebarView` does today (`selectedContentBackgroundColor` for the selected one, `Color.accentColor` for a badge). The detail has every control the accent has to reach, and buttons that open a sheet and a popover. A pure `SpikeTheme` (Forest, with a light and a dark version of the window and the sidebar, and its own accent) feeds it; flags turn each knob (`--tint`, `--scheme`, `--scheme-api`, `--no-accent`, `--list-tint`, ...) and `--shot` saves the window as a PNG.

```
cd docs/research/spike-theme-reach
swift run SpikeThemeReach --theme forest --tint subtle      # a window to look at
./shots.sh                                                 # the screenshots below
```

Run on macOS 27 (build 26A428), Swift 6.4, Xcode SDK, a debug build of a bare executable (no `.app` bundle), with the Mac in dark mode and the system accent set to purple on purpose, so that anything that follows the system and not the theme shows as purple next to Forest's green. The screenshots are the window server's own composite (`CGWindowListCreateImage` of the app's own window, which needs no screen-recording permission), so the glass is in them.

Two roles of "accent" in SwiftUI turned out to be different things, which the rest depends on: `.tint(_)` (and the `.tint` shape style) is what controls read; `Color.accentColor` is the system's accent and is not changed by `.tint`.

## What reaches what

| Asked | What takes the color | What does not | The API that does it | Screenshot |
|---|---|---|---|---|
| **Accent on the glass buttons** | `.glassProminent` fills with the tint. A plain `.glass` button is neutral on the system's accent, but becomes a solid fill of the tint as soon as a `.tint` is set above it (every `.glass` button in the window, not only the prominent ones). Same for `.bordered` (text and a soft fill) and `.borderedProminent` (fill) | Nothing in a glass button can be colored apart from the tint: no separate fill, no stroke. Setting a `.tint` is all or nothing for the window | `.tint(accent)` once on the root view | [stock](theme-reach/stock.png) (system accent: Glass neutral) against [Forest](theme-reach/forest-light.png) (tinted: every glass button green) |
| **Accent on the sidebar's selection** | The rows the app draws itself (what `SidebarView` has today): a fill of `.tint` or of the theme's accent, selected text with `.foregroundStyle(.tint)` | The native `List(.sidebar)` selection pill stays on the system's accent, whatever was tried: `.tint` on the root and on the list, `.listItemTint(.fixed)`, `.accentColor(_)`, and a `.listRowBackground` (it is drawn under the pill and the pill stays purple). `selectedContentBackgroundColor`, which the app's own rows use now, is the system's accent too | Own row: `.background(RoundedRectangle(...).fill(theme.accent.opacity(...)))`, not `selectedContentBackgroundColor`. Native pill: none | [Forest](theme-reach/forest-light.png) (Home purple, Epic 3 green), [list-tint](theme-reach/list-tint.png) (everything tried on the list, pill still purple) |
| **Accent on switches and sliders** | Switch, checkbox, slider, segmented picker, progress bar, `.tint`-styled symbols and text | `Color.accentColor` (the star beside it with `.tint` is green, a `Color.accentColor` badge and the `Plain` button beside it stay purple); `.buttonStyle(.link)` links stay the system's blue | `.tint(accent)` on the root. `.accentColor(_)` does nothing on this system: [the window is as the stock one](theme-reach/accent-color-api.png) | [Forest](theme-reach/forest-light.png), [accent-color-api](theme-reach/accent-color-api.png) |
| **Accent on sheets** | A popover inherits the root's `.tint`: [switch, slider, buttons green](theme-reach/popover-light.png). A sheet gets the root's scheme (light on a dark Mac, with `.preferredColorScheme` or `NSApp.appearance`) | A sheet does **not** inherit `.tint`: it is another window and falls back to the system's accent ([purple switch, slider, prominent buttons](theme-reach/sheet-light.png)) | `.tint(accent)` again on the sheet's content (done once in a shared modifier that every sheet root uses): [sheet-tinted](theme-reach/sheet-tinted.png), [sheet-tinted-dark](theme-reach/sheet-tinted-dark.png) | as linked |
| **Accent on popovers** | As above: inherited | The popover's shape and arrow (not tried to recolor) | Nothing needed; `.presentationBackground(color)` also colors the popover: [popover-bg-dark](theme-reach/popover-bg-dark.png) | [popover-light](theme-reach/popover-light.png) |
| **Surface color of the window** | What the app paints under its content: `.background(theme.window)` on the detail. `NSWindow.backgroundColor` shows through whatever is left unpainted ([window-bg](theme-reach/window-bg.png)) | The title bar strip stays the system's (white in light, dark grey in dark), also with `ignoresSafeAreaEdges: .all` ([under-title](theme-reach/under-title.png)). The strip is the system chrome the spec already leaves out | `.background(color)` on the detail; `window.backgroundColor` for what is not painted | [Forest light](theme-reach/forest-light.png), [window-bg](theme-reach/window-bg.png), [under-title](theme-reach/under-title.png) |
| **Surface color of the sidebar** | `.background(theme.sidebar)` on the sidebar's content, with `.scrollContentBackground(.hidden)` for a `List` | In this window shape the sidebar is edge to edge and flat (with or without our color); I could not get the floating glass pane of Apple's apps here, so how a painted sidebar looks next to real floating glass is not shown (see the end) | `.background(color)` + `.scrollContentBackground(.hidden)` | [Forest light](theme-reach/forest-light.png) |
| **A tint over the windows** | An overlay of the accent at a low opacity over the window and the sidebar (0.06 subtle, 0.14 strong): [subtle](theme-reach/tint-subtle.png), [strong](theme-reach/tint-strong.png). The controls on top keep their colors, so the tint does not wash them | The title bar strip, the native selection pill, a sheet and a popover (other windows) get no tint unless each gets its own background | `.overlay(accent.opacity(x).allowsHitTesting(false))` on the painted surface (mixing the accent into the surface color in the theme value, so no layer is needed, was not tried) | [tint-subtle](theme-reach/tint-subtle.png), [tint-strong](theme-reach/tint-strong.png) |
| **A light and a dark version of one theme** | The theme picks its own window and sidebar color by the scheme; the accent is one value for both; controls, own rows and the surfaces follow. The scheme reaches the window, its sheet and its popover (`.preferredColorScheme` on the root, tried with light on a dark Mac) and all the windows of the app (`NSApp.appearance`, [sheet-light-nsapp](theme-reach/sheet-light-nsapp.png)) | The native pill, `Color.accentColor` and the links keep the system's colors in both | `.preferredColorScheme` for one window tree, `NSApp.appearance = NSAppearance(named:)` for every window (`nil` = system) | [forest-light](theme-reach/forest-light.png), [forest-dark](theme-reach/forest-dark.png) |

## What a theme can set in this app

The list the theme slice builds from.

1. **The color of the window**: one color for the light version and one for the dark, painted by the app under the content (and `NSWindow.backgroundColor` for what is left).
2. **The color of the sidebar**: one for each version.
3. **The accent** (the theme's own or one of seven): applied with `.tint(accent)` on the root of every window, and again on the root of every sheet (it does not carry into sheets; popovers inherit it). It colors the controls (switches, sliders, pickers, checkboxes, progress), the prominent buttons, and every `.glass` button, which turns from neutral to the accent's fill: decide once whether that is wanted; a theme cannot color only the prominent ones.
4. **The selection and the badges of the app's own views** (the sidebar rows, the cards): from the theme's accent read as `.tint` or passed in, never `Color.accentColor` and never `selectedContentBackgroundColor`, which are the system's. The app uses `Color.accentColor` in many places today (`WorkspaceSheet`, `BranchSheet`, `SessionsHomeView`, `SidebarView`...): the theme slice replaces them.
5. **The tint** (off, subtle, strong) as an opacity of the accent over the app's own surfaces of item 1 and 2: 0, 0.06 and 0.14 read well on Forest.
6. **The color scheme** (system, light, dark) with `NSApp.appearance`, which reaches every window of the app (the main window, the agent output window, sheets, popovers).
7. **The background of a sheet or a popover**, if the theme wants it colored: `.presentationBackground(color)` (the sheet does not take the window's color otherwise).

What a theme cannot set: the title bar strip, the toolbar, menus and the system's own chrome; the selection pill of a native `List(.sidebar)` (so the sidebar keeps being the app's own rows, or the pill stays on the system's accent); the color of links with `.link` (the system's blue, unless they are drawn by hand); a `.glass` button's color apart from the one tint; and the shape of a popover.

## Claims of the spec's Appearance section that have to change

Yes, two, small, and a line for a third:

- **Story 17, "the accent color colors the controls and the selection"**: true for the controls and for the selection in the app's own rows (the sidebar today). It is not true of a native `List` selection, which the app does not use in the sidebar, and it has to say that nothing the app draws with `Color.accentColor` follows the accent until the theme slice changes it. Suggested: "the accent colors the controls and the selection the app draws, in every window and sheet".
- **Story 17, "the tint colors the backgrounds"**: true for the backgrounds the app paints (window, sidebar). Not for the title bar strip, sheets and popovers unless each gets the background. Suggested: "the tint colors the windows' and the sidebar's backgrounds".
- **Story 16, "choosing a theme changes the colors of the windows and the sidebar"**: right as written, but the title bar strip stays the system's; the design section already leaves the system chrome out, so this only needs a line in the page's description of Appearance, not a change of the story.

Not changed: story 15 (the scheme sets the appearance of every window: `NSApp.appearance` does), story 18 (translucent windows: not tried here).

## What this did not cover

- **Reduce transparency and the translucent-windows switch** (story 18): the prototype's surfaces are all solid colors and the machine had Reduce transparency off. How a theme's colors look with the glass off, and the switch that picks solid or translucent surfaces, are for that slice.
- **The floating glass sidebar**: in this bare window (a debug executable with no `.app`) the sidebar does not float as in Apple's apps. How the theme's sidebar color sits on a real floating glass pane is for a person to look at in the running app, with the theme slice's first build.
- **Contrast**: only Forest's green and Carrier's blue were tried. White text on a light accent (yellow, say) is not checked; the seven accents need a contrast check in the theme slice.
- **Window shape**: the real window also has the right panel, the inspector and other sheets; the screenshots are of the spike's window only.
