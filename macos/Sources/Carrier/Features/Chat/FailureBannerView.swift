import AppKit
import CarrierCore
import SwiftUI

/// A `FailureBanner` as a banner: red when the turn failed, orange when the provider is not signed in (chat-ui-conv.html, section 3).
struct FailureBannerView: View {
    let banner: FailureBanner
    /// The agent that failed or was refused: when its account has an icon, a color or a label, its mark stands before the title.
    var agent: String?
    /// Copy details puts the provider's text on the pasteboard; a failed turn has it, a refusal says its reason in full already.
    let copyDetails: Bool
    let retry: (() -> Void)?

    /// An account with none of the three shows the title alone, as it always did.
    private var markedAccount: String? {
        guard let agent, ProviderIdentityStore.shared.identity(of: agent) != .none else { return nil }
        return agent
    }

    var body: some View {
        BannerView(
            title: banner.title, detail: banner.detail, hint: banner.hint, tint: banner.warns ? .orange : .red, account: markedAccount.map { AccountMark(account: $0, size: 13) },
            copyDetails: copyDetails ? copy : nil, retry: retry
        )
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(banner.detail, forType: .string)
    }
}
