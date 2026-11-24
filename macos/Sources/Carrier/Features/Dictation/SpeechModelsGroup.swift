import CarrierCore
import SwiftUI

/// The Speech models group of the page: the recognizer filter and the table, and the confirmation of a delete.
struct SpeechModelsGroup: View {
    var dictation = DictationController.shared
    // the chosen model is the controller's; this makes the table redraw when it changes, Reset included
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @State private var filter: RecognizerID?
    /// The id of the model the trash asked to delete, while the confirmation is open.
    @State private var deleting: String?

    var body: some View {
        SettingsGroup(title: "Speech models", footer: "The model in use is the one with its radio lit. A model on disk can be chosen; one that is not has to be downloaded first.", accessory: {
            SegmentedChoice(options: [(value: RecognizerID?.none, title: "All", icon: nil)] + RecognizerID.allCases.map { (value: Optional($0), title: $0.title, icon: nil) }, selection: $filter)
                .accessibilityLabel("Recognizer")
        }, content: {
            if let missing = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:)).missing {
                // another model listens until this one is back: said where it can be downloaded
                ProblemLine(text: "\(missing.name) is not on disk: download it in the table or choose another", font: .scaled(11), announces: false)
                    .padding(.vertical, 8)
            }
            SpeechModelsTable(
                rows: dictation.rows(filter: filter), choose: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) },
                download: dictation.store.download, cancel: dictation.store.cancel, delete: { deleting = $0 }
            )
        })
        .alert(
            "Delete \(deleting.flatMap(modelNamed) ?? "the model")?", isPresented: Binding(get: { deleting != nil }, set: { if $0 == false { deleting = nil } })
        ) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let id = deleting { dictation.store.delete(id) }
                deleting = nil
            }
        } message: {
            Text("It frees its space on this Mac. You can download it again.")
        }
    }

    private func modelNamed(_ id: String) -> String? { dictation.models.first { $0.id == id }?.name }
}
