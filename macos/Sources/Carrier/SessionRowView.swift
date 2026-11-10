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

    var body: some View {
        let content = content
        HStack(spacing: SidebarMetrics.inset) {
            if content.showsIcon {
                ProjectIcon(
                    name: row.workspace, colorKey: projectColorKey(row.base), halo: row.state == .working,
                    mark: .session(row.state)
                )
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                Text(row.title).font(SidebarMetrics.item).fontWeight(row.state == .waiting ? .medium : .regular)
                    .lineLimit(1).truncationMode(.tail).frame(height: Self.titleLine, alignment: .leading)
                detail(content).font(SidebarMetrics.detail).lineLimit(1).truncationMode(.tail).frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            if content.age != nil || content.providers.isEmpty == false {
                VStack(alignment: .trailing, spacing: SidebarMetrics.lineGap) {
                    Text(content.age ?? "").font(SidebarMetrics.detail.monospacedDigit()).foregroundStyle(.tertiary)
                        .lineLimit(1).frame(height: Self.titleLine)
                    ProviderMarks(names: content.providers).frame(height: Self.detailLine)
                }
            }
        }
        .padding(.horizontal, content.showsIcon ? density.rowPadding : SidebarMetrics.inset).padding(.vertical, density.rowPadding)
        .sessionContextMenu(row)
        .help(row.title)
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
/// repository that are one project look alike), in a rounded square of glass tinted with it. The state is on it: a halo that breathes around
/// it while an agent works and a mark on its corner when there is something to say. In a sidebar row it is neutral until the row is
/// selected or hovered (`rowActive`).
struct ProjectIcon: View {
    /// A mark on the corner: a letter or symbol on a disc.
    struct Mark: Equatable {
        var text: String
        var color: Color
        var shape: StateShape?
    }

    let name: String
    /// What the colour is made from: `projectColorKey` of the folder or the repository.
    let colorKey: String
    var halo = false
    var mark: Mark?
    @AppStorage(AppPreferences.statesByShapeKey) private var byShape = false
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
                Text(projectInitials(name)).font(.scaled(12, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            .animation(.easeOut(duration: 0.15), value: active)
            .overlay { if halo { SessionHalo() } }
            .overlay(alignment: .bottomTrailing) {
                if let mark, byShape || mark.text.isEmpty == false {
                    StateMark(text: mark.text, shape: mark.shape, size: 10).foregroundStyle(.white).frame(width: 15, height: 15)
                        .background(Circle().fill(mark.color))
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
    }
}

extension ProjectIcon.Mark {
    /// What a session's state wears on its icon: a "!" while it waits for the person, and while it works a mark only when the states are told
    /// apart by shape (the halo around the icon says it otherwise).
    static func session(_ state: SessionState) -> ProjectIcon.Mark? {
        switch state {
        case .waiting: .init(text: "!", color: .orange, shape: .needsAttention)
        case .working: .init(text: "", color: .blue, shape: .working)
        case .idle, .done: nil
        }
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

/// A ring that swells around the project's icon and fades, again and again, while the agent works. One Core Animation animation capped
/// at 20 fps, which the render server runs, and stopped under the rule of the rings (a hidden window, Reduce Motion): then the ring stays
/// still and faint, so a working session is told from an idle one without motion.
struct SessionHalo: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> HaloHostView {
        let view = HaloHostView(size: ProjectIcon.size, radius: ProjectIcon.radius)
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ view: HaloHostView, context: Context) { view.reduceMotion = reduceMotion }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HaloHostView, context: Context) -> CGSize? {
        CGSize(width: ProjectIcon.size, height: ProjectIcon.size)
    }
}

final class HaloHostView: NSView {
    private static let key = "halo"
    private let ring = CAShapeLayer()
    private var observers: [NSObjectProtocol] = []

    var windowVisible = false { didSet { refresh() } }
    var reduceMotion = false { didSet { refresh() } }

    init(size: CGFloat, radius: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.path = CGPath(roundedRect: ring.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.position = CGPoint(x: size / 2, y: size / 2)
        // what shows while it does not move
        ring.opacity = 0.55
        ring.transform = CATransform3DMakeScale(1.12, 1.12, 1)
        layer?.addSublayer(ring)
        setColor()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        setColor()
    }

    /// A layer gets no tint from the system, so the colour is resolved for the appearance.
    private func setColor() {
        var resolved = NSColor.systemBlue.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = NSColor.systemBlue.cgColor }
        ring.strokeColor = resolved
    }

    private func refresh() {
        guard ringAnimates(windowVisible: windowVisible, reduceMotion: reduceMotion) else { return ring.removeAnimation(forKey: Self.key) }
        // idempotent: an animation already attached is left alone, or it would restart each time the view updates
        guard ring.animation(forKey: Self.key) == nil else { return }
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 1
        swell.toValue = 1.32
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let breath = CAAnimationGroup()
        breath.animations = [swell, fade]
        breath.duration = 1.8
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // uncapped, the render server recomposes at the display rate (see IconController.bounce)
        breath.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20)
        ring.add(breath, forKey: Self.key)
    }
}
