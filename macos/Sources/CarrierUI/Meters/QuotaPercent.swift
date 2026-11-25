import SwiftUI

/// The percent of a quota: bold, and orange where the bar is.
public struct QuotaPercent: View {
    /// The share used, from 0 to 1.
    let used: Double

    public init(used: Double) { self.used = used }

    public var body: some View {
        Text("\(Int((used * 100).rounded()))%").scaledFont(11, weight: .semibold).monospacedDigit()
            .foregroundStyle(used >= 0.9 ? Color.orange : Color.primary)
    }
}
