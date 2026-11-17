import SwiftUI

/// The card the app uses to tell the person something over the message box: a badge, a title, what it means and the actions on the right,
/// in glass. The errors, the notice of a session that is asleep or archived and the message held while the agent answers are all this
/// card; each says its own colour, which fills the glass. `edge` adds a thin edge in the colour, for something that went wrong or needs attention.
struct NoticeCard<Actions: View, Below: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    var hint: String?
    /// A small label before the detail (what the question is about).
    var tag: String?
    /// How many lines the detail may take; all of it when nil.
    var detailLines: Int?
    var edge = false
    /// The account the notice is about: its mark (icon and color, as the footer of an answer wears them) stands before the title.
    var account: String?
    /// When set, the text is a button (the queued message puts itself back in the box).
    var onTap: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    /// Under the header, starting where the title does less 10 points: its rows carry their own inset, so a fill under the pointer lines up.
    @ViewBuilder var below: () -> Below
    init(
        symbol: String, tint: Color, title: String, detail: String? = nil, hint: String? = nil, tag: String? = nil, detailLines: Int? = nil,
        edge: Bool = false, account: String? = nil, onTap: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder below: @escaping () -> Below
    ) {
        (self.symbol, self.tint, self.title, self.detail, self.hint, self.tag) = (symbol, tint, title, detail, hint, tag)
        (self.detailLines, self.edge, self.account, self.onTap, self.actions, self.below) = (detailLines, edge, account, onTap, actions, below)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: symbol).font(.scaled(13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.85)))
                    .accessibilityHidden(true)
                if let onTap { Button(action: onTap) { text }.buttonStyle(.plain) } else { text }
                actions()
            }
            below().padding(.leading, 33)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .chatSurface(.regular.tint(tint.opacity(0.3)), flat: tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .overlay { if edge { RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.45), lineWidth: 1) } }
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let account { AccountMark(account: account, size: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 } }
                Text(title).font(.scaled(13.5, weight: .semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            if tag != nil || detail != nil {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let tag {
                        Text(tag).font(.scaled(11)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    if let detail {
                        let line = Text(detail).font(.scaled(11.5)).foregroundStyle(.secondary).lineSpacing(1.5).lineLimit(detailLines).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        // a text that is a button is not selectable: the click is the point
                        if onTap == nil { line.textSelection(.enabled) } else { line }
                    }
                }
            }
            if let hint { Text(hint).font(.scaled(11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension NoticeCard where Below == EmptyView {
    init(
        symbol: String, tint: Color, title: String, detail: String? = nil, hint: String? = nil, tag: String? = nil, detailLines: Int? = nil,
        edge: Bool = false, account: String? = nil, onTap: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(
            symbol: symbol, tint: tint, title: title, detail: detail, hint: hint, tag: tag, detailLines: detailLines, edge: edge, account: account,
            onTap: onTap, actions: actions, below: { EmptyView() }
        )
    }
}

/// A button that is only its text (or icon) until the pointer is over it, when a pill lights behind it: light enough to sit beside a
/// message without weighing as much as it.
struct HoverTextButtonStyle: ButtonStyle {
    let tint: Color?
    /// Turns red under the pointer, as a choice that does not allow does.
    var danger = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(12, weight: .medium))
            .foregroundStyle(danger && hovered ? Color.red : tint ?? (hovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10).frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(danger && hovered ? Color.red.opacity(0.14) : Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.09 : 0)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
