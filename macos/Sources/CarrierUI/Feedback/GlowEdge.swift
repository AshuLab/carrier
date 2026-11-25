import CarrierCore
import SwiftUI

/// The glow on the card's edge. Working, a bright arc goes round once every few seconds. Waiting for the person, it does not go anywhere: the
/// whole edge is lit and breathes, as a light that waits. Without `moves` it is still: the arc, or the edge half lit.
public struct GlowEdge: View {
    let color: Color
    let waiting: Bool
    let moves: Bool
    /// The card's corners; the update pill passes half its height, a capsule.
    var cornerRadius: CGFloat = Tokens.Radius.card

    public init(
        color: Color,
        waiting: Bool,
        moves: Bool,
        cornerRadius: CGFloat = Tokens.Radius.card
    ) {
        self.color = color
        self.waiting = waiting
        self.moves = moves
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if moves {
            MovingTimeline { context in
                let now = context.date.timeIntervalSinceReferenceDate
                if waiting { breathing(0.5 + 0.5 * sin(now * 2 * .pi / 1.8)) } else { arc(now.truncatingRemainder(dividingBy: 3.4) / 3.4 * 360) }
            }
        } else if waiting {
            breathing(0.6)
        } else {
            arc(200)
        }
    }

    /// `level` from 0 to 1: how lit the edge is.
    private func breathing(_ level: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(color.opacity(0.25 + 0.65 * level), lineWidth: 1.2)
            .shadow(color: color.opacity(0.35 * level), radius: 6)
    }

    private func arc(_ degrees: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(
            AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.62), .init(color: color.opacity(0.95), location: 0.82),
                                    .init(color: color.opacity(0.4), location: 0.92), .init(color: .clear, location: 1)], center: .center, angle: .degrees(degrees)),
            lineWidth: 1.2
        )
    }
}

