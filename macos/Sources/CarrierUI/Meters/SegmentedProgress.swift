import CarrierCore
import SwiftUI

/// A progress bar of separate segments, one for each step: the ones done are green. Past 20 steps it stays at 20 segments, or
/// they would be too thin to tell apart.
public struct SegmentedProgress: View {
    let done: Int
    let total: Int
    var tint: Color = .green

    public init(done: Int, total: Int, tint: Color = .green) { self.done = done; self.total = total; self.tint = tint }

    public var body: some View {
        let count = max(1, min(total, 20))
        let filled = total > 20 ? Int((Double(done) / Double(total) * 20).rounded()) : done
        HStack(spacing: Tokens.Space.s3) {
            ForEach(0..<count, id: \.self) { index in
                Capsule().fill(index < filled ? tint : Color.secondary.opacity(0.25)).frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Copy.pieceProgress(done: done, total: total))
    }
}
