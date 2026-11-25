import CarrierCore
import SwiftUI

/// The Speech models group of the page: the recognizer filter and the table, and the confirmation of a delete.
struct SpeechModelsGroup: View {
    var dictation = DictationController.shared
    // the chosen model is the controller's; this makes the table redraw when it changes, Reset included
    @AppStorage(Preference.dictationModel) private var savedModel
    @State private var filter: RecognizerID?
    /// The id of the model the trash asked to delete, while the confirmation is open.
    @State private var deleting: String?

    var body: some View {
        SettingsGroup(id: "speech-models", title: Copy.dictationGroupModels(), footer: Copy.dictationModelsFooter(), accessory: {
            SegmentedChoice(options: [(value: RecognizerID?.none, title: Copy.dictationFilterAll(), icon: nil)] + RecognizerID.allCases.map { (value: Optional($0), title: $0.title, icon: nil) }, selection: $filter)
                .accessibilityLabel(Copy.dictationRecognizerName())
        }, content: {
            if let missing = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:)).missing {
                // another model listens until this one is back: said where it can be downloaded
                ProblemLine(text: Copy.dictationModelMissing(model: missing.name), size: 11, announces: false)
                    .padding(.vertical, Tokens.Space.s8)
            }
            SpeechModelsTable(
                rows: dictation.rows(filter: filter), choose: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) },
                download: dictation.store.download, cancel: dictation.store.cancel, delete: { deleting = $0 }
            )
        })
        .alert(
            deleting.flatMap(modelNamed).map { Copy.dictationDeleteModelTitle(model: $0) } ?? Copy.dictationDeleteModelTitleGeneric(), isPresented: Binding(get: { deleting != nil }, set: { if $0 == false { deleting = nil } })
        ) {
            Button(Copy.dictationCancel(), role: .cancel) { deleting = nil }
            Button(Copy.dictationDelete(), role: .destructive) {
                if let id = deleting { dictation.store.delete(id) }
                deleting = nil
            }
        } message: {
            Text(Copy.dictationDeleteModelMessage())
        }
    }

    private func modelNamed(_ id: String) -> String? { dictation.models.first { $0.id == id }?.name }
}
