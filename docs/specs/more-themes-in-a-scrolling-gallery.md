# More themes in a scrolling gallery

Status: spec

## Problem

The Mac app has nine themes, and the person who uses it wants more: the well-known palettes they already have in their editor and terminal.
The catalog is meant to keep growing with no fixed number, so adding themes must stay cheap for the page that shows them.
Today it is not: the Theme group of Settings, Appearance is a grid of three columns where every theme is a cell about 130 points tall, so each three themes add a row.
Nine themes are three rows; twelve are four; twenty would be seven, and the person scrolls past all of them to reach the colour scheme, the text size and the accent.
We know because the page was already felt to be long with nine, and the three themes added in the working tree (Solarized, Nord, Gruvbox) made it longer.
The terminal has the same need on its own page, where the theme is chosen from a pop-up of names alone.

## Solution

Two changes that do not depend on each other: a gallery that does not grow the page, and a bigger catalog.

**The gallery is three rows high and the rest of the themes go sideways.**
The cells stay exactly as they are today (a light and a dark preview side by side at the same size, the name under them, the chosen one with the accent's edge), laid out in three fixed rows that fill column by column, and the gallery scrolls horizontally.
The page is the same height with twelve themes or eighty: about 400 points, the height of the three rows of today.
Three things make the hidden part findable and reachable: half a column is cut at the right edge so it is clear there is more, arrows at both sides (hidden at the ends) for a mouse without a horizontal scroll, and choosing a theme with the keyboard scrolls the gallery until the chosen cell is in view.
With the keyboard, up and down move one theme inside a column and left and right move one column, choosing as they go.
It is one piece in `CarrierUI` that takes the themes, the chosen one and an action and reads nothing else, with its catalog entry in `docs/ui.md` and its place in the gallery of pieces, per the rules of a piece.

**The terminal uses the same gallery.**
The pop-up of names is replaced by the same piece, so the app has one way to choose a theme.
The terminal's "Same as the app" choice is the first cell of its gallery: it draws the app's current theme with that label, and it is the chosen one until another is picked, so the terminal follows the app's theme while it is.

**The catalog is the twelve themes we have plus the best known palettes.**
Dracula, Tokyo Night, Catppuccin, One Dark, Monokai, Rosé Pine, Everforest and Ayu, on top of Carrier, Graphite, Ocean, Forest, Sunset, Paper, Rose, Lavender, Midnight, Solarized, Nord and Gruvbox, in that order.
Every theme has a light and a dark version, because the colour scheme picks one.
Dracula's light version is Alucard, which its organization publishes; Monokai has no official light version, so we invent it, keeping its hues and its feeling, and its docs say it is inspired by the original and not the original.
A theme is its window, sidebar and accent in both versions (`design/tokens.json`), its name in both languages, its place in the two preference lists, its 16-colour terminal palette in both versions (from the palette's own ANSI colours, nudged where the contrast test needs it) and its row in the tests and the docs.

The window, sidebar and accent of the eight new themes, taken from each palette's own repository or site and settled with a prototype (window · sidebar · accent):

| Theme | Light | Dark | Source |
|---|---|---|---|
| Dracula | #fffbeb · #dedccf · #644ac9 | #282a36 · #21222c · #bd93f9 | Dracula and Alucard, both published by the organization; the light sidebar is by role parity, the spec gives none |
| Tokyo Night | #e1e2e7 · #d0d5e3 · #2e7de9 | #1a1b26 · #16161e · #7aa2f7 | Night and Day of folke/tokyonight.nvim |
| Catppuccin | #eff1f5 · #e6e9ef · #8839ef | #1e1e2e · #181825 · #cba6f7 | Latte and Mocha of catppuccin/palette |
| One Dark | #fafafa · #eaeaeb · #4078f2 | #282c34 · #21252b · #61afef | One Light and One Dark of atom/one-*-syntax; the sidebars come from the repositories' formula |
| Monokai | #f9f8f1 · #ebe9dc · #62890a | #272822 · #1e1f1c · #a6e22e | dark is Monokai as VS Code ships it; the light is invented |
| Rosé Pine | #faf4ed · #f2e9e1 · #d7827e | #191724 · #1f1d2e · #ebbcba | Dawn and Main of rose-pine/palette; the sidebar is the overlay in light and the surface in dark |
| Everforest | #fffbef · #f2efdf · #8da101 | #2d353b · #232a2e · #a7c080 | light hard and dark medium of sainnhe/everforest |
| Ayu | #fcfcfc · #f8f9fa · #f29718 | #242936 · #1f2430 · #ffcc66 | Light and Mirage of ayu-theme/ayu-colors, current versions |

Themes arrive in batches of three or four, one change each, so every batch is looked at in the app, in both versions, before the next.
The first batch is the three already in the working tree (Solarized, Nord, Gruvbox).

**What lost and why.**
A compact row with the current theme and a "Change…" button that opens a sheet with the whole gallery: it scales best, but the person wants every preview in the page, as today, without a click.
One horizontal row of previews: it also keeps the page's height, but it shows far fewer themes at a time than three rows.
A grid with a fixed height and its own vertical scroll: a scroll inside a scroll, which is awkward to use.
Six themes and a "Show all" button: the page is long again as soon as it is open.
A smaller preview to make the gallery shorter: the person kept today's size.
A pop-up for the terminal only (what it has now): it works at any size, but the two places would choose a theme in two ways.
Originals of Carrier's own (Sand, Mint, Slate…): left for later; the well-known ones were asked for first.

Two throwaway HTML prototypes settled it: one compared five layouts, and the second drew the chosen one with the twenty real themes, the terminal page and the keyboard; the person approved it.

## Scope

1. In Settings, Appearance, the themes are shown in three rows of cells of today's size, and the rest are reached by scrolling sideways.
2. The page's height does not change when a theme is added.
3. Half a column is cut at the right edge while there are themes beyond it; at the end of the scroll the last column is whole.
4. An arrow at each side scrolls the gallery by about a page of columns, and an arrow that cannot scroll further is hidden.
5. Choosing a theme with the keyboard (up and down inside a column, left and right between columns) scrolls the gallery until its cell is fully in view.
6. The chosen theme has the accent's edge, in both color schemes, and is read by VoiceOver as the selected one of the group.
7. In Settings, Terminal, the theme is chosen in the same gallery, and its first cell is "Same as the app", drawn with the app's current theme; it is the chosen one until another is picked, and picking it again goes back to following the app.
8. The catalog has the twenty themes above, each with a light and a dark version that the colour scheme picks, a name in English and in Spanish, and a place in both preference lists.
9. Each theme has its terminal palette in both versions, readable against its own window with the contrast the other themes meet.
10. The docs say Monokai's light version is inspired by the original, and which source each theme's colours come from.

## Decisions

**Seams.**
What the gallery shows beyond layout comes from a pure function in `CarrierCore/Theme`, tested in `CarrierCoreTests/Theme`, and the view draws the result (rule 7 of a piece):

- The terminal's cells: given the app's theme and the stored terminal theme (nil is "same as the app"), the list of cells in order, the first being the app's with its label, and which one is chosen. Covers stories 7 and 8 through the same interface the view calls.
- Keyboard movement: given the cell chosen, the key and the count, the cell to go to, one inside a column and one column at a time, stopping at the ends. Covers story 5's rules; the scrolling itself is the view's.
- The themes: the tests that already exist are the seam, extended by one row per theme. `ThemeTests` pins each theme's window, sidebar and accent in both versions and the count; the contrast test of `TerminalCoreTests` covers the palette of story 9; the Spanish title test and `pnpm design:check` with `design/generate.test.ts` cover the names and the preference lists.

Stories 1 to 4 and 6 have no unit test: where a column is cut, the arrows and the scroll are layout, and a test of them would only repeat the view. They are checked in the app as `docs/ui.md` asks (the Pieces session of `--fixture`, both schemes, `--smoke-window` for the widths), and the piece needs its `GalleryEntry` or `check-structure.sh` fails.
Story 10 is a docs change checked by reading.

**The first slice is a small SwiftUI prototype in the real app** of the three-row horizontal grid (`LazyHGrid` in a scroll view): the cut column, the arrows and scrolling to the chosen cell.
If it does it without hand-made layout, the piece is built on it; if not, the piece is built with the layout it needs and the decision is recorded.
Either way the piece's API stays the same (the themes, the chosen one, an action).

**The cell's size is today's** (the preview 84 points high); the column's width is set so that at the Settings window's usual width three columns fit and half of the next one shows.

**The terminal's stored value does not change:** the terminal theme stays optional in `design/preferences.json`, nil meaning the app's.
There is no migration: the choice of a theme is the same value, only the control that sets it changes.

**Order of work:** the first batch of themes and the prototype can go in parallel; the piece in Appearance follows the prototype; the terminal's gallery follows the piece; the other batches follow the first, and need the piece only to be seen, not to work.

## Out of scope

A theme editor, importing and exporting themes, and mixing one theme's window with another's accent: the accent is already its own choice, and a theme the person builds is the lot of work the Settings spec cut on purpose.
Themes of Carrier's own design.
Search or filters in the gallery: with twenty themes the sideways scroll is enough; they come back if the catalog grows well past that.
A theme that paints more than the window, the sidebar and the accent (`docs/research/macos-app-design/theme-reach.md` says how far a theme reaches).
Changing the accent presets, the tint or translucent windows.

## Open questions

Whether SwiftUI's horizontal grid gives the cut column, the arrows and scrolling to the chosen cell without hand-made layout: the first slice answers it by trying, and nothing else in this spec depends on the answer.
