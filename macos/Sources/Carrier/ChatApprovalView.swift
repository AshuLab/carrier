import CarrierCore
import SwiftUI

/// An approval waiting for the person (chat-ui-conv.html, section 4, option A): the question, the tool's argument in a code block
/// and one button per choice the provider listed, in its order; the first is primary and the ones that do not allow are red.
struct ApprovalCardView: View {
    let card: ApprovalCard
    let answer: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.question).font(.system(size: 13, weight: .semibold))
            if let arg = card.arg { CodeBlockView(language: card.tool, code: arg) }
            HStack(spacing: 8) {
                ForEach(Array(card.choices.enumerated()), id: \.element.id) { index, choice in
                    if index == 0 {
                        Button(choice.label) { answer(card.approvalId, choice.id) }.buttonStyle(.borderedProminent).tint(choice.allow ? nil : .red)
                    } else {
                        Button(choice.label) { answer(card.approvalId, choice.id) }.buttonStyle(.bordered).tint(choice.allow ? nil : .red)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
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
        .font(.system(size: 12, design: .monospaced))
    }
}
