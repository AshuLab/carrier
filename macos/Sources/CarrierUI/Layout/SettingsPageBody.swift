import CarrierCore
import SwiftUI

/// What a page is made of: its groups, as a native `Form` where the page is one (`SettingsPage.usesForm`) and a column of cards elsewhere. A page
/// with many controls gives `reset`: the toolbar's menu runs it after asking.
struct SettingsPageBody<Content: View>: View {
    var reset: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.settingsForm) private var form
    @Environment(\.settingsReset) private var resetter
    @State private var owner = UUID()

    var body: some View {
        Group {
            if form {
                Form { content }.formStyle(.grouped).scrollContentBackground(.hidden)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s12) { content }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { if let reset { resetter?.set(owner, reset) } }
        .onDisappear { resetter?.clear(owner) }
    }
}
