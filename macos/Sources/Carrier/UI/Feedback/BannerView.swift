import CarrierCore
import SwiftUI

/// A failed turn or a refused send: a `NoticeCard` in `tint` (red for a failure, orange for a warning), with the way out as text that lights a pill under
/// the pointer.
struct BannerView: View {
    let title: String
    let detail: String
    let hint: String?
    let tint: Color
    /// The account the banner is about: its mark stands before the title.
    var account: AccountMark?
    /// Puts the details on the pasteboard; nil leaves the button out (a refusal says its reason in full already).
    let copyDetails: (() -> Void)?
    /// Nil when the turn is no longer the last thing: the banner is then only a record.
    let retry: (() -> Void)?
    @State private var copied = false

    var body: some View {
        NoticeCard(symbol: .exclamation, tint: tint, title: title, detail: detail, hint: hint, edge: true, account: account) {
            if let copyDetails {
                Button {
                    copyDetails()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.3))
                        copied = false
                    }
                } label: { Label(copied ? "Copied" : "Copy details", icon: copied ? .check : .copy) }
                    .buttonStyle(NoticeActionStyle(quiet: true))
            }
            if let retry { Button(action: retry) { Label("Try again", icon: .refresh) }.buttonStyle(NoticeActionStyle()) }
        }
    }
}
