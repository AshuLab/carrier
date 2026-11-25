import CarrierCore
import SwiftUI

/// The Storage group of the page: what the downloaded speech models take, and Show in Finder.
struct StorageGroup: View {
    var dictation = DictationController.shared

    var body: some View {
        SettingsGroup(id: "storage", title: Copy.dictationGroupStorage()) {
            SettingsTabRow(id: "downloaded-models", title: Copy.dictationDownloadedModels(), detail: Copy.dictationDownloadedModelsDetail(size: formatModelSize(dictation.store.usedBytes)), first: true) {
                Button { dictation.showModelsInFinder() } label: { Label(Copy.dictationShowInFinder(), icon: .folder) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }
}
