import CarrierCore
import SwiftUI

struct NavigationRow<Trailing: View>: View {
    var id: String?
    let title: String
    let detail: String
    let leading: AnyView?
    /// The first row of a card has no line above it (a page that is not a form).
    var first = false
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    init<Leading: View>(title: String, detail: String, leading: Leading, first: Bool = false, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.first = first
        self.leading = AnyView(leading)
        self.action = action
        self.trailing = trailing()
    }

    init(id: String? = nil, title: String, detail: String, first: Bool = false, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.id = id
        self.title = title
        self.detail = detail
        self.first = first
        self.leading = nil
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            SettingsTabRow(id: id, title: title, detail: detail, first: first, leading: leading) {
                HStack(spacing: 10) {
                    trailing
                    Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
