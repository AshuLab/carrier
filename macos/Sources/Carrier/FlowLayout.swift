import SwiftUI

/// Places its views in a row and starts a new row when the next one does not fit: for chips of different widths. Views of different
/// heights share the middle of their row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(bounds.width, subviews).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var (x, y, rowHeight, widest) = (CGFloat.zero, CGFloat.zero, CGFloat.zero, CGFloat.zero)
        var row = 0..<0
        // the views of a finished row sit in its middle, once the tallest of them is known
        func centre() {
            for index in row { frames[index].origin.y += (rowHeight - frames[index].height) / 2 }
        }
        for subview in subviews {
            // proposed the row's width, so a view wider than the row (a long label) cuts itself instead of widening the layout
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                centre()
                (x, y, rowHeight) = (0, y + rowHeight + spacing, 0)
                row = frames.count..<frames.count
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            row = row.lowerBound..<frames.count
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        centre()
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}
