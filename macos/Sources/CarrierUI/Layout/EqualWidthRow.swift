import SwiftUI

/// Lays its children side by side, each as wide as the widest, none apart.
public struct EqualWidthRow: Layout {

    public init() {}
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count), height: sizes.map(\.height).max() ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.isEmpty == false else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + width * CGFloat(index), y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
