import SwiftUI

/// The card the app uses to tell the person something over the message box: a badge, a title, what it means and the actions on the right,
/// in glass. The errors, the notice of a session that is asleep or archived and the message held while the agent answers are all this
/// card; each says its own colour. `tinted` fills the glass with the colour (a state the session is in); the neutral glass with a thin
/// edge in the colour is for something that went wrong or needs attention.
struct NoticeCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    var hint: String?
    /// How many lines the detail may take; all of it when nil.
    var detailLines: Int?
    var tinted = false
    var edge = false
    /// When set, the text is a button (the queued message puts itself back in the box).
    var onTap: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol).font(.scaled(13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.85)))
                .accessibilityHidden(true)
            if let onTap { Button(action: onTap) { text }.buttonStyle(.plain) } else { text }
            actions()
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background { if tinted == false { RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)) } }
        .glassEffect(.regular.tint(tinted ? tint.opacity(0.3) : (scheme == .dark ? Color.black.opacity(0.3) : nil)), in: .rect(cornerRadius: 14))
        .overlay { if edge { RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.45), lineWidth: 1) } }
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.scaled(13.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
            if let detail {
                let line = Text(detail).font(.scaled(11.5)).foregroundStyle(.secondary).lineSpacing(1.5).lineLimit(detailLines).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // a text that is a button is not selectable: the click is the point
                if onTap == nil { line.textSelection(.enabled) } else { line }
            }
            if let hint { Text(hint).font(.scaled(11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A button that is only its text (or icon) until the pointer is over it, when a pill lights behind it: light enough to sit beside a
/// message without weighing as much as it.
struct HoverTextButtonStyle: ButtonStyle {
    let tint: Color?
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(12, weight: .medium))
            .foregroundStyle(tint ?? (hovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10).frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.09 : 0)))
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
