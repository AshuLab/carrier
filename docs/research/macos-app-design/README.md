# macOS app design (HTML mockups)

The visual design of the Carrier macOS app, as clickable HTML with fake data. Open `diseno.html` in a browser (it needs `shared.css` next to it). It is the source of truth for how the window looks; the SwiftUI app should be built to match it.

`diseno.html` is the final state of the design. It shows, in one page: the window (left sidebar, centre, right panel) with every view reachable by clicking, the menu bar item and its menu, the About sheet (click About in the sidebar) and a gallery of empty states. The toggle at the top switches light and dark.

`explorations/` holds the option pages that led to it, one per question (sidebar, overview, centre, files, review, slices, details, output, settings, about). Each shows several alternatives side by side with a situation switcher. They are history: read them to see what was tried and why something was dropped, not to build from.

## What is deliberately not final

The icons are placeholders (letters in tiles for file types, simple glyphs elsewhere); a proper icon set comes later. All data is invented. Several things the mockup shows are not in the engine's snapshot yet; the list is in the epic that implements this design.

## Rules the design follows

Colour carries meaning only: green and moving is running, orange is needs you, red is an error or a problem, blue is ready for test or the live accent, grey is waiting. Done steps in the pipeline and review are green. Everything else is neutral. Text that can be long truncates with an ellipsis and never hides the `#number`. Data the engine does not have yet shows an empty state instead of nothing.
