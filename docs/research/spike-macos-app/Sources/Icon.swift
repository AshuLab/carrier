import AppKit

enum IconVariant: String, CaseIterable, Identifiable {
    case ring, bar, number
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ring: return "Ring + count"
        case .bar: return "Count + bar"
        case .number: return "Number in a box"
        }
    }
}

enum IconMotion: String, CaseIterable, Identifiable {
    case none, sweep, stripes, bounce
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "No motion"
        case .sweep: return "Shine sweep"
        case .stripes: return "Marching stripes"
        case .bounce: return "Bouncing segment"
        }
    }
}

struct IconState: Equatable {
    var connected: Bool
    var working: Int      // epics running
    var done: Int         // slices closed across the running epics
    var total: Int        // slices across the running epics
    var attention: Int    // epics needing the person, or a problem
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// Draws the menu bar icon. `fg == nil` means "live in the menu bar": a template image when nothing needs attention,
/// otherwise a coloured one that uses labelColor (resolved at draw time). `phase` (0..<1) drives the bar's motion.
func iconImage(_ v: IconVariant, _ s: IconState, fg: NSColor?, phase: Double = 0, motion: IconMotion = .none) -> NSImage {
    let h: CGFloat = 18
    let label: String? = (s.connected && s.working > 0) ? "\(s.working)" : nil
    let template = fg == nil && s.attention == 0
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    let textSize = label.map { NSAttributedString(string: $0, attributes: [.font: font]).size() } ?? .zero
    let glyphW: CGFloat = v == .ring ? 14 : 18
    var w: CGFloat = 2 + glyphW + 2
    if label != nil, v != .number { w += 3 + ceil(textSize.width) }
    if s.attention > 0 { w += 5 }

    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let base: NSColor = template ? .black : (fg ?? .labelColor)
        let main = base.withAlphaComponent(s.connected ? 1 : 0.4)
        let track = base.withAlphaComponent(s.connected ? 0.3 : 0.2)
        func text(_ t: String, at p: NSPoint, size: CGFloat = 12) {
            let f = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            let a = NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: main])
            a.draw(at: NSPoint(x: p.x, y: p.y - a.size().height / 2))
        }
        var x: CGFloat = 2
        switch v {
        case .ring:
            let r = NSRect(x: x + 1, y: (h - 12) / 2, width: 12, height: 12)
            let t = NSBezierPath(ovalIn: r); t.lineWidth = 2; track.setStroke(); t.stroke()
            let c = NSPoint(x: r.midX, y: r.midY)
            if s.connected && s.working > 0 {
                let f = max(s.fraction, 0.06)
                let p = NSBezierPath()
                if f >= 0.999 { p.appendOval(in: r) } else {
                    p.appendArc(withCenter: c, radius: 6, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                }
                p.lineWidth = 2; p.lineCapStyle = .round; main.setStroke(); p.stroke()
            } else if s.connected {
                main.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
            }
            x += 14 + 3
            if let l = label { text(l, at: NSPoint(x: x, y: h / 2)) }
        case .bar:
            if let l = label { text(l, at: NSPoint(x: x, y: h / 2)); x += ceil(textSize.width) + 3 }
            let r = NSRect(x: x, y: (h - 5) / 2, width: 18, height: 5)
            track.setFill(); NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5).fill()
            if s.connected && s.working > 0 {
                let fw = max(5, r.width * CGFloat(s.fraction))
                let fillRect = NSRect(x: r.minX, y: r.minY, width: fw, height: 5)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5).addClip()
                switch motion {
                case .none:
                    main.setFill(); fillRect.fill()
                case .sweep:
                    base.withAlphaComponent(0.55).setFill(); fillRect.fill()
                    NSBezierPath(rect: fillRect).addClip()
                    let cx = r.minX - 5 + CGFloat(phase) * (fw + 10)
                    NSGradient(colors: [main.withAlphaComponent(0), main, main.withAlphaComponent(0)])?
                        .draw(in: NSRect(x: cx - 5, y: r.minY, width: 10, height: 5), angle: 0)
                case .stripes:
                    base.withAlphaComponent(0.6).setFill(); fillRect.fill()
                    NSBezierPath(rect: fillRect).addClip()
                    main.setStroke()
                    let p = NSBezierPath(); p.lineWidth = 1.6
                    var sx = r.minX - 8 + CGFloat(phase) * 4
                    while sx < r.maxX + 8 { p.move(to: NSPoint(x: sx, y: r.minY - 1)); p.line(to: NSPoint(x: sx + 6, y: r.maxY + 1)); sx += 4 }
                    p.stroke()
                case .bounce:
                    main.setFill(); fillRect.fill()
                    let room = r.maxX - fillRect.maxX
                    if room > 4 {
                        let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2     // ping-pong 0...1...0
                        let sx = fillRect.maxX + CGFloat(t) * (room - 4)
                        main.withAlphaComponent(0.85).setFill()
                        NSBezierPath(roundedRect: NSRect(x: sx, y: r.minY, width: 4, height: 5), xRadius: 2, yRadius: 2).fill()
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        case .number:
            let r = NSRect(x: x, y: (h - 14) / 2, width: 18, height: 14).insetBy(dx: 0.75, dy: 0.75)
            let b = NSBezierPath(roundedRect: r, xRadius: 3.5, yRadius: 3.5); b.lineWidth = 1.5; main.setStroke(); b.stroke()
            let t = label ?? (s.connected ? "·" : "–")
            let sz = NSAttributedString(string: t, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)]).size()
            text(t, at: NSPoint(x: r.midX - sz.width / 2, y: h / 2), size: 11)
        }
        if s.attention > 0 {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: w - 7, y: h - 8, width: 6, height: 6)).fill()
        }
        return true
    }
    img.isTemplate = template
    return img
}

/// Rasterises an icon once into a bitmap (2x), so showing it again costs a pointer swap, not a redraw.
func bake(_ img: NSImage) -> NSImage {
    let s = img.size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width * 2), pixelsHigh: Int(s.height * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return img }
    rep.size = s
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(origin: .zero, size: s))
    NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: s); out.addRepresentation(rep); out.isTemplate = img.isTemplate
    return out
}

let frameCount = 15
nonisolated(unsafe) var frameCache: [String: NSImage] = [:]
func cachedIcon(_ v: IconVariant, _ s: IconState, phase: Double, motion: IconMotion) -> NSImage {
    let i = Int((phase * Double(frameCount)).rounded()) % frameCount
    let key = "\(v.rawValue)|\(s.connected)|\(s.working)|\(s.done)|\(s.total)|\(s.attention)|\(motion.rawValue)|\(i)"
    if let hit = frameCache[key] { return hit }
    let img = bake(iconImage(v, s, fg: nil, phase: Double(i) / Double(frameCount), motion: motion))
    frameCache[key] = img
    return img
}
