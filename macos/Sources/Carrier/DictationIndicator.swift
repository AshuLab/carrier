import AppKit
import CarrierCore
import SwiftUI

/// What the message box shows while it listens: a line outside the box's edge, growing outwards (never into the text), the way the chat's glow goes
/// round a card that thinks (`GlowEdge`): a ring of the accent and two neighbouring hues, and over it a bright arc with a short bloom that always
/// goes round. In silence it goes at the pace of a slow breath; with a voice it goes faster, the line thickens with the voice and trembles with its
/// mids and highs. Reduce Motion stops the turning, the swelling and the tremble (the brightness still follows the voice); Reduce Transparency
/// keeps the ring alone, with no arc and no bloom. It ignores the pointer, has the box's radius (dictation-composer-spec.html, section 3) and exists
/// only while it listens, with its timeline, `fps` frames a second.
struct DictationIndicator: View {
    let levels: VoiceLevels
    /// The message box's own radius (`MessageBox` writes the same 16; keep the two equal).
    var radius: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var motion = IndicatorMotion()

    // ponytail: 60 frames a second is what makes the tremble smooth; the cost is the processor time while it listens, so lower this if Activity Monitor says so
    private static let fps = 60.0

    /// The arc and its bloom are light over the ring; Reduce Transparency keeps the ring alone.
    static func drawsLight(reduceTransparency: Bool) -> Bool { reduceTransparency == false }

    static func accentColors() -> [Color] {
        let accent = NSColor(Color.themeAccent).usingColorSpace(.sRGB) ?? .controlAccentColor
        var (hue, saturation, brightness): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        accent.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return dictationColors(accent: HSB(hue: hue, saturation: saturation, brightness: brightness)).map {
            Color(hue: $0.hue, saturation: $0.saturation, brightness: $0.brightness)
        }
    }

    var body: some View {
        let colors = Self.accentColors()
        // with Reduce Motion nothing goes round, trembles or thickens: the arc stands still and its brightness follows the voice, at a calmer rate
        TimelineView(.animation(minimumInterval: 1 / (reduceMotion ? 30 : Self.fps))) { context in
            let frame = motion.frame(toward: levels, at: context.date, moving: reduceMotion == false)
            let heard = frame.levels
            let voice = Double(heard.overall)
            let tremble = reduceMotion ? 0 : Double(heard.mid + heard.high) / 2 * sin(frame.drift * 6)
            // in silence the line only swells and fades with the breath; a voice thickens it and makes it tremble
            let width = 1.3 + 0.7 * frame.breath * (1 - voice) + (reduceMotion ? 0 : 2.4 * voice) + 0.9 * tremble
            // the line is drawn on a rectangle pushed out by half its width, so all of it is outside the box and the box keeps its whole inside
            let line = RoundedRectangle(cornerRadius: radius + width / 2, style: .continuous)
            let angle = Angle.degrees(reduceMotion ? 200 : frame.spin)
            let light = Self.drawsLight(reduceTransparency: reduceTransparency)
            ZStack {
                // the ring is the glow's dim base; alone (Reduce Transparency) it is the whole cue, so it is nearly opaque and only the voice brightens it
                line.stroke(AngularGradient(colors: colors + [colors[0]], center: .center), lineWidth: width)
                    .opacity(light ? 0.3 + 0.2 * frame.breath * (1 - voice) + 0.3 * voice : 0.8 + 0.2 * voice)
                if light {
                    line.stroke(
                        AngularGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.35), .init(color: colors[2].opacity(0.4), location: 0.6),
                                    .init(color: colors[1].opacity(0.85), location: 0.8), .init(color: colors[0], location: 0.92),
                                    .init(color: colors[0].opacity(0.5), location: 0.97), .init(color: .clear, location: 1)],
                            center: .center, angle: angle
                        ),
                        lineWidth: width
                    )
                    .shadow(color: colors[0].opacity(0.3 + 0.3 * frame.breath * (1 - voice) + 0.4 * voice), radius: 2 + 3 * frame.breath * (1 - voice) + 6 * voice)
                }
            }
            .padding(-width / 2)
            .opacity(light ? 0.55 + 0.3 * frame.breath * (1 - voice) + 0.45 * voice : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the indicator keeps between frames: the follower that smooths the voice, and the angle and the tremble's phase, which only ever advance (so a
/// change of speed never makes them jump). Held in a class because the timeline's closure draws and cannot write to a `@State` value.
final class IndicatorMotion {
    struct Frame {
        var levels: VoiceLevels
        var spin: Double
        var drift: Double
        /// `0...1`, a slow swell about every 4 s that gives the line something to do in silence.
        var breath: Double
    }

    private var follower = VoiceFollower()
    private var last: Date?
    private var spin = 0.0
    private var drift = 0.0

    func frame(toward target: VoiceLevels, at date: Date, moving: Bool) -> Frame {
        let seconds = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        follower.step(toward: target, seconds: seconds)
        let shown = follower.shown
        if moving {
            // almost still in silence (a turn in a minute) and a turn in about 2.3 s at full voice; the tremble keeps time with the mids
            spin += seconds * (6 + 150 * Double(shown.overall))
            drift += seconds * (0.9 + 3.0 * Double(shown.mid))
        }
        let breath = moving ? 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 4.2) : 0.5
        return Frame(levels: shown, spin: spin, drift: drift, breath: breath)
    }
}
