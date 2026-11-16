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
        SettingsGroup(title: "Speech models", accessory: {
            HStack(spacing: 6) {
                FilterChip(title: "All", on: filter == nil) { filter = nil }
                ForEach(RecognizerID.allCases, id: \.self) { recognizer in
                    FilterChip(title: recognizer.title, on: filter == recognizer) { filter = filter == recognizer ? nil : recognizer }
                }
            }
            .padding(.trailing, 14)
        }, content: {
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
