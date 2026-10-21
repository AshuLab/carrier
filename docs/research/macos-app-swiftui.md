# Building the macOS app design in SwiftUI on macOS 26 and later

> Research of 2026-10-21 for the design in [macos-app-design/diseno.html](macos-app-design/diseno.html) and the [macOS app brief](../specs/macos-app.md). Read-only on the repo: nothing under `macos/` or `assets/` was touched. Everything ran on this Mac (macOS 27.0, Xcode toolchain with the macOS 27.0 SDK, Apple Swift 6.4, `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`, Command Line Tools 27.0 also installed) in a throwaway SwiftPM package at `/Users/vemec/.claude-ashu-lab/jobs/67f3fde8/tmp/swift-feasibility/` (not in the repo; the PNGs it rendered are in its `out/`). The SDK's `.swiftinterface` files (`SwiftUI.framework`, `SwiftUICore.framework`, `Charts.framework`) are the source for "this API exists"; Apple pages were read through `developer.apple.com/tutorials/data/documentation/...json`. The machine has a display and a login session, so some tests opened small windows for a few seconds. It has no Screen Recording permission, so no real screenshot of a window could be taken (see question 11).

## Short answer

**Architecture.** Keep the AppKit lifecycle, the `NSStatusItem` icon and the plain `NSMenu`. Replace the body of the existing window with one SwiftUI root: a `NavigationSplitView` whose sidebar is a `List` with `.listStyle(.sidebar)` and whose detail carries `.inspector(isPresented:)` for the right panel, hosted in the same `NSHostingController` with `sceneBridgingOptions = .all` and a `.fullSizeContentView` window. In the probe this produced, with no custom drawing, a floating Liquid Glass sidebar and inspector (`NSGlassEffectView` for each) and a toolbar of glass items. The centre is a `ScrollView` + `LazyVStack` with the pipeline strip as `.safeAreaBar(edge: .top)` (the system builds a `NSScrollPocket` there: content scrolls behind, blurred). Cards that hold content use plain fills and materials, glass is kept for buttons and the few floating pills. Settings and About become sidebar destinations of the same split view. One `@Observable` model, fed by the existing `ControlMonitor` thread, is the only data source; view state (selection, inspector tab, group-by) stays in `@State`/`@AppStorage` of the views.

**The three riskiest things.**

1. **Toolchain.** In the macOS 27 SDK `@State` is a macro (`public macro State()` in `SwiftUI.swiftinterface`) whose plugin ships only with Xcode. The committed `PanelView.swift` already uses `@State`, and with `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build` it fails: `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`. `macos/README.md` says the Command Line Tools are enough; on this machine that is no longer true for the default SDK. It builds under the CLT only with `--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`; it builds and tests under Xcode's toolchain (108 tests pass in the repo copy). Decide which one the project promises before building more views.
2. **Animation cost.** SwiftUI's `repeatForever` ring cost about 9% to 12% of a core for eight small rings in a release build, and kept costing the same after the window was hidden with `orderOut`. A Core Animation ring cost 0%. Gating on the window's occlusion state fixed the hidden case (0%). WindowServer's share could not be measured here (it idles at 40% to 55% because of the user's displays, bigger than the signal).
3. **Not being able to look.** Liquid Glass, the scroll edge blur and the sidebar toggle cannot be verified without a real screenshot, and none could be taken. `ImageRenderer` works headless but draws a "prohibited" placeholder for `List`, `NavigationSplitView`, segmented pickers and the glass buttons. So the design match for the window as a whole needs a person (or a Screen Recording permission) at least once. Also: the default sidebar toggle button did not appear in the AppKit-hosted window (question 1).

## 1. Window and sidebar

**`NavigationSplitView` in an `NSHostingController` works and gives the glass.** Probe: `NSWindow(contentViewController: NSHostingController(rootView: RootShell()))` with `sceneBridgingOptions = .all`, style mask `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, content 1100x700 (the repo's `WindowController.makeWindow()` already does this). A walk of the view tree after two seconds gave `NSSplitView` > `_NSSplitViewItemViewWrapper` > `NSGlassEffectView` for the 268 pt sidebar and for the 316 pt inspector, an `NSScrollPocket` per column at the top, and an `NSTitlebarContainerView` 52 pt high with an `NSToolbarView` holding the title and a glass platter per toolbar item. So the "floating" sidebar and inspector are system-provided; there is nothing to draw. Apple's guidance says the same: "Liquid Glass applies to the topmost layer of the interface, where you define your navigation" and split views "are optimized to create a consistent and familiar experience for sidebar and inspector layouts" ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). Do not put your own `.background` on the sidebar or inspector: Apple says custom backgrounds "might overlay or interfere with Liquid Glass".

**`NSSplitViewController` gives the same glass, with more work.** Probe: three `NSSplitViewItem`s (`sidebarWithViewController:`, a plain one, `inspectorWithViewController:`) each with an `NSHostingController`. It produced two `NSGlassEffectView`s (230 and 280 pt) and scroll pockets, but `window.toolbar == nil` and `contentMinSize == (0, 0)`: you add the `NSToolbar` (with the toggle-sidebar item) and the minimum size yourself. Its advantages are real (autosaved widths, `isCollapsed` control, `holdingPriority`, `canCollapse`), but Apple's own SwiftUI sample uses `NavigationSplitView` too. Recommendation: `NavigationSplitView`, because the root can be a single SwiftUI view and the window code stays what it is now. Switch to `NSSplitViewController` only if autosaved widths or fine collapse behaviour turn out to matter.

**Window set-up that was verified.**

- Minimum size: `.frame(minWidth: 980, minHeight: 600)` on the root view made `window.contentMinSize` = `(980, 652)` (the 52 is the title/toolbar band, because of `.fullSizeContentView`). No manual `contentMinSize` needed. `NSHostingController.sizingOptions` (interface: `minSize`, `intrinsicContentSize`, `maxSize`, `preferredContentSize`) controls which of those the hosting controller pushes to the window; the default produced this result.
- Column widths: `.navigationSplitViewColumnWidth(min:ideal:max:)` on the sidebar content (interface line 327) and `.inspectorColumnWidth(min:ideal:max:)` on the inspector's content (line 14967). With `min: 230, ideal: 268` the sidebar came out at 268 and the inspector, with `ideal: 316`, at 316 (the design's 268 and 316). Apple's page for `inspectorColumnWidth` says both forms apply "when presented as a trailing column".
- Inspector: `.inspector(isPresented:content:)` (macOS 14+, interface line 14965) goes on the detail view, not on the split view. Apple: "Trailing column inspectors have their presentation state restored by the framework."
- Titlebar: nothing special needed beyond `.fullSizeContentView`; `toolbarStyle` stayed `.automatic` (0) and the title ("Carrier") sits in the toolbar. `titlebarAppearsTransparent` stayed false and the system still drew the sidebar behind the traffic lights. `windowToolbarStyle` and `windowResizability` exist only as `Scene` modifiers (interface lines 24534 and 625), so they do not apply to an `NSWindow` hosted by hand; use `NSWindow.toolbarStyle` if a style is wanted.
- **Sidebar toggle.** The toolbar of the hosted window had only my own items; no sidebar toggle appeared, and `NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)` changed nothing (pane widths stayed 316 and 268). So do not count on the automatic toggle (`ToolbarDefaultItemKind.sidebarToggle` exists, so a scene-based window probably gets it; not tested). What compiled and put an item in the toolbar: `NavigationSplitView(columnVisibility: $columns)` plus `ToolbarItem(placement: .navigation) { Button { columns = columns == .detailOnly ? .all : .detailOnly } label: { Label("Sidebar", systemImage: "sidebar.leading") } }`. The click itself was not exercised.
- Sidebar list: `List(selection:)` with `.listStyle(.sidebar)` (interface `SidebarListStyle`), `Section { } header: { HStack { Text("Running"); Spacer(); Menu { Picker("Group by", ...) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden } }` for the header with the `⋯` menu, rows of `HStack { glyph, VStack { title + "#40", subtitle } }.tag(selection)`, and `.safeAreaInset(edge: .bottom)` for Settings/About. All compiled and rendered in the window. The existing `PanelView.swift` already uses this shape. `Section(isExpanded:)` gives collapsible groups if wanted.

## 2. Pipeline strip fixed on top, content scrolling behind it

Use **`.safeAreaBar(edge: .top) { PipelineStrip() }`** on the `ScrollView` (macOS 26, interface `SwiftUICore.View`, line 22856). Apple's page: it "shows the specified content as a custom bar", "the content view is anchored to the specified … edge and its [size] insets the safe area. Additionally, it extends the edge effect of any scroll views affected by the inset safe area." That is exactly "translucent, blurred, content passes behind": probe result, the window's view tree has an `NSScrollPocket` of the strip's size in the centre column, and the `cacheDisplay` image shows row 0 ending under the strip. Add `.scrollEdgeEffectStyle(.soft, for: .top)` (line 15926; styles `.automatic`, `.soft`, `.hard`) only if the default edge looks wrong; Apple: "By default, a scroll view renders an automatic edge effect." There is also `scrollEdgeEffectHidden(_:for:)`.

What each option does, ranked by simplicity:

1. `safeAreaBar` (recommended): system blur and edge effect, no code for the material. Compiled and run.
2. `safeAreaInset(edge: .top) { strip.background(.regularMaterial) }`: works on every OS, but you draw the blur yourself and the content has a hard edge. Not run; use it only if `safeAreaBar` looks wrong with the toolbar above it.
3. A toolbar item: Apple's toolbar guidance wants icons, not a stepper with text, so no.
4. `backgroundExtensionEffect()` (line 15832) is the wrong tool: it mirrors and blurs content *beside* the sidebar/inspector for hero images ("extends and blurs the image under the sidebar and inspector"), not a bar.

One thing to watch: the strip must not be under the glass toolbar's own scroll pocket twice; in the probe both coexisted (title row, then strip, then content), but how they look together is unverified (no screenshot).

## 3. Glass: where and where not

Verified in the SDK: `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `View.glassEffect(_:in:)` (default shape is a capsule), `GlassEffectContainer(spacing:content:)`, `glassEffectID`, `glassEffectUnion`, `glassEffectTransition`, `PrimitiveButtonStyle.glass` / `.glass(_:)` and `.glassProminent`. All macOS 26. All of these compiled in the probe.

Apple's rules (Adopting Liquid Glass; Applying Liquid Glass to custom views): glass is "a distinct functional layer for controls and navigation elements"; "limit these effects to the most important functional elements"; "avoid overcrowding or layering Liquid Glass elements on top of each other"; use `GlassEffectContainer` "when applying Liquid Glass effects on multiple views to achieve the best rendering performance"; "too many Liquid Glass effect containers and … effects to views outside of containers can degrade performance".

Mapping to the design:

| Design element | Use |
|---|---|
| Buttons in the toolbar and the inspector footer (Open window, Reveal, Choose…, Detect again, Send a test) | `.buttonStyle(.glass)`; the primary one (Start Carrier, Continue in terminal) `.buttonStyle(.glassProminent)` with `.tint`. Small ones: `.controlSize(.small)`. |
| Sidebar, inspector, toolbar | Nothing to add: the system draws them. |
| "2/3" pill in the sidebar header, count chips | Plain `Capsule()` filled with `Color.green.opacity(0.22)` (as the design does with `color-mix`), not glass: they are content/status, and the sidebar is already glass (glass on glass). |
| Tab controls (Slices/Review/Details, Agent output/Files changed, Settings tabs) | See below. |
| Agent session cards, tool-call cards, "Now" card, details groups, overview tiles, file lists | Content: `.background(.quaternary, in: .rect(cornerRadius: 16))` (a semantic fill) or `.regularMaterial` if something scrolls behind it. Not glass. The design's own cards are `rgba(255,255,255,.055)` fills with a 0.5 px line, which `Color(nsColor: .quaternarySystemFill)` plus `.overlay(.separator)` reproduces. |
| Transcript and diff areas | Solid dark fill; they are code. |
| Floating "scroll to latest" or similar pill, if added | `glassEffect(.regular.interactive(), in: .capsule)`. |

Render note: in the headless `ImageRenderer`, glass buttons came out as flat green slabs, so judge glass only in a real window.

**Small pill tabs.** Native: `Picker(selection:) { ... }.pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()` compiled and is an AppKit `NSSegmentedControl`, so it follows the system's Liquid Glass look for free, with `Label`s for the icons and text like `Slices 3/8` for the count badge. It cannot draw the design's orange count badge inside a segment. Custom: an `HStack` of buttons in a `Capsule` with the selected one a lighter capsule (`matchedGeometryEffect` for the slide) is about 25 lines and matches the mockup pixel for pixel, but is not a system control (no keyboard arrows, no VoiceOver "segment" semantics unless added). Recommendation: start native for the three tab groups, switch to custom only if the badge colour is wanted. How the native one looks next to the mockup is unverified (could not be seen).

## 4. Donut chart

Both work, both rendered headless (image `out/gallery-dark.png` in the throwaway folder: left Charts, right custom).

- **Swift Charts**: `Chart(data) { SectorMark(angle: .value("n", s.n), innerRadius: .ratio(0.78), angularInset: 2).cornerRadius(4).foregroundStyle(s.color) }.chartLegend(.hidden)` (interface: `SectorMark.init(angle:innerRadius:outerRadius:angularInset:)`, `ChartContent.cornerRadius(_:style:)`, `chartAngleSelection(value:)` for tap-to-select a legend entry). Gives a gap (`angularInset`) and rounded corners on each segment, but those are rounded *corners*, not round *caps*: the ends stay flat-ish with softened corners. It adds the `Charts` import (a system framework, no package) and comes with accessibility for free. No track ring: add a grey full-circle `SectorMark` or a background circle.
- **Custom `Shape`** (`Path.addArc` stroked with `StrokeStyle(lineWidth: 12, lineCap: .round)`, one arc per segment, `animatableData` for animation): exact match for the mockup, whose SVG is `stroke-linecap="round"` with `stroke-dasharray` and a 14-unit gap. Cost: round caps eat `lineWidth/2` at each end, so the gap you pass must be larger than the visual gap; the probe used a 2% gap and the caps almost touch (blue next to green in the render). `Circle().trim(from:to:)` also works but each segment needs its own rotation; `Path.addArc` is simpler.

Recommendation: the custom `Shape` (about 20 lines, three segments, the design asks for round caps with a gap). Use Charts if rounded corners are an acceptable approximation or if tap selection of segments is wanted. Both render in `ImageRenderer`, so both are testable (question 11).

## 5. Animations

Design: avatar with a ring turning inside while working; a green moving glyph in the sidebar; a pulsing dot.

Measured (release build, a 8-avatar window, 20 s of process CPU time via `ps -o time`, one run per row, noise a few points; "WindowServer" could not be separated from its 40%-55% idle load and is not reported):

| Variant (8 of them) | App CPU |
|---|---|
| Static avatars | 0% |
| SwiftUI `rotationEffect` + `.linear(duration: 1).repeatForever` | 8.8% to 10.7% (three runs) |
| Same, window hidden with `orderOut` after 1 s | 10.3% (does not stop) |
| `TimelineView(.animation(minimumInterval: 1/20))` | 7.9% |
| `TimelineView(.animation)` (uncapped) | 3.2% (single run; unexplained, lower than the capped one, treat as noise) |
| Pulse dot, `.opacity` + `.easeInOut.repeatForever` | 7.8% to 8.2% |
| Core Animation ring (`CAShapeLayer` + `CABasicAnimation`, `preferredFrameRateRange` 20 fps) in an `NSViewRepresentable` | 0% |
| SwiftUI ring gated by the window's occlusion state, visible | 12% |
| Same, window hidden | 0% |

What follows:

- SwiftUI animations run in the app's process, a frame at a time. Eight small rings are not free (about one tenth of a core). The design can have more than eight avatars on screen (session headers, overview rows, slices), and a spinning glyph per sidebar row.
- `repeatForever` does **not** stop when the window is ordered out. `onAppear`/`onDisappear` do not fire for that either. The existing app keeps its `NSWindow` for the life of the app (`isReleasedWhenClosed = false`) and only stops the *monitor* on close, so a closed window with a spinning ring inside would keep burning CPU. Gate it: observe `NSWindow.didChangeOcclusionStateNotification` (`WindowVisible` in the probe: an `NSViewRepresentable` that reports `window.occlusionState.contains(.visible)`) and do not build the ring while false. The ring must keep its animation `@State` in its own small view (`SpinRing`), not in the parent, or it comes back as a frozen ring: this bit the first version of the probe (the flag stayed true after the ring was removed and re-inserted, so nothing animated).
- `TimelineView(.animation(minimumInterval:paused:))` is the only frame-rate control SwiftUI exposes; `preferredFrameRateRange` is a Core Animation property (it is not in the SwiftUI interface). It did not beat `repeatForever` here, so it is not worth the complexity.
- The repo's finding (section 6 of [macos-app.md](macos-app.md)) was that an uncapped Core Animation animation made WindowServer expensive in the translucent *menu bar* and that `preferredFrameRateRange` fixed it. The same applies to the CA ring: set the 20 fps range. Whether a ring inside the window costs WindowServer anything was not measurable here. The window is opaque-ish glass, not the menu bar, so the effect may differ; unverified.
- Recommendation: a Core Animation ring (`CARing` in the probe, 20 lines) for the avatars and the sidebar glyph, because they are many and always visible while working; plain SwiftUI `.opacity` pulse for the one or two dots (cheap enough, add the occlusion gate). Both use `@Environment(\.accessibilityReduceMotion)` (interface `SwiftUICore` line 23466): when true, show a static ring (a partial arc without rotation) and a static dot. The CA view reads it through `makeNSView`/`updateNSView` context and does not add the animation. `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is the AppKit equivalent. Not tested with the setting on (the setting cannot be changed from here).
- When the app is in the background but the window is visible, nothing stops the animation; that is normal for a visible window. When the window is minimised or fully covered, occlusion becomes not visible and the gate stops it.

## 6. Truncation, monospaced text, transcripts

- **Middle truncation**: `Text(path).lineLimit(1).truncationMode(.middle)` rendered `app/api/very/long/d…re/webhooks/route.ts` in a 360 pt row, the end of the path (the file name) kept. For `#40` that must never be hidden: `HStack { Text(name).lineLimit(1).truncationMode(.tail); Text("#40").layoutPriority(1) }`; the probe's sidebar row truncated the name and kept the number.
- **Monospaced**: `.font(.system(.caption, design: .monospaced))` (or `.monospaced()` on a font). `.monospacedDigit()` for the `+64 −0` counts.
- **Selectable**: `.textSelection(.enabled)` on the path text and on message text compiled and rendered. For a transcript with hundreds of cards, put it on the message text and the diff text, not on the whole container (selection across lazy rows is limited in SwiftUI; not tested).
- **Long transcript**: 800 rows (a message plus a tool card, every third with a 2-line diff), release build, 620x700 window, 60 programmatic scroll steps of 500 pt:

| Container | First show | Footprint | 60 scroll steps (worst step) |
|---|---|---|---|
| `ScrollView { VStack }` | 806 ms | +196 MB | 200 ms (20 ms) |
| `ScrollView { LazyVStack(pinnedViews: [.sectionHeaders]) }`, 8 sections of 100 | 101 ms | +15 MB, +42 MB after scrolling | 292 ms (27 ms) |
| `List(... ).listStyle(.plain)` | 105 ms | +22 MB, +24 MB after | 658 ms (31 ms) |

  `LazyVStack` is the fit: fast open, small footprint, the cheapest scrolling of the two lazy ones, variable-height cards with no fixed-height trouble, and `pinnedViews: [.sectionHeaders]` gave sticky per-agent headers with `Section { } header: { }` (the header background was `.bar`, which also satisfies "translucent"). `List` printed `WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.` and its document height was an estimate (45 127 vs 61 844 pt), which makes scroll positions jump with variable heights. The eager `VStack` is out. The first-show time includes layout of everything in view, not the data decoding. Message and card views here are simple; real syntax-coloured diffs will cost more per row. With `LazyVStack`, keep the model's rows `Identifiable` and stable (the transcript from `OutputWatcher.lines` is re-sent whole every 2 s today, so diffing by line index matters, see the hierarchy section).
- "Collapsible output" per card: `DisclosureGroup`, or a `@State var open` per card (the probe's `ToolCard(expanded:)`); keep collapsed content out of the view tree (`if open`) so lazy rows stay cheap.

## 7. File-type icons

`UTType(filenameExtension: ext)` then `NSWorkspace.shared.icon(for: type)` (the `forContentType` form; `icon(forFileType:)` is the older one) returns an `NSImage` with 32 representations; `Image(nsImage:).resizable().interpolation(.high).frame(width: 24, height: 24)` draws them (rendered fine, see `out/gallery-dark.png`: document icons with a small `TS`, `{}` or arrow). Probe results for 10 names: `swift`, `md`, `json`, `png`, `sh`, `yml` resolve to proper UTIs; `Dockerfile` (no extension) gives `nil`; `.lock` and unknown extensions give a `dyn.` dynamic type (generic document icon). **`.ts` resolves to `public.mpeg-2-transport-stream`** (video), so a TypeScript file gets the transport stream's icon, which looks like a "TS" document here but is the wrong type; if the design's letters-in-tiles are wanted for code files, a small table of the extensions Carrier cares about (ts, tsx, js, json, md, yml, swift, css, html) overriding the UTI is safer. Cache by lowercased extension in a `[String: NSImage]` on the main actor (the probe's `FileIcons`; second lookups took about a microsecond). Creating the image is lazy (0.01 ms); the Launch Services work happens at the first draw, so no need to prefetch. The design's own icons are placeholders ("a proper icon set comes later"), so this is the system-icon option, not a final one; the alternative is SF Symbols (`doc.text`, `curlybraces`, `photo`) tinted by category.

## 8. Menu bar

**Keep `NSStatusItem` and `NSMenu`**, and add the epics to the menu. Probe (`EpicMenu`): an `NSMenuDelegate` whose `menuNeedsUpdate(_:)` rebuilds the epic items each time the menu opens, with `NSMenuItem.sectionHeader(title:)` for "Epics", `item.image = NSImage(systemSymbolName:)` configured with `NSImage.SymbolConfiguration(paletteColors: [.systemGreen])` for the state glyph (green `circle.dotted` running, orange `exclamationmark.circle.fill` needs you, blue `checkmark.circle.fill` ready, grey `circle` waiting), an `attributedTitle` with the name and a smaller secondary-colour state line, and `item.badge = NSMenuItemBadge(string:)` for "2/5". It built and ran headless (six items, images and badges set); how the menu looks, and whether palette colours survive the glass menu, was not seen. The repo's `MenuControls` already builds the menu once and updates item titles from `react(to:)`; the epic items should be inserted the same way `install(in:after:)` does, from the state the `AppDelegate` monitor already delivers. Rebuilding in `menuNeedsUpdate` reads the latest state at open time and costs nothing while the menu is closed. Caveat from the repo's own research: changing the *status item's image* invalidates an open menu; items inside the open menu are a different matter and the existing code already sets titles on the main queue while open.

**`MenuBarExtra`: not worth it, confirmed.** SDK facts: `MenuBarExtra` is `macOS 13.0` only, with `init(isInserted:content:label:)` and `init(content:label:)` and exactly two styles, `.menu` (`PullDownMenuBarExtraStyle`) and `.window` (`WindowMenuBarExtraStyle`); nothing new for 26 or 27 in the interface. `.menu` renders `Button`/`Divider`/`Toggle` as menu items (no per-row custom view); `.window` is a floating panel, not a menu. The reasons in [macos-app.md](macos-app.md) stand: it needs a SwiftUI `App` lifecycle (the spike's app ended by itself when the extra was not inserted), its label swaps images (22% CPU at 12.5 fps in that spike) and the custom Core Animation icon needs the `NSStatusItem.button` that the existing code owns. The only new thing it would buy is a SwiftUI-rendered menu body, which the design's menu (plain rows, glyphs, a badge) does not need. Keep the current approach.

## 9. Settings inside the main window

A sidebar destination (`SidebarSel.settings`) whose detail is a `Form` with `.formStyle(.grouped)` or the design's own grouped cards. Compiled (`SettingsSample`):

- Switches: `Toggle("…", isOn: $x).toggleStyle(.switch)`. Persist with `@AppStorage` for the app's own preferences; the existing `SetupController.settings` for the engine paths.
- The tabbed layout (Engine, Notifications, Menu bar, General): a `Picker(...).pickerStyle(.segmented)` bound to an enum, then a `switch` on it (as in question 3). The icon previews ("Count and bar" etc.) are small views in a `Button` row with a selection ring, not a picker.
- Path rows with "Reveal" and "Choose…": `Text(path).lineLimit(1).truncationMode(.middle)`; Reveal = `NSWorkspace.shared.activateFileViewerSelecting([url])`; Choose = either SwiftUI `.fileImporter(isPresented:allowedContentTypes:)` (compiled) or `NSOpenPanel` with `canChooseFiles`, `canChooseDirectories`, `directoryURL`, `runModal()` (compiled; the AppKit panel was not shown). The `NSOpenPanel` form is simpler to call from a button and to configure for "choose a folder" (shared root) versus "choose a file" (carrier script). Not exercised: the panel opens a modal on the real screen.
- Open at login: `SMAppService.mainApp.register()/unregister()` and `.status` (interface: `ServiceManagement`). In an unbundled executable `SMAppService.mainApp.status` returned `3` (`notFound`), so the toggle has to be tested from the ad-hoc signed `Carrier.app` that `build-app.sh` makes. Not tested there; whether ad-hoc signing is enough for `register()` on macOS 27 is unverified. The design says it "starts the app, never Carrier itself", which is what `mainApp` does. Show `requiresApproval` (status 2) as a link to Login Items (`SMAppService.openSystemSettingsLoginItems()`).
- Notifications "Send a test": the repo's `SystemNotificationCentre` already exists; the Settings view only needs a button calling it.

## 10. Light and dark, accent, colours

Resolved values on this Mac (`NSAppearance.performAsCurrentDrawingAppearance`, sRGB):

| Design token (dark / light) | System colour | System value (dark / light) |
|---|---|---|
| green `#30d158` / `#28a745` | `Color.green` (`systemGreen`) | `#30d158` (exact) / `#34c759` |
| orange `#ff9f0a` / `#e08600` | `Color.orange` | `#ff9230` / `#ff8d28` |
| blue `#0a84ff` / `#007aff` | `Color.blue` | `#0091ff` / `#0088ff`; `controlAccentColor` = `#007aff` (the user's accent, default blue) |
| red `#ff453a` / `#e5372d` | `Color.red` | `#ff4245` / `#ff383c` |
| `--text` | `.primary` (`labelColor`) | white 85% / black 85% |
| `--dim` (62% / 66%) | `.secondary` (`secondaryLabelColor`) | 55% / 50% |
| `--faint` (34% / 38%) | `.tertiary` (`tertiaryLabelColor`) | 25% / 26% |
| `--line` (10%) | `.separator` / `Color(nsColor: .separatorColor)` | 10% (exact) |
| `--card` (5.5% / 4%) | `Color(nsColor: .quaternarySystemFill)` or `.quaternary` | 3% (a hair lighter than the mockup); `tertiarySystemFill` 5% is closer |
| `--card2` (9% / 7%) | `.secondarySystemFill` / `.tertiary` fill | 8% |
| `--sel` selection | `.selection` / accent | list rows use the system selection; do not hand-colour them |
| window/background | `.background` / `.windowBackgroundColor` | `#1e1e1e` / white (the glass is translucent over it) |

Take the semantic colours as they are: `.primary`, `.secondary`, `.tertiary`, `.separator`, `.quaternary`, `.tint` for the accent (follows System Settings; the design's "live accent" blue is `.tint`, so it becomes the user's accent colour, which the design's "colour carries meaning" rule treats as acceptable only for selection and the in-progress step). The mockup's own numbers are Apple's dark palette for green and blue, so the system values are the design.

The custom colours the design needs, three:

- **Running**: `Color.green` (system). The light-mode design value `#28a745` is darker than `#34c759` for text contrast; for green *text* on the light background (the pill label, the `+64` count), use `Color.green.mix(with: .black, by: 0.15)` or a named asset colour with light/dark variants, otherwise the system green is fine for glyphs and fills.
- **Needs you**: `Color.orange` for fills and glyphs; light-mode text needs a darker orange than the system's (`#e08600`), so define it as an asset or `Color(light:dark:)`-style `NSColor` with an `NSColor(name:dynamicProvider:)`.
- **Ready for test**: `Color.blue` (`#0091ff`/`#0088ff`); the design's "ready" blue is distinct from the accent, so do not use `.tint` for it, or it turns grey-blue/purple/etc. when the user picks another accent.

Define the three once (`extension Color { static let running, needsYou, ready }`) in an asset catalog or via `NSColor(name:dynamicProvider:)`; SwiftPM resources work for an asset catalog, but the repo builds the `.app` by script, so the dynamic-provider form needs no resource handling. Apple's own advice: "leverage system colors, or define a custom color with light and dark variants, and an increased contrast option for each variant." Increase-contrast variants were not tested. The red in the design is for errors and uses `Color.red`. The transcript's black pane is a fixed `#0d0d10`/`#1d1d22` in the design in both modes; keep it fixed (code areas), not semantic.

## 11. Testing without a screen

State of the toolchain: `xcode-select -p` is full Xcode here; the repo's README promises the Command Line Tools are enough, which is false for SwiftUI code on the macOS 27 SDK (risk 1). With Xcode's toolchain `swift test` in the repo copy ran 108 tests (Swift Testing) in 0.2 s; in my package `swift test` with two Swift Testing tests (rendering and caching) passed.

**What works, and what does not.**

1. **View-model and formatting tests in `CarrierCore`**: the right place for almost everything (state derivation, grouping by status or repo, strings, counts, which glyph, donut segment fractions, menu items). They run with no UI, on any toolchain. `IconState`, `PanelFormat` and `ConnectionState` are already built this way. Put the new derived state (grouped sidebar rows, pipeline step states, review phases, per-file `+N −N` totals per session) here as plain values; the SwiftUI views become thin mappings of them. This is what the agent can verify exactly.
2. **`ImageRenderer` headless: works**, no window, no `NSApplication.run`, on the main actor (`MainActor.assumeIsolated` or `@MainActor` test). `ImageRenderer(content: view.environment(\.colorScheme, .dark))`, `scale = 2`, `.cgImage` gave a 1040x1024 image in 35 to 210 ms; light and dark both rendered. Inside a Swift Testing test it passed, including reading a pixel (`NSBitmapImageRep.colorAt`) to check that the green segment is where it should be. It draws text, shapes, `Image`, SF Symbols, the Charts donut and the custom donut, file icons, cards, monospaced text and middle truncation. Apple's page says what it cannot: "does not include views whose contents are composited by Core Animation layers, such as more complex controls and containers … most types of UIKit and AppKit views. In those cases, `ImageRenderer` displays a placeholder image". Observed: `List`, `NavigationSplitView` (the whole shell rendered as a red "prohibited" sign on yellow), the segmented `Picker` and the glass buttons come out as placeholders or flat slabs. So **render the leaf views** (a session card, tool card, donut, overview tiles, the review steps, a settings row, the empty states), not the shell, and compare against the mockup by eye or by a stored reference PNG with a tolerance. An agent can render a screenshot of a leaf view and view it (the images were read back and looked right).
3. **`NSHostingView.cacheDisplay` and `layer.render(in:)`: not reliable.** Off-screen hosting view: text and images drawn, shapes and backgrounds missing. A real on-screen window `cacheDisplay` produced a usable structural picture of the whole shell (sidebar rows, strip over the rows, the inspector text, toolbar button), but without glass or materials and with wrong selection colours; `CALayer.render(in:)` produced garbage (the layout misplaced). Useful as a smoke test that a window lays out and nothing is clipped; it is not a screenshot of the real look.
4. **True screenshots**: `screencapture -l <windowNumber>` exited 1 ("could not create image from window"; the full-screen one: "could not create image from display"), since this process has no Screen Recording permission. With that permission granted to the terminal or runner, `screencapture` of the probe's window number would work; it was not tested. Without it, the whole-window look (glass, edge blur) needs a person.
5. **Structure assertions on a live window** do work and are cheap: after `NSHostingController` + `orderFrontRegardless` + 2 s, the probe read `contentMinSize`, the toolbar items, the tree's `NSGlassEffectView` and `NSScrollPocket` counts and the pane widths. They are fine as a smoke test of the window set-up (`contentMinSize` equals the declared minimum, the inspector is 316 wide); they open a real window, so keep them out of the default `swift test` or mark them as such. The repo's existing `CarrierTests` already does a small version of this for the icon layer.

Where SwiftUI cannot run in tests at all: nothing found; `@MainActor` tests work under Swift Testing with Xcode's toolchain.

## Recommended view hierarchy

Names are suggestions; `CarrierCore` types are the real ones.

```
AppDelegate (existing)
  NSStatusItem + IconController (existing, untouched)
  NSMenu (existing) + EpicMenuSection (new, NSMenuDelegate: epics, glyph images, badge)
  WindowController (existing) -> NSWindow (.fullSizeContentView) -> NSHostingController(sceneBridgingOptions: .all)
    AppRoot(model: AppModel)                         // one NavigationSplitView
      Sidebar                                        // List(.sidebar), selection: SidebarSel
        OverviewRow
        EpicGroup(status | repo)  { header: title + "2/3" pill + GroupMenu(⋯) }  -> EpicRow (StateGlyph, name #n, subtitle)
        (safeAreaInset bottom) SettingsRow, AboutRow
      Detail (switch on selection)
        OverviewView: YourTurnList, SlotTiles(3), AgentsWorking, HealthCard, WatchedRepos, EmptyState
        EpicView(epic)                               // .inspector(isPresented:) on this view
          ScrollView { LazyVStack(pinnedViews) }
            EpicHeader
            OutputPicker (Agent output | Files changed)  [segmented, small]
            SessionSection(session)                  // header: AgentAvatar + title + stats; body: Message | ToolCard (icon, path, DiffView, CollapsibleOutput)
            FilesChanged: SessionFiles -> FileRow (FileIcon, PathText, +N −N)
          .safeAreaBar(edge: .top) { PipelineStrip(steps) }
          .toolbar { sidebar toggle, inspector toggle, Open in browser… }
          .inspector { InspectorView }
            TabPicker (Slices | Review | Details)
            SlicesTab: DonutView(segments), Legend, SliceList
            ReviewTab: NowCard, ReviewSteps (1-2-3, connector), FoldedHistory
            DetailsTab: DetailGroup -> DetailRow
        SettingsView: BannerStatus, TabPicker(Engine|Notifications|Menu bar|General), SettingRow(PathRow | SwitchRow | PreviewRow)
        AboutView (sheet or detail)
```

Reusable leaves: `AgentAvatar` (CA ring, occlusion gated), `StateGlyph`, `PulseDot`, `Pill`, `Card` (fill, not glass), `EmptyState(icon, title, line)`, `PathText` (mono, middle truncation), `FileIcon` (UTI cache).

**Where state lives.**

- `AppModel` (`@Observable`, main actor; the current `PanelModel` grows into it). Holds `state: ConnectionState?` (set from `ControlMonitor.onChange` via `DispatchQueue.main.async`, as `WindowController.startMonitor` does now, with the same StopFlag so a closed window costs nothing), derived values computed in `CarrierCore` from `PanelSnapshot`: `epics` grouped by status or repo, `slots`, `health` lines (`PanelFormat`: `uptimeLine`, `nextCheckLine`, `reposLine`), `IconState`. Views read it with plain `let model: AppModel` (no property wrapper needed for `@Observable`).
- `@State` in `AppRoot`: `selection: SidebarSel?`, `inspectorOn`, `columns` (split visibility). `@AppStorage`: `groupBy`, the last inspector tab, settings switches. `@State` in leaf views: expanded cards, hovered rows.
- `EpicTranscript` (`@Observable`, one per open epic view): fed by `OutputWatcher` (already in `CarrierCore`) on its own thread while the epic's output tab is visible, started in `.task(id: epic.executionId)` and ended by task cancellation (replaces `AgentOutputWindow`'s own StopFlag). Today `OutputWatcher` returns the last `count` raw lines every 2 s; the design needs parsed sessions, tool calls and diffs, a message and a file list per agent. Those are not in the snapshot or the tail: the brief and the design README already say the engine has to supply them. The view hierarchy above assumes a parser in `CarrierCore` that turns lines into `Session`/`Message`/`ToolCall`/`FileChange` values and tests like `AgentOutput`'s.
- The menu keeps its own derived state from the `AppDelegate` monitor (`MenuControls.react(to:)`), so the menu works with the window closed.

Everything the monitor delivers arrives once per second; `@Observable` only invalidates views that read the changed properties, but the whole `ConnectionState` enum is replaced each second, so break the model into per-epic values keyed by `repo#issue` (a struct with `Equatable`) and assign only when different, or the sidebar and transcript will re-evaluate every tick. That was not measured.

## What stayed unverified

- How the window actually looks (glass, edge blur, strip under the toolbar, segmented control against the mockup's pills, the menu with palette-coloured glyphs): no screenshot possible (no Screen Recording permission; `ImageRenderer` cannot draw these).
- That the explicit sidebar-toggle toolbar item toggles; that a scene-based window gets the automatic toggle that the AppKit-hosted one did not.
- WindowServer cost of animated layers inside the window, battery, ProMotion/120 Hz, several displays; the 8 to 12% figures are one machine, release build, small samples.
- Behaviour with Reduce Motion, Reduce Transparency and Increase Contrast turned on.
- `SMAppService.mainApp.register()` from the ad-hoc signed `Carrier.app` on macOS 27; `NSOpenPanel` and `.fileImporter` interaction (nothing was shown).
- `.textSelection(.enabled)` across many lazy rows; syntax-coloured diff cost per row; the 1-per-second whole-state replacement cost.
- `NavigationSplitView` state restoration and the inspector's restored state in a hand-hosted window.
- `swift test` under the Command Line Tools with `--sdk MacOSX26.sdk`: the build succeeded there and a test run printed passing tests, but an earlier invocation also showed a frontend failure in the test build that was not investigated; treat CLT-only as unsupported until retried.
- Apple pages quoted come from the documentation JSON; the HIG-level statements (glass on the functional layer) are Apple's, the mapping to this design is mine.
