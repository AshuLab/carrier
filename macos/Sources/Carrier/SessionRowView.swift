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
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15
    /// The orange of "Waiting for you" as text: the system's on dark, a deeper one on light, where the system's is too pale to read.
    static let attention = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.70, green: 0.36, blue: 0, alpha: 1)
    })

    private var place: Text {
        row.branch.map { Text("\(Image(systemName: "arrow.triangle.branch")) \($0)") } ?? Text("Base folder")
    }

    @ViewBuilder private var detail: some View {
        if row.state == .waiting {
            Text("Waiting for you").fontWeight(.medium).foregroundStyle(Self.attention)
        } else {
            (showsWorkspace ? Text("\(row.workspace) · \(place)") : place).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ProjectIcon(
                name: row.workspace, colorKey: projectColorKey(row.base), halo: row.state == .working,
                mark: row.state == .waiting ? .init(text: "!", color: .orange) : nil
            )
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                Text(row.title).font(SidebarMetrics.item).fontWeight(row.state == .waiting ? .medium : .regular)
                    .lineLimit(1).truncationMode(.tail).frame(height: Self.titleLine, alignment: .leading)
                detail.font(SidebarMetrics.detail).lineLimit(1).truncationMode(.tail).frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: SidebarMetrics.lineGap) {
                Text(timeText(row.updatedAt, now: Date())).font(SidebarMetrics.detail.monospacedDigit()).foregroundStyle(.tertiary)
                    .lineLimit(1).frame(height: Self.titleLine)
                ProviderMarks(names: row.providers).frame(height: Self.detailLine)
            }
        }
        .padding(.horizontal, SidebarMetrics.inset).padding(.vertical, SidebarMetrics.itemPadding)
        .contextMenu { SessionMenuItems(row: row) }
        .help(row.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// What the row says aloud: the title, the state in words (the icon draws it), where it works, the providers and "5 minutes ago".
    private var label: String {
        let state: String? = switch row.state {
        case .working: "Working"
        case .waiting: "Needs attention"
        case .idle, .done: nil
        }
        let age = spokenAge(row.updatedAt, now: Date())
        return ([row.title, state, row.workspace, row.branch ?? "Base folder"] + row.providers + [age]).compactMap { $0 }.joined(separator: ", ")
    }
}

/// The project's icon: its initials in white on a colour that is the same every time (from its name, so a session's folder and an epic's
/// repository that are one project look alike), in a rounded square. The state is on it: a halo that breathes around it while an agent works
/// and a mark on its corner when there is something to say.
struct ProjectIcon: View {
    /// A mark on the corner: a letter or symbol on a disc.
    struct Mark: Equatable {
        var text: String
        var color: Color
    }

    let name: String
    /// What the colour is made from: `projectColorKey` of the folder or the repository.
    let colorKey: String
    var halo = false
    var mark: Mark?
    static let size: CGFloat = 32
    static let radius: CGFloat = 9
    /// Mid tones, each at least 4.5:1 against the white of the letters.
    static let palette: [Color] = [
        Color(red: 0.48, green: 0.31, blue: 0.77), Color(red: 0.07, green: 0.50, blue: 0.60), Color(red: 0.72, green: 0.38, blue: 0.12),
        Color(red: 0.14, green: 0.47, blue: 0.29), Color(red: 0.72, green: 0.25, blue: 0.44), Color(red: 0.25, green: 0.44, blue: 0.82),
        Color(red: 0.48, green: 0.42, blue: 0.07), Color(red: 0.36, green: 0.42, blue: 0.50),
    ]

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(Self.palette[projectColorIndex(colorKey, count: Self.palette.count)])
            .frame(width: Self.size, height: Self.size)
            .overlay { Text(projectInitials(name)).font(.scaled(12, weight: .semibold)).tracking(0.3).foregroundStyle(.white) }
            .overlay { if halo { SessionHalo() } }
            .overlay(alignment: .bottomTrailing) {
                if let mark {
                    Text(mark.text).font(.scaled(10, weight: .heavy)).foregroundStyle(.white).frame(width: 15, height: 15)
                        .background(Circle().fill(mark.color))
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
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
