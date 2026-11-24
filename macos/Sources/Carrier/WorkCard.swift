import SwiftUI

/// The shell of a card in the feed: a fill and glass, rounded 12. The tool group of a session, a markdown table and the epic's
/// slices and review findings wear it, so how "a card with a line on top" looks is changed here once.
private struct WorkCardShell: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
            .chatSurface(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), flat: Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            // a solid base under the glass: a card that grows or folds goes over the message next to it for a moment, and the glass alone shows that text through it
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.themeWindow))
    }
}

extension View {
    func workCard() -> some View { modifier(WorkCardShell()) }
}
