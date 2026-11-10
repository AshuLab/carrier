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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark").font(.scaled(12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange))
                Text(card.question).font(.scaled(14, weight: .semibold))
                Spacer(minLength: 0)
                Text(behind > 0 ? "\(behind) more waiting" : "Waiting for you").font(.scaled(11)).foregroundStyle(.secondary)
            }
            if let arg = card.arg { CodeBlockView(language: card.tool, code: arg) }
            VStack(spacing: 2) {
                ForEach(Array(card.choices.enumerated()), id: \.element.id) { index, choice in row(index, choice) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.orange.opacity(0.25)), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func row(_ index: Int, _ choice: ChatChoice) -> some View {
        let first = index == 0
        let line = Button { answer(card.approvalId, choice.id) } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)").font(.scaled(11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(first ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(first ? Color.themeAccent : Color.secondary.opacity(0.18)))
                Text(choice.label).font(.scaled(13, weight: .medium)).foregroundStyle(choice.allow ? Color.primary : Color.red)
                Spacer(minLength: 0)
                if index < 9 { Text("⌥\(index + 1)").font(.scaled(11)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill(choice, first: first)))
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

/// What an answered approval became: one line, with a check when the choice allowed and a cross when it did not.
struct ApprovalDecidedView: View {
    let text: String
    let allow: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: allow ? "checkmark" : "xmark").foregroundStyle(allow ? Color.green : Color.red)
            Text(text).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        }
        .codeFont(12)
    }
}
