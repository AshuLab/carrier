import CarrierCore
import SwiftUI

/// The card the app uses to tell the person something over the message box: a badge, a title, what it means and the actions on the right,
/// in glass. The errors, the notice of a session that is asleep or archived and the message held while the agent answers are all this
/// card; each says its own colour, which fills the glass.
public struct NoticeCard<Actions: View, Below: View>: View {
    let symbol: AppIcon
    let tint: Color
    let title: String
    var detail: String?
    var hint: String?
    /// A small label before the detail (what the question is about).
    var tag: String?
    /// How many lines the detail may take; all of it when nil.
    var detailLines: Int?
    var edge = false
    /// The detail goes on the title's own line, cut at the end, instead of under it.
    var inline = false
    /// The account the notice is about: its mark (icon and color, as the footer of an answer wears them) stands before the title.
    var account: AccountMark?
    /// When set, the text is a button (the queued message puts itself back in the box).
    var onTap: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    /// Under the header, starting where the title does less 10 points: its rows carry their own inset, so a fill under the pointer lines up.
    @ViewBuilder var below: () -> Below
    public init(
        symbol: AppIcon, tint: Color, title: String, detail: String? = nil, hint: String? = nil, tag: String? = nil, detailLines: Int? = nil,
        edge: Bool = false, inline: Bool = false, account: AccountMark? = nil, onTap: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder below: @escaping () -> Below
    ) {
        (self.symbol, self.tint, self.title, self.detail, self.hint, self.tag) = (symbol, tint, title, detail, hint, tag)
        (self.detailLines, self.edge, self.inline, self.account, self.onTap, self.actions, self.below) = (detailLines, edge, inline, account, onTap, actions, below)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            HStack(alignment: .center, spacing: Tokens.Space.s14) {
                Glyph(symbol, size: 13, bold: true).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous).fill(tint.opacity(0.85)))
                    .accessibilityHidden(true)
                if let onTap { Button(action: onTap) { text }.buttonStyle(.plain) } else { text }
                actions()
            }
            below().padding(.leading, Tokens.Space.s32)
        }
        .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s12)
        .chatSurface(.regular.tint(tint.opacity(0.3)), flat: tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.roomy))
        .environment(\.noticeTint, tint)
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s6) {
                if let account { account.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 } }
                Text(title).scaledFont(13.5, weight: .semibold).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(inline ? 1 : 0)
                if inline, let detail {
                    Text(detail).scaledFont(11.5).foregroundStyle(Color.primary.opacity(0.78)).lineLimit(1).truncationMode(.tail)
                }
            }
            if inline == false, tag != nil || detail != nil {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                    if let tag {
                        Text(tag).scaledFont(11).foregroundStyle(.secondary).padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    if let detail {
                        let line = Text(detail).scaledFont(11.5).foregroundStyle(Color.primary.opacity(0.78)).lineSpacing(1.5).lineLimit(detailLines).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        // a text that is a button is not selectable: the click is the point
                        if onTap == nil { line.textSelection(.enabled) } else { line }
                    }
                }
            }
            if let hint { Text(hint).scaledFont(11.5).foregroundStyle(Color.primary.opacity(0.78)).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension NoticeCard where Below == EmptyView {
    public init(
        symbol: AppIcon, tint: Color, title: String, detail: String? = nil, hint: String? = nil, tag: String? = nil, detailLines: Int? = nil,
        edge: Bool = false, inline: Bool = false, account: AccountMark? = nil, onTap: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(
            symbol: symbol, tint: tint, title: title, detail: detail, hint: hint, tag: tag, detailLines: detailLines, edge: edge, inline: inline, account: account,
            onTap: onTap, actions: actions, below: { EmptyView() }
        )
    }
}

extension EnvironmentValues {
    /// The colour of the `NoticeCard` the view is in, for its actions (`NoticeActionStyle`).
    @Entry public var noticeTint = Color.gray
}
