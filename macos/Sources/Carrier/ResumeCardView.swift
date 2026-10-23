import CarrierCore
import SwiftUI

/// The card of a stopped epic, between its title and its tabs: the reason, what resuming does and, for an engine that can be asked,
/// the Resume button. Resume asks first in a sheet; the button reads "Resuming…" until the engine answers; a refusal stays in the card.
struct ResumeCardView: View {
    let card: ResumeCard
    let repo: String
    let issue: Int
    @State private var confirming = false
    @State private var resuming = false
    @State private var refusal: String?

    private var color: Color { card.attention == .error ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title).font(.headline)
                Text(card.words).foregroundStyle(.secondary)
                if let refusal { Text(refusal).font(.callout).foregroundStyle(color) }
            }
            Spacer(minLength: 12)
            if card.showsButton {
                Button(resuming ? "Resuming…" : "Resume") { confirming = true }
                    .buttonStyle(.borderedProminent).tint(color).disabled(resuming)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.35)))
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $confirming) { confirmation }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resume this epic?").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.sheet, id: \.self) { line in Text("• " + line) }
            }
            HStack {
                Spacer()
                Button("Cancel") { confirming = false }.keyboardShortcut(.cancelAction)
                Button("Resume") {
                    confirming = false
                    resume()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(color)
            }
        }
        .padding(20).frame(width: 420)
    }

    private func resume() {
        (resuming, refusal) = (true, nil)
        let (path, repo, issue) = (controlSocketPath(), repo, issue)
        DispatchQueue.global().async {
            let result = resumeEpic(socketPath: path, repo: repo, issue: issue)
            DispatchQueue.main.async {
                refusal = resumeFailureWords(result)
                guard result == .resumed else { return resuming = false }
                // the card goes with the stuck state at the next snapshot; where it does not (the fixture), the button comes back
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { resuming = false }
            }
        }
    }
}
