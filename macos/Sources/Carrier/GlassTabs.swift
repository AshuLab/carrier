import SwiftUI

/// A row of tabs on Liquid Glass: one glass capsule holds the segments and the chosen one is a lighter pill that slides to the
/// next. It replaces the system segmented picker, which draws flat inside a window and cannot colour a segment's count.
struct GlassTabs<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
        var count: String?
        var countColor: Color = .secondary
    }

    let items: [Item]
    @Binding var selection: ID
    /// Spread the segments over the whole width instead of hugging their labels.
    var fill = false
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let chosen = item.id == selection
                Button { withAnimation(.smooth(duration: 0.22)) { selection = item.id } } label: {
                    HStack(spacing: 5) {
                        Text(item.title).fontWeight(chosen ? .semibold : .regular)
                        if let count = item.count { Text(count).foregroundStyle(item.countColor) }
                    }
                    .font(.callout).lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background { if chosen { Capsule().fill(.primary.opacity(0.14)).matchedGeometryEffect(id: "pill", in: pill) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: !fill, vertical: true)
    }
}
