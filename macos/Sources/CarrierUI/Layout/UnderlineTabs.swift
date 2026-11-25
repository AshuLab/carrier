import CarrierCore
import SwiftUI

/// A row of tabs with no box: the words, a hairline across and a line under the chosen one that slides to the next. The quiet
/// tabs of the app: the epic's two, the inspector's three, Settings' four and the sidebar's grouping.
public struct UnderlineTabs<ID: Hashable>: View {
    public struct Item: Identifiable {
        public let id: ID
        let title: String
        /// An icon before the title.
        var icon: AppIcon?
        var count: String?
        var countColor: Color = .secondary

        public init(id: ID, title: String, icon: AppIcon? = nil, count: String? = nil, countColor: Color = .secondary) {
            self.id = id
            self.title = title
            self.icon = icon
            self.count = count
            self.countColor = countColor
        }
    }

    let items: [Item]
    @Binding var selection: ID
    /// Spread the tabs over the whole width instead of hugging their labels.
    var fill = false

    public init(items: [Item], selection: Binding<ID>, fill: Bool = false) { self.items = items; self._selection = selection; self.fill = fill }
    @Namespace private var line

    public var body: some View {
        HStack(spacing: fill ? Tokens.Space.none : Tokens.Space.s18) {
            ForEach(items) { item in
                let chosen = item.id == selection
                Button { withAnimation(.smooth(duration: 0.22)) { selection = item.id } } label: {
                    HStack(spacing: Tokens.Space.s5) {
                        if let icon = item.icon { Glyph(icon, size: 11) }
                        Text(item.title).fontWeight(chosen ? .semibold : .regular)
                        if let count = item.count { Text(count).foregroundStyle(item.countColor) }
                    }
                    .font(.subheadline).lineLimit(1)
                    .foregroundStyle(chosen ? Color.primary : .secondary)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .padding(.top, Tokens.Space.s5).padding(.bottom, Tokens.Space.s8)
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
