import CarrierCore
import SwiftUI

/// An approval waiting for the person, over the message box in glass tinted with the attention orange: the question, the tool's argument
/// in a code block and one numbered line per choice the provider listed, in its order. The first is the one to press (it wears the accent),
/// a choice that does not allow turns red under the pointer, and ⌥1, ⌥2… answer from the keyboard (a plain digit would be a character
/// of the message being written). With more than one waiting, the others come after this one is answered.
struct ApprovalCardView: View {
    let card: ApprovalCard
    /// How many more approvals wait behind this one.
    let behind: Int
    let answer: (String, String) -> Void
    @State private var hovered: String?
    /// The height the tool's argument wants, to cap it (and scroll) when it would push the message box out of a short window.
    @State private var argHeight: CGFloat = 0
    @Environment(\.conversationHeight) private var paneHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.snug) {
            HStack(spacing: Tokens.Space.snug) {
                Glyph(.exclamation, size: 12, bold: true).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.attention))
                Text(card.question).font(.scaled(14, weight: .semibold))
                Spacer(minLength: 0)
                Text(behind > 0 ? "\(behind) more waiting" : "Waiting for you").font(.scaled(11)).foregroundStyle(.secondary)
            }
            if let arg = card.arg {
                ScrollView { CodeBlockView(language: card.tool, code: arg).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { argHeight = $0 } }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: argHeight > 0 ? min(argHeight, cardRoom(in: paneHeight)) : nil)
            }
            VStack(spacing: Tokens.Space.hair) {
                ForEach(Array(card.choices.enumerated()), id: \.element.id) { index, choice in row(index, choice) }
            }
        }
        .padding(Tokens.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatSurface(.regular.tint(Color.attention.opacity(0.16)), flat: Color.attention.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.sheet))
        .accessibilityElement(children: .contain)
    }

    private func row(_ index: Int, _ choice: ChatChoice) -> some View {
        let first = index == 0
        let line = Button { answer(card.approvalId, choice.id) } label: {
            HStack(spacing: Tokens.Space.snug) {
                Text("\(index + 1)").font(.scaled(11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(first ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous).fill(first ? Color.themeAccent : Color.secondary.opacity(0.18)))
                Text(choice.label).font(.scaled(13, weight: .medium)).foregroundStyle(choice.allow ? Color.primary : Color.red)
                Spacer(minLength: 0)
                if index < 9 { Text("⌥\(index + 1)").font(.scaled(11)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, Tokens.Space.snug).padding(.vertical, Tokens.Space.sm)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.snug, style: .continuous).fill(fill(choice, first: first)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? choice.id : (hovered == choice.id ? nil : hovered) }
        .accessibilityLabel(choice.label)
        return index < 9 ? AnyView(line.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)) : AnyView(line)
    }

    private func fill(_ choice: ChatChoice, first: Bool) -> Color {
        if hovered == choice.id { return choice.allow ? Color.primary.opacity(0.1) : Color.red.opacity(0.16) }
        return first ? Color.primary.opacity(0.06) : .clear
    }
}

extension Color {
    /// What asks for the person's attention (approvals, questions): a dusty amber, less bright than the system orange.
    static let attention = Color(Tokens.Attention.approval)
}

/// What an answered approval became: one line, with a check when the choice allowed and a cross when it did not.
struct ApprovalDecidedView: View {
    let text: String
    let allow: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.tight) {
            Glyph(allow ? .check : .close).foregroundStyle(allow ? Color.green : Color.red)
            Text(text).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
        }
        .codeFont(12)
    }
}

extension EnvironmentValues {
    /// The height of the conversation's pane, so what sits over the message box (an approval, a question) can leave the box room in a short window.
    @Entry var conversationHeight: CGFloat = 0
}

/// How tall the long part of a card over the message box (a command, the options of a question) may be: a third of the pane, never less than a few lines,
/// and a fixed height while the pane's is not known yet. Over it the part scrolls, so the card never covers the box.
func cardRoom(in paneHeight: CGFloat) -> CGFloat { paneHeight > 0 ? max(120, paneHeight / 3) : 300 }
