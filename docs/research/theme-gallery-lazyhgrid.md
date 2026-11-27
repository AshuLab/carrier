# Theme gallery: SwiftUI's horizontal grid

Whether `LazyHGrid` in a horizontal `ScrollView` gives the theme gallery its three fixed rows, the cut half column, the arrows and the scroll to the chosen cell without hand-made layout.
It is the first step of [more-themes-in-a-scrolling-gallery](../specs/more-themes-in-a-scrolling-gallery.md), tried in the real app (macOS 26, `--fixture`, 2026-11-26) with the made-up lists of the pieces gallery: nine, twelve and forty cells.

## What the grid gave

- **Three rows that fill column by column.**
  `LazyHGrid(rows: three flexible items)` places cell `n` in row `n % 3` of column `n / 3`, which is the order the keyboard function (`themeGalleryMove`) assumes.
  It is lazy, so forty or eighty cells cost what the visible columns cost.
- **Sideways scroll and the scroll to the chosen cell.**
  `ScrollPosition.scrollTo(id:)` with no anchor moves the least it takes for the cell to be whole, and does nothing when it already is; a cell cut at the right edge is brought in, and one cut at the left too.
- **The offset and the sizes**, from `onScrollGeometryChange` (the content offset, the content width and the viewport width), which is what the arrows need: an arrow is shown only while there is something to scroll to, and a page is three columns.

## What it did not give

- **The cut column.**
  The grid does not size its columns: a cell's width is whatever the cell takes.
  `containerRelativeFrame(.horizontal)` was tried for "a width that leaves half a column at the edge" and gave the wrong width on the first layout (it measured the window, not the scroll view), so the columns came out wider than the gallery and the cells overlapped.
  The viewport's own width, read with `onGeometryChange` on the scroll view, gives `(width - 3 gaps) / 3.5` and is stable; the half column is a consequence of that width and not something the grid does.
- **Its own height.**
  Flexible rows take what they are offered, and a view that offers little (a window that sizes itself to its content) shrinks them to their minimum of 10 points: the gallery was 50 points high.
  `fixedSize(horizontal: false, vertical: true)` on the scroll view makes the height the three cells' own (389 points with nine, twelve or forty cells).
- **Arrows, keyboard and the accessible group.**
  A scroll view has none of them.
  The arrows are two `IconButton`s over the edges calling `scrollTo(x:)`, the keys are `focusable()` and `onKeyPress` answered by the pure function, and the group is `accessibilityElement(children: .contain)` with a label.
  The system's focus ring around the whole gallery is turned off (`focusEffectDisabled()`): the chosen cell's edge is already what says where the keyboard is, because the keys choose as they go.

## What was chosen

The piece is built on `LazyHGrid` and `ScrollPosition`; the only hand-made parts are the column's width (from the viewport), the fixed height, the arrows and the keys.
Building it from a `LazyHStack` of columns was the alternative, but it would have needed the grid's column fill done by hand and a scroll target per column instead of per cell.
The piece's API is the same either way: the cells, the chosen one's id and an action.
