import SwiftUI

/// A light that sweeps over the text it is on, in the primary colour over the secondary one the text has.
public struct Shimmer: ViewModifier {
    let active: Bool

    public init(active: Bool) { self.active = active }

    public func body(content: Content) -> some View {
        content.overlay {
            if active {
                MovingTimeline { context in
                    let p = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)) / 2.2 * 1.6 - 0.3
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .primary, location: 0.5), .init(color: .clear, location: 1)],
                                   startPoint: UnitPoint(x: p - 0.25, y: 0.5), endPoint: UnitPoint(x: p + 0.25, y: 0.5))
                }
                .mask(content)
            }
        }
    }
}
