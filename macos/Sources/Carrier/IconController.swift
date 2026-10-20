import AppKit
import CarrierCore
import QuartzCore

/// Holds the icon's layers. It takes no clicks: the button underneath has to receive them to open the menu.
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Draws the status item with Core Animation layers on its button, never a swapped image: swapping costs CPU and resets an
/// open menu. Count, track, fill and the orange dot, and while epics run a short segment bouncing over the unfilled part: one
/// Core Animation animation on its layer, capped at 20 fps, so the app has no timer and draws nothing per frame. Main thread only.
final class IconController {
    /// Where the app reaches the icon from: the status item lives as long as the app does.
    static var shared: IconController?

    static func install(on item: NSStatusItem) {
        shared = IconController(item: item)
    }

    private let item: NSStatusItem
    let host = PassthroughView()
    private let text = CATextLayer(), track = CALayer(), fill = CALayer(), segment = CALayer(), badge = CALayer()
    private var state = IconState()
    /// How far the attached animation travels; the animation is only replaced when this changes, or it would restart every second.
    private var attachedTravel: Double?
    private var appearanceWatch: NSKeyValueObservation?

    private let trackWidth: CGFloat = 18
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    private init(item: NSStatusItem) {
        self.item = item
        host.wantsLayer = true
        track.masksToBounds = true
        track.cornerRadius = 2.5
        track.addSublayer(fill)
        track.addSublayer(segment)
        segment.cornerRadius = IconState.segmentLength / 2
        for layer in [text, track, badge] { host.layer?.addSublayer(layer) }
        item.button?.addSubview(host)
        // a layer gets no tint from the system, so its colours are resolved again whenever the button's appearance changes
        appearanceWatch = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.draw() }
        }
        draw()
    }

    func show(_ connection: ConnectionState) {
        state = IconState(connection)
        draw()
    }

    /// One line for the self-test log.
    var summary: String {
        "connected=\(state.connected) working=\(state.working) bar=\(state.done)/\(state.total) attention=\(state.attention) width=\(item.length) segment=\(attachedTravel.map { "travel \($0)" } ?? "none")"
    }

    private func color(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        (item.button?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

    private func draw() {
        let thick = NSStatusBar.system.thickness
        let label: String? = state.connected && state.working > 0 ? "\(state.working)" : nil
        let labelWidth = label.map { ceil(NSAttributedString(string: $0, attributes: [.font: font]).size().width) } ?? 0
        let width = 4 + (label == nil ? 0 : labelWidth + 3) + trackWidth + 4 + (state.attention > 0 ? 5 : 0)
        var x: CGFloat = 4

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        item.length = width
        host.frame = NSRect(x: 0, y: 0, width: width, height: thick)
        // stopped is the same icon faded
        host.layer?.opacity = state.connected ? 1 : 0.4

        text.isHidden = label == nil
        if let label {
            text.string = label
            text.font = font
            text.fontSize = 12
            text.foregroundColor = color(.labelColor)
            text.contentsScale = item.button?.window?.backingScaleFactor ?? 2
            text.frame = NSRect(x: x, y: (thick - 15) / 2, width: labelWidth + 1, height: 15)
            x += labelWidth + 3
        }

        track.frame = NSRect(x: x, y: (thick - 5) / 2, width: trackWidth, height: 5)
        track.backgroundColor = color(NSColor.labelColor.withAlphaComponent(0.3))
        fill.frame = NSRect(x: 0, y: 0, width: trackWidth * state.fraction, height: 5)
        fill.backgroundColor = color(.labelColor)

        let travel = state.segmentTravel(trackWidth: Double(trackWidth))
        segment.isHidden = travel == nil
        segment.frame = NSRect(x: fill.frame.width, y: 0, width: IconState.segmentLength, height: 5)
        segment.backgroundColor = color(.labelColor)
        if travel != attachedTravel {
            Self.bounce(segment, travel: travel)
            attachedTravel = travel
        }

        // on top of any state
        badge.isHidden = state.attention == 0
        badge.frame = NSRect(x: width - 8, y: thick - 9, width: 6, height: 6)
        badge.cornerRadius = 3
        badge.backgroundColor = color(.systemOrange)
        CATransaction.commit()
    }

    /// Replaces whatever moves the layer: a bounce over `travel` points, or nothing for nil.
    static func bounce(_ layer: CALayer, travel: Double?) {
        layer.removeAllAnimations()
        guard let travel else { return }
        let bounce = CABasicAnimation(keyPath: "transform.translation.x")
        bounce.fromValue = 0
        bounce.toValue = travel
        bounce.duration = 0.7
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // uncapped, the render server recomposes the translucent menu bar at the display rate and WindowServer goes from ~8% to ~55%
        bounce.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20)
        layer.add(bounce, forKey: "bounce")
    }
}
