import CarrierCore
import SwiftUI

public struct NavigationRow<Trailing: View>: View {
    var id: String?
    let title: String
    let detail: String
    let leading: AnyView?
    /// What is wrong, in words: it takes the place of the detail, in orange (`SettingsTabRow.problem`).
    var problem: String?
    /// The first row of a card has no line above it (a page that is not a form).
    var first = false
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    public init<Leading: View>(title: String, detail: String, leading: Leading, first: Bool = false, problem: String? = nil, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.first = first
        self.problem = problem
        self.leading = AnyView(leading)
        self.action = action
        self.trailing = trailing()
    }

    public init(id: String? = nil, title: String, detail: String, first: Bool = false, problem: String? = nil, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.id = id
        self.title = title
        self.detail = detail
        self.first = first
        self.problem = problem
        self.leading = nil
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            SettingsTabRow(id: id, title: title, detail: detail, first: first, problem: problem, leading: leading) {
                HStack(spacing: Tokens.Space.s10) {
                    trailing
                    Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
