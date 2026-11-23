import AppKit
import CarrierCore
import QuartzCore
import SwiftUI

/// A session in the sidebar: the project as an icon (its initials on a colour of its own, in a rounded square) that carries the state,
/// the title and under it where it works, and on the right the age of its last activity over the providers it has used. The two
/// lines on each side have the same height, so the age sits on the title's line and the providers on the second one.
struct SessionRowView: View {
    private let timeChanges = TimeFormatChanges()
    let row: SessionRow
    /// Outside the workspace order the group is not the workspace, so the second line says it.
    let showsWorkspace: Bool
    /// Pin and Archive take the age's place while the pointer is on the row. Only the sessions list asks for them: the Archive section draws
    /// this row inside a button, and Settings draws it as a preview.
    var hoverActions = false
    /// The sidebar's list gives its rows room around their lines and the third one, with the pull request; the Archive section keeps them compact.
    var roomy = false
    @State private var hovered = false
    @Environment(SessionActions.self) private var actions
    private let titles = TitleRegeneration.shared
    @AppStorage(SidebarStore.pinnedKey) private var pinnedStored = ""
    @AppStorage(SidebarStore.showsIconKey) private var showsIcon = true
    @AppStorage(SidebarStore.showsBranchKey) private var showsBranch = true
    @AppStorage(SidebarStore.showsPullRequestKey) private var showsPullRequest = true
    @AppStorage(SidebarStore.showsDiffKey) private var showsDiff = true
    @AppStorage(SidebarStore.showsProvidersKey) private var showsProviders = true
    @AppStorage(SidebarStore.showsAgeKey) private var showsAge = true
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15, metaLine: CGFloat = 17
    /// Two buttons of 22 points and the gap between them.
    private static let actionsWidth: CGFloat = 46
    /// The orange of "Waiting for you" as text: the system's on dark, a deeper one on light, where the system's is too pale to read.
    static let attention = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.70, green: 0.36, blue: 0, alpha: 1)
    })

    /// The green of "Done" (the turn ended and the person has not opened the session): a lighter one on dark, a deeper one on light.
    static let done = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.19, green: 0.70, blue: 0.31, alpha: 1) : NSColor(red: 0.12, green: 0.55, blue: 0.24, alpha: 1)
    })
    /// The cyan of a session whose turn ended while the agent waits for something it started: its ring and its clock, apart from the violet of one that works.
    static let backgroundWork = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1) : NSColor(red: 0.0, green: 0.48, blue: 0.70, alpha: 1)
    })
    /// Whether the ring stays on after the agent stops, to go round once more in green when the turn ended unread (`finished`).
    @State private var ringKept = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: SessionRowContent {
        SessionRowContent(
            row, showsWorkspace: showsWorkspace,
            parts: SessionRowParts(icon: showsIcon, branch: showsBranch, providers: showsProviders, age: showsAge, pullRequest: showsPullRequest, diff: showsDiff), now: Date()
        )
    }

    private var pinned: Bool { pinnedIds(pinnedStored).contains(row.id) }

    private func togglePin() {
        let ids = pinnedIds(pinnedStored)
        pinnedStored = storedPins(pinned ? ids.subtracting([row.id]) : ids.union([row.id]))
    }

    /// What the host refuses (a session that is working) is told in an alert, as the context menu does.
    private func archive() {
        Task { if let refusal = await actions.archive(row.id) { tell(refusal) } }
    }

    private func place(_ place: SessionPlace) -> Text {
        switch place {
        case .branch(let name): Text("\(Image(inline: .gitBranch)) \(Text(name).font(.scaled(11, design: .monospaced)))")
        case .baseFolder: Text("\(Image(inline: .folder)) Base folder")
        }
    }

    /// While the session waits for the person, the word takes the place of the time at the top right (`SessionTimeLabel`); with the time
    /// switched off it is the second line's, where it has always been.
    private func waitsAtTop(_ content: SessionRowContent) -> Bool { row.state == .waiting && content.age != nil }

    /// The same for "Done" (the turn ended and the session has not been opened since): the word takes the place of the time.
    private func doneAtTop(_ content: SessionRowContent) -> Bool { row.status == .unread && content.age != nil }

    @ViewBuilder private func detail(_ content: SessionRowContent) -> some View {
        if row.state == .waiting && waitsAtTop(content) == false {
            Text("Needs you").fontWeight(.medium).foregroundStyle(Self.attention)
        } else if row.status == .unread && doneAtTop(content) == false {
            Text("Done").fontWeight(.medium).foregroundStyle(Self.done)
        } else {
            switch (content.workspace, content.place) {
            case (let workspace?, let placed?): Text("\(workspace) · \(place(placed))").foregroundStyle(.secondary)
            case (let workspace?, nil): Text(workspace).foregroundStyle(.secondary)
            case (nil, let placed?): place(placed).foregroundStyle(.secondary)
            case (nil, nil): Text("")
            }
        }
    }

    /// The time at the top right (`SessionTimeLabel`).
    private func ageOrStopwatch(_ content: SessionRowContent) -> some View { SessionTimeLabel(row: row, age: content.age) }

    /// The age, or the two buttons while the pointer is on the row. The age stays in the layout, hidden, so the column does not change its width as they come in.
    private func ageSlot(_ content: SessionRowContent) -> some View {
        ZStack(alignment: .trailing) {
            ageOrStopwatch(content).opacity(hoverActions && hovered ? 0 : 1)
            if hoverActions && hovered {
                HStack(spacing: 2) {
                    hoverButton(pinned ? .pinOff : .pin, pinned ? "Unpin" : "Pin", togglePin)
                    hoverButton(.archive, "Archive", why: archiveBlock(row), archive)
                }
                .transition(.opacity)
            }
        }
        .font(SidebarMetrics.detail.monospacedDigit()).lineLimit(1).frame(height: Self.titleLine)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        // room for the two buttons even while they are hidden, so the title does not move as the pointer comes in
        .frame(minWidth: hoverActions ? Self.actionsWidth : nil, alignment: .trailing)
    }

    var body: some View {
        let content = content
        // the third line, with the pull request and the lines changed, only where the list has room for it and the session has either
        let third = roomy && content.hasThirdLine
        HStack(alignment: .top, spacing: SidebarMetrics.inset) {
            if content.showsIcon {
                ProjectIcon(
                    base: row.base, name: row.workspace, colorKey: projectColorKey(row.base), working: row.isWorking, background: row.isWorking && row.state != .working,
                    finished: ringKept && !row.isWorking
                )
            }
            VStack(alignment: .leading, spacing: roomy ? density.sessionLineGap : SidebarMetrics.lineGap) {
                HStack(spacing: 4) {
                    RollingTitle(text: titles.title(of: row), waiting: titles.waiting.contains(row.id))
                        .font(SidebarMetrics.item).fontWeight(row.state == .waiting ? .medium : .regular)
                    Spacer(minLength: 4)
                    ageSlot(content)
                }
                .frame(height: Self.titleLine)
                HStack(spacing: 4) {
                    detail(content).font(SidebarMetrics.detail).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    // with no third line the providers sit here; with one they go down to it
                    if third == false { ProviderMarks(names: content.providers) }
                }
                .frame(height: Self.detailLine)
                if third {
                    HStack(spacing: 8) {
                        SessionWorkPill(pr: content.pullRequest, diff: content.diff)
                        Spacer(minLength: 4)
                        ProviderMarks(names: content.providers)
                    }
                    .frame(height: Self.metaLine)
                }
            }
        }
        .padding(.horizontal, content.showsIcon ? (roomy ? density.sessionRowPadding - 2 : density.rowPadding) : SidebarMetrics.inset).padding(.vertical, roomy ? density.sessionRowPadding : density.rowPadding)
        .onChange(of: row.isWorking, initial: true) { _, working in if working { ringKept = true } }
        .onChange(of: row.status) { old, new in
            guard old == .working, ringKept else { return }
            // a turn that ended unread gets one fast green lap; anything else (it waits for the person, or they are looking at it) drops the ring now
            guard new == .unread, reduceMotion == false else { ringKept = false; return }
            Task { try? await Task.sleep(for: .seconds(1.2)); ringKept = false }
        }
        .onHover { hovered = $0 }
        .sessionContextMenu(row)
        .hoverCard { SessionPeekView(card: sessionPeek(row, now: Date())) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(content))
        // the buttons are drawn on hover only: VoiceOver reaches the same two here
        .accessibilityAction(named: pinned ? "Unpin" : "Pin") { if hoverActions { togglePin() } }
        .accessibilityAction(named: "Archive") { if hoverActions && archiveBlock(row) == nil { archive() } }
    }

    /// `why` is what keeps the button off: it is the tooltip then, and what VoiceOver reads after the name.
    private func hoverButton(_ symbol: AppIcon, _ title: String, why: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(symbol, size: 11).foregroundStyle(.secondary).frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(radius: 5)).disabled(why != nil).help(why ?? title).accessibilityLabel(title).accessibilityHint(why ?? "")
    }

    /// What the row says aloud: the title, the state in words (the icon draws it), where it works, the providers and "5 minutes ago",
    /// the parts the person switched off left out.
    private func label(_ content: SessionRowContent) -> String {
        let state: String? = switch row.state {
        case .working: "Working"
        case .waiting: "Needs attention"
        case .idle, .done: row.background.isEmpty == false ? "Waiting on background work" : row.status == .unread ? "Done" : nil
        }
        let place: String? = switch content.place {
        case .branch(let name)?: name
        case .baseFolder?: "Base folder"
        case nil: nil
        }
        let age = content.age == nil ? nil : spokenAge(row.updatedAt, now: Date())
        let work: [String?] = roomy ? [content.pullRequest?.spoken, content.diff.map { "\($0.added) lines added, \($0.removed) removed" }] : []
        return ([row.title, state, row.workspace, place] + work + content.providers + [age]).compactMap { $0 }.joined(separator: ", ")
    }
}

/// What a session's row says at the top right, in the place of its time: "Needs you" while it waits for a permission or an answer, "Done" and
/// beside it how long ago, once its turn ended and it was not opened since, how long the turn has run while it works or waits for what it started (a stopwatch that ticks
/// each second, in the colour of the ring), or else the age of its last activity. `age` is nil while the time is switched off: then none of it shows.
struct SessionTimeLabel: View {
    let row: SessionRow
    let age: String?

    var body: some View {
        if row.state == .waiting && age != nil {
            Text("Needs you").fontWeight(.medium).foregroundStyle(SessionRowView.attention)
        } else if row.status == .unread, let age {
            // the word, and beside it how long ago it ended: the time it would have shown
            HStack(spacing: 4) {
                Text("Done").fontWeight(.medium).foregroundStyle(SessionRowView.done)
                Text(age).foregroundStyle(.tertiary)
            }
        } else if age != nil, let since = WorkingClock.shared.since(row) {
            TickingTimeline(every: 1) { context in
                Text(workingElapsed(Int(context.date.timeIntervalSince(since)))).foregroundStyle(row.state == .working ? Color.thought : SessionRowView.backgroundWork)
            }
        } else {
            Text(age ?? "").foregroundStyle(.tertiary)
        }
    }
}

extension EnvironmentValues {
    /// Whether the row the view is in is selected or hovered: its project icon wears its colour then and is neutral otherwise. True
    /// outside the sidebar's rows, where the icon is always coloured.
    @Entry var rowActive = true
    /// How the sidebar row the view is in stands: at rest, under the pointer, or selected. At rest outside the sidebar's rows.
    @Entry var rowState = RowState.resting
}

enum RowState { case resting, hovered, selected }

extension ProjectColor {
    /// Muted hues chosen to match `ProjectIcon.palette` so white initials and marks keep readable contrast in both light and dark appearances.
    var color: Color {
        switch self {
        case .red: Color(hue: 0.98, saturation: 0.56, brightness: 0.64)
        case .orange: Color(hue: 0.06, saturation: 0.60, brightness: 0.62)
        case .yellow: Color(hue: 0.125, saturation: 0.56, brightness: 0.52)
        case .green: Color(hue: 0.375, saturation: 0.54, brightness: 0.51)
        case .teal: Color(hue: 0.47, saturation: 0.54, brightness: 0.52)
        case .blue: Color(hue: 0.61, saturation: 0.56, brightness: 0.64)
        case .purple: Color(hue: 0.76, saturation: 0.52, brightness: 0.64)
        case .pink: Color(hue: 0.90, saturation: 0.52, brightness: 0.64)
        }
    }
}

/// Loads and caches copied project icon PNGs from `project-icons`, returning nil when the file is missing or unreadable so the tile falls back to color and mark.
@MainActor enum ProjectIconImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named fileName: String?, in store: ProjectIconStore = .current()) -> NSImage? {
        guard let url = store.existingURL(for: fileName) else {
            if let stale = store.fileURL(for: fileName) { cache.removeObject(forKey: stale.path as NSString) }
            return nil
        }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let loaded = NSImage(contentsOf: url), loaded.isValid, loaded.size.width > 0, loaded.size.height > 0 else { return nil }
        cache.setObject(loaded, forKey: key)
        return loaded
    }
}

/// The project's icon: its chosen image, or its chosen mark or initials in white on its chosen colour or one made from its name, in a rounded
/// square of glass tinted with it. A bright arc goes round its edge while an agent works (`WorkingRing`).
/// In a sidebar row it is neutral until the row is selected or hovered (`rowActive`).
struct ProjectIcon: View {
    let name: String
    /// What the colour is made from: `projectColorKey` of the folder or the repository.
    let colorKey: String
    var customColor: ProjectColor? = nil
    var mark: AppIcon? = nil
    var image: String? = nil
    var imageFolder: String? = nil
    var working = false
    /// The ring is the cyan of a session that waits for something it started, not the violet of one that works.
    var background = false
    /// The ring goes once round in green, fast, after `working`: the agent just ended its turn. The owner takes it away a moment later.
    var finished = false
    @Environment(\.rowActive) private var active
    static let size: CGFloat = 32
    static let radius: CGFloat = 9
    /// 24 muted colours: 12 hues, each in a fuller and a greyer tone, the brightness of each chosen so the white letters keep at least 4.5:1.
    static let palette: [Color] = [
        (0.042, 0.52, 0.64), (0.125, 0.52, 0.52), (0.208, 0.52, 0.49), (0.292, 0.52, 0.51), (0.375, 0.52, 0.51), (0.458, 0.52, 0.51),
        (0.542, 0.52, 0.56), (0.625, 0.52, 0.64), (0.708, 0.52, 0.64), (0.792, 0.52, 0.64), (0.875, 0.52, 0.64), (0.958, 0.52, 0.64),
        (0.042, 0.36, 0.50), (0.125, 0.36, 0.50), (0.208, 0.36, 0.48), (0.292, 0.36, 0.50), (0.375, 0.36, 0.50), (0.458, 0.36, 0.49),
        (0.542, 0.36, 0.50), (0.625, 0.36, 0.50), (0.708, 0.36, 0.50), (0.792, 0.36, 0.50), (0.875, 0.36, 0.50), (0.958, 0.36, 0.50),
    ].map { Color(hue: $0.0, saturation: $0.1, brightness: $0.2) }

    init(name: String, colorKey: String, customColor: ProjectColor? = nil, mark: AppIcon? = nil, image: String? = nil, imageFolder: String? = nil, working: Bool = false, background: Bool = false, finished: Bool = false) {
        self.name = name
        self.colorKey = colorKey
        self.customColor = customColor
        self.mark = mark
        self.image = image
        self.imageFolder = imageFolder
        self.working = working
        self.background = background
        self.finished = finished
    }

    init(tile: ProjectTile, imageFolder: String? = nil, working: Bool = false, background: Bool = false, finished: Bool = false) {
        self.name = tile.name
        self.colorKey = ""
        self.customColor = if case .named(let color) = tile.color { color } else { nil }
        self.hashedIndex = if case .hashed(let index) = tile.color { index } else { nil }
        self.mark = if case .mark(let icon) = tile.content { icon } else { nil }
        self.image = tile.image
        self.imageFolder = imageFolder
        self.working = working
        self.background = background
        self.finished = finished
    }

    /// The icon of the project whose folder is `base`: what the person set on it, else made from `name` and `colorKey` as it was before projects.
    @MainActor init(base: String, name: String, colorKey: String, working: Bool = false, background: Bool = false, finished: Bool = false) {
        let tile = projectTile(path: base, in: ProjectsModel.shared.rows, fallback: projectTile(name: name, colorKey: colorKey))
        self.init(tile: tile, working: working, background: background, finished: finished)
    }

    /// The icon of an epic's repository `owner/name`: its project's when one has it as its `origin`, else made from `name` and `colorKey` as it was before projects.
    @MainActor init(repo: String, name: String, colorKey: String, working: Bool = false) {
        self.init(tile: projectTile(repo: repo, in: ProjectsModel.shared.rows, fallback: projectTile(name: name, colorKey: colorKey)), working: working)
    }

    private var hashedIndex: Int?

    private var tileColor: Color {
        if let customColor { return customColor.color }
        let index = hashedIndex ?? projectColorIndex(colorKey, count: Self.palette.count)
        return Self.palette[index % Self.palette.count]
    }

    private var loadedImage: NSImage? {
        guard let image else { return nil }
        let store = imageFolder.map(ProjectIconStore.init(folder:)) ?? .current()
        return ProjectIconImageCache.image(named: image, in: store)
    }

    var body: some View {
        Group {
            if let loadedImage {
                Color.clear
                    .frame(width: Self.size, height: Self.size)
                    .glassEffect(.regular, in: .rect(cornerRadius: Self.radius))
                    .overlay {
                        Image(nsImage: loadedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Self.size, height: Self.size)
                            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                            .saturation(active ? 1 : 0)
                            .opacity(active ? 1 : 0.72)
                    }
            } else {
                Color.clear
                    .frame(width: Self.size, height: Self.size)
                    .glassEffect(active ? .regular.tint(tileColor) : .regular, in: .rect(cornerRadius: Self.radius))
                    .overlay {
                        if let mark {
                            Glyph(mark, size: 15, bold: true).foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        } else {
                            let initials = projectInitials(name)
                            Text(initials).font(.scaled(initials.count > 2 ? 10.5 : 12, weight: .semibold)).tracking(initials.count > 2 ? 0 : 0.3)
                                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: active)
        .overlay { if working || finished { WorkingRing(finished: finished && working == false, background: background).transition(.opacity) } }
        .animation(.easeOut(duration: 0.3), value: finished)
    }
}

/// The providers a session has worked with, as their marks (three at most, then "+n"): the provider's letter where there is no mark.
struct ProviderMarks: View {
    let names: [String]
    private static let shown = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(names.prefix(Self.shown), id: \.self) { name in
                AccountMark(account: name, size: 12).help(ProviderIdentityStore.shared.shortName(of: name))
            }
            if names.count > Self.shown { Text("+\(names.count - Self.shown)").font(.scaled(10, weight: .semibold)) }
        }
        .foregroundStyle(.secondary)
    }
}

/// A bright arc that goes round the project icon's edge while the agent works, the one on a run's card in the chat (`GlowEdge`): it fades
/// in along its way and goes once round every few seconds. One Core Animation animation capped at 20 fps, which the render server runs,
/// and stopped under the rule of the rings (a hidden window, Reduce Motion): then the arc stays still, so a working session is told from
/// an idle one without motion.
struct WorkingRing: NSViewRepresentable {
    /// The agent's turn ended: the arc turns green and goes once round, fast, from where it was.
    var finished = false
    /// The arc is cyan while the agent waits for something it started.
    var background = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> WorkingRingHostView {
        let view = WorkingRingHostView(size: ProjectIcon.size, radius: ProjectIcon.radius)
        view.reduceMotion = reduceMotion
        view.background = background
        view.finished = finished
        return view
    }

    func updateNSView(_ view: WorkingRingHostView, context: Context) {
        view.reduceMotion = reduceMotion
        view.background = background
        view.finished = finished
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkingRingHostView, context: Context) -> CGSize? {
        CGSize(width: ProjectIcon.size, height: ProjectIcon.size)
    }
}

final class WorkingRingHostView: NSView {
    private static let key = "turn"
    private static let lineWidth: CGFloat = 2
    /// The arc's tail, head and fade, as the chat draws them, over a clear rest of the circle.
    private static let stops: [(alpha: CGFloat, at: NSNumber)] = [(0, 0), (0, 0.62), (0.95, 0.82), (0.4, 0.92), (0, 1)]
    /// A turn of the arc, in seconds, and the one fast lap when the agent's turn ended.
    private static let period: CFTimeInterval = 3.4
    private static let finishPeriod: CFTimeInterval = 0.9

    /// Clips the turning gradient to the icon's edge.
    private let edge = CALayer()
    private let gradient = CAGradientLayer()
    private var observers: [NSObjectProtocol] = []

    var windowVisible = false { didSet { refresh() } }
    var reduceMotion = false { didSet { refresh() } }
    /// The turn ended: the green lap replaces the turning one, starting where the arc is.
    var finished = false {
        didSet {
            guard finished != oldValue else { return }
            lapStart = gradient.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double ?? 0
            setColor()
            gradient.removeAnimation(forKey: Self.key)
            refresh()
        }
    }
    private var lapStart = 0.0
    /// The arc's cyan, for a session that waits for what it started.
    var background = false { didSet { if background != oldValue { setColor() } } }

    init(size: CGFloat, radius: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        edge.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let stroke = CAShapeLayer()
        stroke.frame = edge.bounds
        stroke.path = CGPath(
            roundedRect: edge.bounds.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2), cornerWidth: radius - Self.lineWidth / 2,
            cornerHeight: radius - Self.lineWidth / 2, transform: nil
        )
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.cgColor
        stroke.lineWidth = Self.lineWidth
        edge.mask = stroke
        // a square bigger than the icon, so its corners never turn into view
        let reach = size * 1.5
        gradient.bounds = CGRect(x: 0, y: 0, width: reach, height: reach)
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = Self.stops.map(\.at)
        edge.addSublayer(gradient)
        layer?.addSublayer(edge)
        place()
        setColor()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func place() {
        edge.position = CGPoint(x: bounds.midX, y: bounds.midY)
        gradient.position = CGPoint(x: edge.bounds.midX, y: edge.bounds.midY)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { windowVisible = false; return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowVisible = window.occlusionState.contains(.visible) }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowVisible = false }
            },
        ]
        windowVisible = window.occlusionState.contains(.visible)
    }

    /// The violet of the chat's glow (`Color.thought`), the same in both appearances; green once the turn ended.
    private func setColor() {
        let violet = (finished ? NSColor(SessionRowView.done) : background ? NSColor(SessionRowView.backgroundWork) : NSColor(Color.thought)).cgColor
        gradient.colors = Self.stops.map { violet.copy(alpha: $0.alpha) as Any }
        // what shows while it does not move: the arc a little past its start, as the chat's does
        gradient.transform = CATransform3DMakeRotation(-.pi * 200 / 180, 0, 0, 1)
    }

    private func refresh() {
        guard ringAnimates(windowVisible: windowVisible, reduceMotion: reduceMotion) else { return gradient.removeAnimation(forKey: Self.key) }
        // idempotent: an animation already attached is left alone, or it would restart each time the view updates
        guard gradient.animation(forKey: Self.key) == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = finished ? lapStart : 0
        turn.toValue = (finished ? lapStart : 0) - 2 * Double.pi
        turn.duration = finished ? Self.finishPeriod : Self.period
        turn.repeatCount = finished ? 1 : .infinity
        turn.timingFunction = CAMediaTimingFunction(name: finished ? .easeOut : .linear)
        // uncapped, the render server recomposes at the display rate (see IconController.bounce)
        turn.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20)
        gradient.add(turn, forKey: Self.key)
    }
}
