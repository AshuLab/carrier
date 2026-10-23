import AppKit
import CarrierCore
import QuartzCore
import SwiftUI

/// A ring: a faint track and an arc over it. The arc turns with one Core Animation animation, capped at 20 fps, which the
/// render server runs: nothing in the app ticks it, where a SwiftUI repeating animation costs 9% to 12% of a core.
final class RingLayer: CALayer {
    static let spinKey = "spin"

    let track = CAShapeLayer(), arc = CAShapeLayer()

    /// A ring of `diameter` points; the arc turns only when `animate` is true.
    static func make(diameter: CGFloat, lineWidth: CGFloat, color: CGColor, animate: Bool) -> RingLayer {
        let ring = RingLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let path = CGPath(ellipseIn: ring.bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        for layer in [ring.track, ring.arc] {
            layer.frame = ring.bounds
            layer.path = path
            layer.fillColor = nil
            layer.lineWidth = lineWidth
            ring.addSublayer(layer)
        }
        ring.arc.strokeEnd = 0.25
        ring.arc.lineCap = .round
        ring.setColor(color)
        ring.setAnimating(animate)
        return ring
    }

    func setColor(_ color: CGColor) {
        track.strokeColor = color.copy(alpha: 0.25)
        arc.strokeColor = color
    }

    func setAnimating(_ on: Bool) { arc.setSpinning(on) }
}

extension CALayer {
    /// Idempotent: an animation already attached is left alone, or it would restart every time the view updates.
    func setSpinning(_ on: Bool) {
        guard on else { return removeAnimation(forKey: RingLayer.spinKey) }
        guard animation(forKey: RingLayer.spinKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        // uncapped, the render server recomposes at the display rate (see IconController.bounce)
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20)
        add(spin, forKey: RingLayer.spinKey)
    }
}

/// Hosts a RingLayer, or a glyph, and decides whether it turns from the window's visibility and Reduce Motion. The window is kept for the
/// life of the app and ordering it out does not stop animations, so the host watches occlusion and closing itself.
final class RingHostView: NSView {
    private static let live = NSHashTable<RingHostView>.weakObjects()

    /// The layer that turns and the one that is centred: the ring's arc inside its ring, or the glyph itself.
    private let spinner: CALayer, root: CALayer
    private let ring: RingLayer?
    private let tint: NSColor
    private var observers: [NSObjectProtocol] = []

    var windowVisible = false { didSet { refresh() } }
    var reduceMotion = false { didSet { refresh() } }

    init(diameter: CGFloat, lineWidth: CGFloat, color: NSColor) {
        let ring = RingLayer.make(diameter: diameter, lineWidth: lineWidth, color: color.cgColor, animate: false)
        self.ring = ring
        (root, spinner, tint) = (ring, ring.arc, color)
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        setUp(diameter)
    }

    /// A white SF Symbol, `diameter` points square.
    init(symbol: String, diameter: CGFloat) {
        let glyph = CALayer()
        glyph.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        // drawn at twice the size for retina, and white because a layer gets no tint from the system
        let configuration = NSImage.SymbolConfiguration(pointSize: 2 * diameter, weight: .bold).applying(.init(paletteColors: [.white]))
        glyph.contents = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        glyph.contentsGravity = .resizeAspect
        (ring, root, spinner, tint) = (nil, glyph, glyph, .white)
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        setUp(diameter)
    }

    private func setUp(_ diameter: CGFloat) {
        wantsLayer = true
        layer?.addSublayer(root)
        // centred from the start: layout() only runs when the view is resized
        root.position = CGPoint(x: diameter / 2, y: diameter / 2)
        Self.live.add(self)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.position = CGPoint(x: bounds.midX, y: bounds.midY)
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
        // a layer gets no tint from the system, so its colour is resolved again when the appearance changes
        var resolved = tint.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = tint.cgColor }
        ring?.setColor(resolved)
    }

    var animating: Bool { spinner.animation(forKey: RingLayer.spinKey) != nil }

    private func refresh() {
        spinner.setSpinning(ringAnimates(windowVisible: windowVisible, reduceMotion: reduceMotion))
    }

    /// For the self-test: the rings on screen and how many turn.
    @MainActor static var summary: String {
        let rings = live.allObjects.filter { $0.window != nil }
        return "rings=\(rings.count) animating=\(rings.filter(\.animating).count)"
    }
}

struct SpinningRing: NSViewRepresentable {
    var diameter: CGFloat = 16
    var lineWidth: CGFloat = 2.5
    var color: NSColor = .systemGreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> RingHostView {
        let view = RingHostView(diameter: diameter, lineWidth: lineWidth, color: color)
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ view: RingHostView, context: Context) { view.reduceMotion = reduceMotion }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RingHostView, context: Context) -> CGSize? {
        CGSize(width: diameter, height: diameter)
    }
}

/// A glyph that turns by the ring's rule: the same animation, and the same window-visibility and Reduce Motion gating.
struct SpinningGlyph: NSViewRepresentable {
    var symbol: String
    var diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> RingHostView {
        let view = RingHostView(symbol: symbol, diameter: diameter)
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ view: RingHostView, context: Context) { view.reduceMotion = reduceMotion }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RingHostView, context: Context) -> CGSize? {
        CGSize(width: diameter, height: diameter)
    }
}
