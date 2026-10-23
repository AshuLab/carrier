import CarrierCore
import SwiftUI

/// The card of a stopped epic, between its title and its tabs: the reason, what resuming does and, for an engine that can be asked,
/// the Resume button. Resume asks first in a sheet; the button reads "Resuming…" until the engine answers and the snapshot shows the epic out of needs-human (`EpicStore.resuming`); a refusal stays in the card.
struct ResumeCardView: View {
    let card: ResumeCard
    let store: EpicStore
    let epic: EpicRef
    @State private var confirming = false

    private var resuming: Bool { store.resuming.contains(epic) }

    private var color: Color { card.attention == .error ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title).font(.headline)
                Text(card.words).foregroundStyle(.secondary)
                if let refusal = store.resumeRefusals[epic] { Text(refusal).font(.callout).foregroundStyle(color) }
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
        store.startResuming(epic)
        let (path, store, epic) = (controlSocketPath(), store, epic)
        DispatchQueue.global().async {
            let result = resumeEpic(socketPath: path, repo: epic.repo, issue: epic.issue)
            DispatchQueue.main.async { store.answeredResume(epic, refusal: resumeFailureWords(result)) }
        }
    }
}
