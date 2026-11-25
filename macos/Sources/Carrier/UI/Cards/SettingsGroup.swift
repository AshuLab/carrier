import SwiftUI

/// A group of a tab: a small uppercase title over a card of rows, or a section of a native `Form`. `footer` is the longer word about the whole
/// group, under it, so a row's own line can stay short.
struct SettingsGroup<Content: View, Accessory: View>: View {
    var id: String?
    let title: String
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.settingsForm) private var form

    var body: some View {
        if form {
            Section {
                content.environment(\.settingsGroup, id ?? "")
            } header: {
                if title.isEmpty == false {
                    HStack {
                        Text(title)
                        Spacer(minLength: 8)
                        accessory
                    }
                    .settingsAnchored(id, group: id)
                }
            } footer: {
                if let footer { Text(footer) }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if title.isEmpty == false {
                    HStack {
                        Text(title).sectionLabel()
                        Spacer(minLength: 8)
                        accessory
                    }
                    .padding(.leading, 14).padding(.top, 8)
                }
                SettingsTabCard { content }.environment(\.settingsGroup, id ?? "")
                if let footer { Text(footer).scaledFont(11).foregroundStyle(.secondary).padding(.horizontal, 14) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsAnchored(id, group: id)
        }
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(id: String? = nil, title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(id: id, title: title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}
