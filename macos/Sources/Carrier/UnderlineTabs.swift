import SwiftUI

/// A row of tabs with no box: the words, a hairline across and a line under the chosen one that slides to the next. The quiet
/// tabs of the app: the epic's two, the inspector's three, Settings' four and the sidebar's grouping.
struct UnderlineTabs<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
        /// An SF Symbol before the title.
        var icon: String?
        var count: String?
        var countColor: Color = .secondary
    }

    let items: [Item]
    @Binding var selection: ID
    /// Spread the tabs over the whole width instead of hugging their labels.
    var fill = false
    @Namespace private var line

    var body: some View {
        HStack(spacing: fill ? 0 : 18) {
            ForEach(items) { item in
                let chosen = item.id == selection
                Button { withAnimation(.smooth(duration: 0.22)) { selection = item.id } } label: {
                    HStack(spacing: 5) {
                        if let icon = item.icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                        Text(item.title).fontWeight(chosen ? .semibold : .regular)
                        if let count = item.count { Text(count).foregroundStyle(item.countColor) }
                    }
                    .font(.subheadline).lineLimit(1)
                    .foregroundStyle(chosen ? Color.primary : .secondary)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .padding(.top, 5).padding(.bottom, 8)
                    .overlay(alignment: .bottom) {
                        if chosen { Capsule().fill(.primary).frame(height: 2).matchedGeometryEffect(id: "line", in: line).offset(y: 1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .frame(maxWidth: fill ? .infinity : nil)
        .fixedSize(horizontal: !fill, vertical: true)
    }
}
