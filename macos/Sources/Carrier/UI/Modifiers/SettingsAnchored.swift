import CarrierCore
import SwiftUI

/// Makes a row (or a group, with its own identifier as both) findable by the search: the id the page scrolls to, and the color it takes when it
/// is the place that was chosen. With no identifier the view is not a place of the search.
private struct SettingsAnchored: ViewModifier {
    let group: String?
    let id: String
    @Environment(\.settingsPage) private var page
    @Environment(\.settingsGroup) private var inherited
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        if let page {
            let anchor = settingsAnchor(page, group: group ?? inherited, row: id)
            content.id(anchor)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Color.yellow.opacity(highlight == anchor ? 0.3 : 0)))
                .animation(.easeOut(duration: 0.5), value: highlight == anchor)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func settingsAnchored(_ id: String?, group: String? = nil) -> some View {
        if let id { modifier(SettingsAnchored(group: group, id: id)) } else { self }
    }
}
