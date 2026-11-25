import CarrierCore
import SwiftUI

/// The Storage group of the page: what the downloaded speech models take, and Show in Finder.
struct StorageGroup: View {
    var dictation = DictationController.shared

    var body: some View {
        SettingsGroup(id: "storage", title: "Storage") {
            SettingsTabRow(id: "downloaded-models", title: "Downloaded models", detail: "\(formatModelSize(dictation.store.usedBytes)) in the Carrier folder", first: true) {
                Button { dictation.showModelsInFinder() } label: { Label("Show in Finder", icon: .folder) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }
}
