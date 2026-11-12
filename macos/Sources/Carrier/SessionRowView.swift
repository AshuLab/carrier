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
    @AppStorage(SidebarStore.showsIconKey) private var showsIcon = true
    @AppStorage(SidebarStore.showsBranchKey) private var showsBranch = true
    @AppStorage(SidebarStore.showsProvidersKey) private var showsProviders = true
    @AppStorage(SidebarStore.showsAgeKey) private var showsAge = true
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15
    /// The orange of "Waiting for you" as text: the system's on dark, a deeper one on light, where the system's is too pale to read.
    static let attention = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.70, green: 0.36, blue: 0, alpha: 1)
    })

    private var content: SessionRowContent {
        SessionRowContent(
            row, showsWorkspace: showsWorkspace,
            parts: SessionRowParts(icon: showsIcon, branch: showsBranch, providers: showsProviders, age: showsAge), now: Date()
        )
    }

    private func place(_ place: SessionPlace) -> Text {
        switch place {
        case .branch(let name): Text("\(Image(systemName: "arrow.triangle.branch")) \(name)")
        case .baseFolder: Text("Base folder")
        }
    }

    @ViewBuilder private func detail(_ content: SessionRowContent) -> some View {
        if row.state == .waiting {
            Text("Waiting for you").fontWeight(.medium).foregroundStyle(Self.attention)
        } else {
            switch (content.workspace, content.place) {
            case (let workspace?, let placed?): Text("\(workspace) · \(place(placed))").foregroundStyle(.secondary)
            case (let workspace?, nil): Text(workspace).foregroundStyle(.secondary)
            case (nil, let placed?): place(placed).foregroundStyle(.secondary)
            case (nil, nil): Text("")
            }
        }
    }

    /// The time at the top right: the age of the last activity, or how long the turn has run while the session works (a stopwatch that
    /// ticks each second, in the colour of the ring).
    @ViewBuilder private func ageOrStopwatch(_ content: SessionRowContent) -> some View {
        if content.age != nil, let since = WorkingClock.shared.since(row) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(workingElapsed(Int(context.date.timeIntervalSince(since)))).foregroundStyle(Color.thought)
            }
        } else {
            Text(content.age ?? "").foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        let content = content
        HStack(spacing: SidebarMetrics.inset) {
            if content.showsIcon {
                ProjectIcon(name: row.workspace, colorKey: projectColorKey(row.base), working: row.state == .working)
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                Text(row.title).font(SidebarMetrics.item).fontWeight(row.state == .waiting ? .medium : .regular)
                    .lineLimit(1).truncationMode(.tail).frame(height: Self.titleLine, alignment: .leading)
                detail(content).font(SidebarMetrics.detail).lineLimit(1).truncationMode(.tail).frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            if content.age != nil || content.providers.isEmpty == false {
                VStack(alignment: .trailing, spacing: SidebarMetrics.lineGap) {
                    ageOrStopwatch(content)
                        .font(SidebarMetrics.detail.monospacedDigit()).lineLimit(1).frame(height: Self.titleLine)
                    ProviderMarks(names: content.providers).frame(height: Self.detailLine)
                }
            }
        }
        .padding(.horizontal, content.showsIcon ? density.rowPadding : SidebarMetrics.inset).padding(.vertical, density.rowPadding)
        .sessionContextMenu(row)
        .hoverCard { SessionPeekView(card: sessionPeek(row, now: Date())) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(content))
    }

    /// What the row says aloud: the title, the state in words (the icon draws it), where it works, the providers and "5 minutes ago",
    /// the parts the person switched off left out.
    private func label(_ content: SessionRowContent) -> String {
        let state: String? = switch row.state {
        case .working: "Working"
        case .waiting: "Needs attention"
        case .idle, .done: nil
        }
        let place: String? = switch content.place {
        case .branch(let name)?: name
        case .baseFolder?: "Base folder"
        case nil: nil
        }
        let age = content.age == nil ? nil : spokenAge(row.updatedAt, now: Date())
        return ([row.title, state, row.workspace, place] + content.providers + [age]).compactMap { $0 }.joined(separator: ", ")
    }
}

extension EnvironmentValues {
    /// Whether the row the view is in is selected or hovered: its project icon wears its colour then and is neutral otherwise. True
    /// outside the sidebar's rows, where the icon is always coloured.
    @Entry var rowActive = true
}

/// The project's icon: its initials in white on a colour that is the same every time (from its name, so a session's folder and an epic's
/// repository that are one project look alike), in a rounded square of glass tinted with it. A bright arc goes round its edge while an agent works (`WorkingRing`).
/// In a sidebar row it is neutral until the row is selected or hovered (`rowActive`).
struct ProjectIcon: View {
    let name: String
    /// What the colour is made from: `projectColorKey` of the folder or the repository.
    let colorKey: String
    var working = false
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

    var body: some View {
        Color.clear
            .frame(width: Self.size, height: Self.size)
            .glassEffect(active ? .regular.tint(Self.palette[projectColorIndex(colorKey, count: Self.palette.count)]) : .regular, in: .rect(cornerRadius: Self.radius))
            .overlay {
                let initials = projectInitials(name)
                Text(initials).font(.scaled(initials.count > 2 ? 10.5 : 12, weight: .semibold)).tracking(initials.count > 2 ? 0 : 0.3)
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            .animation(.easeOut(duration: 0.15), value: active)
            .overlay { if working { WorkingRing() } }
    }
}

/// The providers a session has worked with, as their marks (three at most, then "+n"): the provider's letter where there is no mark.
struct ProviderMarks: View {
    let names: [String]
    private static let shown = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(names.prefix(Self.shown), id: \.self) { name in
                if let image = AgentAvatar.mark(name) {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 12, height: 12)
                } else {
                    Text(String(name.prefix(1)).uppercased()).font(.scaled(10, weight: .bold))
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> WorkingRingHostView {
        let view = WorkingRingHostView(size: ProjectIcon.size, radius: ProjectIcon.radius)
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ view: WorkingRingHostView, context: Context) { view.reduceMotion = reduceMotion }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WorkingRingHostView, context: Context) -> CGSize? {
        CGSize(width: ProjectIcon.size, height: ProjectIcon.size)
    }
}

final class WorkingRingHostView: NSView {
    private static let key = "turn"
    private static let lineWidth: CGFloat = 2
    /// The arc's tail, head and fade, as the chat draws them, over a clear rest of the circle.
    private static let stops: [(alpha: CGFloat, at: NSNumber)] = [(0, 0), (0, 0.62), (0.95, 0.82), (0.4, 0.92), (0, 1)]
    /// A turn of the arc, in seconds.
    private static let period: CFTimeInterval = 3.4

    /// Clips the turning gradient to the icon's edge.
    private let edge = CALayer()
    private let gradient = CAGradientLayer()
    private var observers: [NSObjectProtocol] = []

    var windowVisible = false { didSet { refresh() } }
    var reduceMotion = false { didSet { refresh() } }

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

    /// The violet of the chat's glow (`Color.thought`), the same in both appearances.
    private func setColor() {
        let violet = NSColor(Color.thought).cgColor
        gradient.colors = Self.stops.map { violet.copy(alpha: $0.alpha) as Any }
        // what shows while it does not move: the arc a little past its start, as the chat's does
        gradient.transform = CATransform3DMakeRotation(-.pi * 200 / 180, 0, 0, 1)
    }

    private func refresh() {
        guard ringAnimates(windowVisible: windowVisible, reduceMotion: reduceMotion) else { return gradient.removeAnimation(forKey: Self.key) }
        // idempotent: an animation already attached is left alone, or it would restart each time the view updates
        guard gradient.animation(forKey: Self.key) == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * Double.pi
        turn.duration = Self.period
        turn.repeatCount = .infinity
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        // uncapped, the render server recomposes at the display rate (see IconController.bounce)
        turn.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20)
        gradient.add(turn, forKey: Self.key)
    }
}
