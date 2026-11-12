import AppKit
import CarrierCore
import SwiftUI

/// What the message box shows while it listens, in three layers over its glass and under its text, all ignoring the pointer and with the
/// box's own radius (dictation-composer-spec.html, section 3): the edge, a halo just inside it and a light that drifts in from the edges.
/// It exists only while it listens, and its timeline, 30 frames a second, with it.
struct DictationIndicator: View {
    let level: Float
    var radius: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var colors: [Color] {
        let accent = NSColor(Color.themeAccent).usingColorSpace(.sRGB) ?? .controlAccentColor
        var (hue, saturation, brightness): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        accent.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return dictationColors(accent: HSB(hue: hue, saturation: saturation, brightness: brightness)).map {
            Color(hue: $0.hue, saturation: $0.saturation, brightness: $0.brightness)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let colors = colors
        let edge = dictationEdgeOpacity(level: level)
        // with Reduce Motion nothing turns or drifts: the timeline stops and the level still sets the brightness
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(time * 50))
            ZStack {
                if reduceTransparency == false {
                    ZStack {
                        light(colors, time: time).opacity(dictationLightOpacity(level: level)).mask { lightMask(shape) }
                        shape.strokeBorder(gradient, lineWidth: 7).blur(radius: 8).opacity(edge / 2)
                    }
                    .drawingGroup()
                    .clipShape(shape)
                }
                shape.strokeBorder(gradient, lineWidth: 1.5).opacity(edge)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A 3 x 3 mesh of the three colors whose inner points drift with the clock.
    private func light(_ colors: [Color], time: Double) -> some View {
        func drift(_ phase: Double) -> (Float, Float) { (Float(0.12 * sin(time * 0.6 + phase)), Float(0.12 * cos(time * 0.5 + phase))) }
        let (d1, d2, d3, d4, d5) = (drift(0).0, drift(1).1, drift(2), drift(3).0, drift(4).1)
        // the corners stay; the middle of each edge slides along it and the center wanders
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + d1, 0], [1, 0],
            [0, 0.5 + d2], [0.5 + d3.0, 0.5 + d3.1], [1, 0.5 + d5],
            [0, 1], [0.5 + d4, 1], [1, 1],
        ]
        let (a, b, c) = (colors[0], colors[1], colors[2])
        return MeshGradient(width: 3, height: 3, points: points, colors: [a, b, c, c, a, b, b, c, a])
    }

    /// Strongest toward the edges and a quarter as strong in the middle, where the text is.
    private func lightMask(_ shape: RoundedRectangle) -> some View {
        ZStack {
            Color.white.opacity(0.25)
            shape.strokeBorder(.white, lineWidth: 36).blur(radius: 18)
        }
    }
}
