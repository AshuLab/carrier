import AppKit
import CarrierCore
import QuartzCore
import SwiftUI

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
        let violet = (finished ? NSColor(Color.sessionDone) : background ? NSColor(Color.backgroundWork) : NSColor(Color.thought)).cgColor
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
