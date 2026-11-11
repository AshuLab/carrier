import CarrierCore
import SwiftUI

/// An `AskUserQuestion` waiting for the person, over the message box in the same glass as the approval card: one question at a time (a chip
/// with its header, the question and whether it takes one pick or several, dots and Back when there are several, and what was answered before), its options as numbered rows with their description, and a
/// row to write an answer of their own. One pick answers and moves on (the last one sends everything); a question that takes several
/// picks has Next or Send. Skip declines them all. ⌥1, ⌥2… pick from the keyboard, as on the approval card; ⌘↩ sends and ⌥⎋ skips (never a bare
/// Return or Escape: the message box under the card is still there). Options that do not fit scroll.
struct QuestionCardView: View {
    let card: ApprovalCard
    let behind: Int
    /// The approval, the choice (Send answers or Skip) and, for the first, the answer to each question by its text.
    let answer: (String, String, [String: String]?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    /// Per question: the options picked, and `options.count` for the person's own answer.
    @State private var picked: [Set<Int>] = []
    @State private var own: [String] = []
    @State private var hovered: Int?
    /// The height the options want, to cap it (and scroll) when a question brings more than fits.
    @State private var optionsHeight: CGFloat = 0
    @FocusState private var writing: Bool

    private var question: ChatQuestion { card.questions[min(step, card.questions.count - 1)] }
    private var last: Bool { step >= card.questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark").font(.scaled(12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.attention))
                Text(question.header).font(.scaled(11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer(minLength: 0)
                Text(behind > 0 ? "\(behind) more waiting" : "Waiting for you").font(.scaled(11)).foregroundStyle(.secondary)
                if card.questions.count > 1 { progress }
            }
            if step > 0 { earlier }
            VStack(alignment: .leading, spacing: 2) {
                Text(question.question).font(.scaled(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(question.multiSelect ? "Choose any that apply" : "Choose one").font(.scaled(11)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        row(index, label: option.label, detail: option.description)
                        if let preview = option.preview, picked[safe: step]?.contains(index) == true { previewBlock(preview) }
                    }
                    row(question.options.count, label: "Other…", detail: nil)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { optionsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: optionsHeight > 0 ? min(optionsHeight, 300) : nil)
            if picked.indices.contains(step), picked[step].contains(question.options.count) {
                TextField("Your answer", text: $own[step]).textFieldStyle(.plain).font(.scaled(13)).focused($writing)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(writing ? 0.3 : 0.12)))
                    .onSubmit { if complete { next() } }
                    .accessibilityLabel("Your own answer")
            }
            HStack(spacing: 8) {
                if step > 0 { Button { go(step - 1) } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(PillButtonStyle(.quiet)) }
                Spacer(minLength: 0)
                Button("Skip") { answer(card.approvalId, declineId, nil) }.buttonStyle(PillButtonStyle(.decline))
                    .keyboardShortcut(.escape, modifiers: .option).help("Skip the questions (⌥⎋)")
                if needsButton {
                    // ⌘↩ and not a plain Return: the message box under the card would lose its Return
                    Button(last ? "Send" : "Next") { next() }.buttonStyle(PillButtonStyle(.primary)).disabled(complete == false)
                        .keyboardShortcut(.return, modifiers: .command).help("\(last ? "Send" : "Next") (⌘↩)")
                }
            }
            .font(.scaled(12))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.attention.opacity(0.16)), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .onAppear { setUp() }
        .onChange(of: card.approvalId) { _, _ in setUp() }
    }

    /// A pick moves on by itself, except the last question's: sending is final, so it waits for Send. A question with several picks, or the
    /// person's own words, always waits.
    private var needsButton: Bool {
        question.multiSelect || last || picked[safe: step]?.contains(question.options.count) == true
    }

    /// One dot per question, the current one filled.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(card.questions.indices, id: \.self) { Circle().fill(Color.primary.opacity($0 == step ? 0.7 : 0.2)).frame(width: 6, height: 6) }
        }
        .accessibilityElement().accessibilityLabel("Question \(step + 1) of \(card.questions.count)")
    }

    /// What was answered before this question, one line each, so the last one does not lose its context.
    private var earlier: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(0..<step, id: \.self) { at in
                Text("\(card.questions[at].header) · \(text(of: at))").font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private var allowId: String { card.choices.first(where: \.allow)?.id ?? "allow" }
    private var declineId: String { card.choices.first(where: { $0.allow == false })?.id ?? "deny" }

    private func setUp() {
        step = 0
        picked = card.questions.map { _ in [] }
        own = card.questions.map { _ in "" }
    }

    /// What the option looks like once picked (the provider's own sample), under its row.
    private func previewBlock(_ preview: String) -> some View {
        Text(preview).font(.scaled(11, design: .monospaced)).textSelection(.enabled).padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.leading, 40).padding(.bottom, 4)
    }

    /// The answer to question `at`: the labels picked in the order of the options, then the person's own words, comma-separated.
    private func text(of at: Int) -> String {
        guard card.questions.indices.contains(at), picked.indices.contains(at) else { return "" }
        let options = card.questions[at].options
        var parts = picked[at].filter { $0 < options.count }.sorted().map { options[$0].label }
        let mine = own[at].trimmingCharacters(in: .whitespacesAndNewlines)
        if picked[at].contains(options.count), mine.isEmpty == false { parts.append(mine) }
        return parts.joined(separator: ", ")
    }

    private var complete: Bool { text(of: step).isEmpty == false }

    private func go(_ to: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { step = to }
        hovered = nil
    }

    private func next() {
        guard complete else { return }
        if last == false { return go(step + 1) }
        let answers = Dictionary(uniqueKeysWithValues: card.questions.indices.map { (card.questions[$0].question, text(of: $0)) })
        answer(card.approvalId, allowId, answers)
    }

    private func choose(_ index: Int) {
        guard picked.indices.contains(step) else { return }
        let other = index == question.options.count
        if question.multiSelect {
            if picked[step].contains(index) { picked[step].remove(index) } else { picked[step].insert(index) }
        } else {
            picked[step] = [index]
        }
        if other, picked[step].contains(index) { writing = true } else if question.multiSelect == false, last == false { next() }
    }

    private func row(_ index: Int, label: String, detail: String?) -> some View {
        let chosen = picked[safe: step]?.contains(index) == true
        let line = Button { choose(index) } label: {
            HStack(spacing: 10) {
                ZStack {
                    // a circle takes one pick, a square takes several
                    RoundedRectangle(cornerRadius: question.multiSelect ? 6 : 10, style: .continuous).fill(chosen ? Color.themeAccent : Color.secondary.opacity(0.18))
                    if chosen { Image(systemName: "checkmark").font(.scaled(10, weight: .bold)).foregroundStyle(.white) } else {
                        Text("\(index + 1)").font(.scaled(11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.scaled(13, weight: .medium))
                    if let detail, detail.isEmpty == false { Text(detail).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                Text("⌥\(index + 1)").font(.scaled(11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(hovered == index ? 0.1 : chosen ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .accessibilityLabel(detail.map { "\(label). \($0)" } ?? label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        return line.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
    }
}

/// The one look of the buttons of the cards over the message box: a pill. Back is quiet, Skip is quiet and turns red under the pointer (as a choice that does not
/// allow does on the approval card), Send and Next wear the accent.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case quiet, decline, primary }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(12, weight: .medium))
            .foregroundStyle(text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
    }

    private var text: Color {
        switch kind {
        case .primary: .white
        case .decline: hovered ? .red : .secondary
        case .quiet: hovered ? .primary : .secondary
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: Color.themeAccent.opacity(hovered ? 1 : 0.9)
        case .decline: hovered ? Color.red.opacity(0.16) : Color.primary.opacity(0.08)
        case .quiet: Color.primary.opacity(hovered ? 0.14 : 0.08)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
