# The sidebar names each epic by its title

Status: spec

## Problem

A row of the macOS app's sidebar says the repository's name and the issue number (`carrier #310`) and, under it, the state. The epic's title shows only on hover. With several epics of one repository the rows read `carrier #297`, `carrier #305`, `carrier #310`, and the only way to tell which is which is to hover each one or remember the numbers. The title is what identifies an epic and it is the one thing the row hides.

The sidebar also draws every stuck epic in orange, whatever the reason. A review limit waiting for a decision and an authentication failure look the same, although one asks for a choice and the other is an error.

## Solution

The first line of a row is the epic's title, truncated at the end, followed by `#issue` in the faint tone it has today, which never truncates. The second line has the state on the left and, on the right, the GitHub mark and the repository's name in the primary tone. The mark is `GitHubMark`, already in the app for the repositories list. The state keeps the rest of the line: the repository gives way first, takes at most about half of the line and ends in `…`. When the sidebar is grouped by repository the group header already says it, so the second line has the state alone. While the engine has no title for an epic the first line is the repository's name and `#issue`, as today, and the right side of the second line is left out so the name does not appear twice.

Hovering a row shows the full title and, under it, the repository's `owner/name`, so a truncated name of either can be read; a cancelled epic keeps the reason it already shows there.

The glyph and the state text of a stuck epic follow the attention colours of the glossary: orange when a person's input is needed, red when something failed. A stuck epic stays in the "Needs you" group either way. The classification is the `Attention` type that [the pipeline strip's epic](pipeline-strip-states.md) adds, so this epic is built after it.

What was cut. Keeping the repository and number on top and the title as a tooltip is today and is what hurts. Putting `repo #n` in the second line, faint, before the state lost: with the sidebar grouped by status the repository got lost in grey text. A capsule around the repository, and book, folder or branch icons, lost to the GitHub mark on the right: the capsule costs width the state needs when the name is long, and the GitHub mark says it is a GitHub repository with no explanation. Truncating the title in the middle was not considered, because the start of a title is the part that tells epics apart.

The exploration with every option, long repository names and a narrow sidebar is in `docs/research/macos-app-design/explorations/sidebar-rows-options.html`.

## Scope

1. As Diego, I see each row's epic title as its first line, so epics of the same repository can be told apart without hovering.
2. As Diego, I see the issue number right after the title, and it is never cut when the title is long.
3. As Diego, when the sidebar is grouped by status I see each row's repository on the right of its second line, with the GitHub mark, and the state on the left.
4. As Diego, when the repository's name is long it is cut with `…` before the state is, and I can read it whole by hovering.
5. As Diego, when the sidebar is grouped by repository I see the state alone on the second line.
6. As Diego, I see an epic with no title yet as the repository's name and `#issue`, with nothing repeated.
7. As Diego, I see a stuck epic waiting for my input with an orange glyph and orange state text, and a stuck epic that failed with a red glyph and red state text, both under "Needs you".

## Decisions

The model decides what each row says so the view stays a mapping, in `SidebarRow` (`macos/Sources/CarrierCore/Sidebar.swift`):

```swift
public struct SidebarRow: Equatable {
    public var repo: String
    public var issue: Int
    public var state: EpicMenuState
    /// The epic's title; nil while the engine has none, and the view then shows `name` in its place.
    public var title: String?
    /// The repository's name, never its owner.
    public var name: String
    /// Shown on the right of the second line; nil when the sidebar is grouped by repository or when `title` is nil.
    public var repoLabel: String?
    /// The stage and round or slices, the kind of intervention, "waiting for a slot" or how long ago.
    public var detail: String
    /// Only for a stuck epic: decides the colour of its glyph and of `detail`.
    public var attention: Attention?
    /// The full title, then `owner/name`, then the reason of a cancelled epic.
    public var tooltip: String
}
```

`attention` is `Attention(kind: epic.needsHumanKind)` for the rows of stuck epics and nil for the rest. It reaches the glyph as an optional parameter of `StateGlyph` that defaults to nil, so the other users of `StateGlyph` (the menu bar and the Overview) keep drawing every stuck epic in orange; `EpicMenuState` does not grow an error case, which would change them. The state's colour on the second line is read from the same field.

The truncation is a layout rule of the view, not of the model: title and `#issue` in one line with the number fixed, the repository with a maximum of about half of the second line and a lower shrink priority than the state. The repository gets the GitHub mark through the existing `GitHubMark`.

Testing seams. Stories 1 to 3, 5 to 7 go through the sidebar builder in `macos/Tests/CarrierCoreTests/SidebarTests.swift`, the seam that already pins the rows: `title`, `repoLabel` for both groupings and for a missing title, `tooltip`, and `attention` for a review limit, an agent asking for help, a timeout and an unknown kind. Stories 2 and 4 are layout and have no automated test: the number never cut and the repository giving way first are checked by Diego with a long title, a long repository name and the sidebar at its narrowest, in light and dark, with the exploration page open beside it.

## Out of scope

The grouping of the sidebar and its toggle, the Overview, and the Ready, Done and Cancelled rows beyond the layout change (a cancelled epic stays grey). Applying the attention colours to the rest of the app (the toolbar pill, the menu bar, the Overview, the tab counts, the repositories chips). The pipeline strip, which has its own epic. Showing the pull request number.
