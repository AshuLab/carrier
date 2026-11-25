import SwiftUI

/// The mark of an account, drawn from values: a symbol (the glyph the account was given), else its `initials` (the first letter, when the account was given
/// that), else its tool's mark as `ProviderMark` draws it; in `tint`, or in the color around it when there is none. The area that shows an account asks
/// the account's identity and passes these (`AccountMark(account:)`).
struct AccountMark: View {
    /// An SF Symbol name; nil when the account has no glyph.
    var symbol: String?
    /// What the mark says when it has no symbol; empty to draw the tool's mark instead.
    var initials = ""
    /// What the tool's mark is looked up by when there is no symbol and no initials.
    var tool = ""
    /// Nil takes the color the mark is drawn in.
    var tint: Color?
    var size: CGFloat = 14

    var body: some View {
        if let tint { mark.foregroundStyle(tint) } else { mark }
    }

    @ViewBuilder private var mark: some View {
        if let symbol {
            Image(systemName: symbol).scaledFont(size * 0.86, weight: .medium).frame(width: size, height: size)
        } else if initials.isEmpty == false {
            Text(initials).scaledFont(size * 0.8, weight: .bold).frame(width: size, height: size)
        } else {
            ProviderMark(name: tool, size: size)
        }
    }
}
