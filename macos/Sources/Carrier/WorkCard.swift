import SwiftUI

/// The shell of a card in the feed: a fill and glass, rounded 12. The tool group of a session, a markdown table and the epic's
/// slices and review findings wear it, so how "a card with a line on top" looks is changed here once.
private struct WorkCardShell: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
            .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 12))
    }
}

extension View {
    func workCard() -> some View { modifier(WorkCardShell()) }
}
