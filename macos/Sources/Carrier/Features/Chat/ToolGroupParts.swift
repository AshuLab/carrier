import CarrierCore
import SwiftUI

/// Opens or folds a step. The change is animated here, where it is made, and not by an `.animation` on the card: the feed is a lazy stack,
/// which only moves what is under a card smoothly when the whole update is in the transaction; with the animation on the card alone the
/// card faded while everything under it jumped to its place in one frame.
func flip(_ key: String, in flipped: Binding<Set<String>>) {
    let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.35)
    withAnimation(animation) {
        if flipped.wrappedValue.insert(key).inserted == false { flipped.wrappedValue.remove(key) }
    }
}

// MARK: parts

/// How the steps open: the card grows from its line and the steps stay where they are, uncovered from the top as it grows (clipped at
/// the bottom edge), instead of sliding in from above over the line.
struct RevealLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        content.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

struct Reveal: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        // the steps fade ahead of the height (squared): folding, they are gone before the card closes over them, and opening, they come in
        // once there is room for them, so a cut-off row is never seen
        RevealLayout(progress: progress) { content }.clipped().opacity(progress * progress)
    }
}

extension AnyTransition {
    static var reveal: AnyTransition { .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)) }
}

/// The lead of the line: what the agent is doing, or how the run ended.
struct LeadView: View {
    let lead: ChatToolGroupView.Lead
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch lead {
            case .spark: Twinkle(reduceMotion: reduceMotion)
            case .ring: SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor)
            case .waiting: Circle().fill(Color.attention).frame(width: 8, height: 8).shadow(color: Color.attention.opacity(0.6), radius: 3)
            case .done: DoneMark()
            case .stopped: Glyph(.stopFilled, size: 8).foregroundStyle(.secondary)
            case .failed: StateMark(shape: .problem, size: 12).foregroundStyle(.red)
            case .none: EmptyView()
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// The spark of thinking: it turns a little and dims, slowly.
struct Twinkle: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            spark(0, 1)
        } else {
            MovingTimeline { context in
                let t = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.4
                spark(sin(t) * 18, 0.75 + 0.25 * cos(t))
            }
        }
    }

    private func spark(_ degrees: Double, _ opacity: Double) -> some View {
        Glyph(.sparkles, size: 11).foregroundStyle(Color.thought).rotationEffect(.degrees(degrees)).opacity(opacity)
    }
}

/// The tick a run leaves when it ends: it bounces once.
struct DoneMark: View {
    @State private var ticks = 0

    var body: some View {
        Glyph(.checkCircleFilled, size: 12).foregroundStyle(.green)
            .glyphKick(ticks)
            .onAppear { ticks += 1 }
    }
}

extension Color {
    /// The timer of a slow call: the system's amber on dark, a deeper one on light, where the system's is too pale to read.
    static let slowCall = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.70, green: 0.36, blue: 0, alpha: 1)
    })
}
