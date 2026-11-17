import CarrierCore
import SwiftUI

/// The notice of a stopped epic, the last element of its Agent output feed: the reason, what resuming does and, for an engine that can be
/// asked, the Resume button. Resume asks first in a sheet; the button reads "Resuming…" until the engine answers and the snapshot shows
/// the epic out of needs-human (`EpicStore.resuming`); a refusal stays under the words.
struct ResumeCardView: View {
    let card: ResumeCard
    let store: EpicStore
    let epic: EpicRef
    @State private var confirming = false

    private var resuming: Bool { store.resuming.contains(epic) }

    var body: some View {
        NoticeCard(symbol: "exclamationmark", tint: card.attention.color, title: card.title, detail: card.words) {
            if card.showsButton {
                Button { confirming = true } label: { Label(resuming ? "Resuming…" : "Resume", systemImage: "play.fill") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).labelStyle(.titleAndIcon).disabled(resuming)
            }
        } below: {
            if let refusal = store.resumeRefusals[epic] { ProblemLine(text: refusal, font: .scaled(11.5)).padding(.top, 6) }
        }
        .sheet(isPresented: $confirming) { confirmation.themed() }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resume this epic?").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.sheet, id: \.self) { line in Text("• " + line) }
            }
            HStack(spacing: 10) {
                Spacer()
                Button { confirming = false } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
                Button {
                    confirming = false
                    resume()
                } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .labelStyle(.titleAndIcon).padding(.top, 10)
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
