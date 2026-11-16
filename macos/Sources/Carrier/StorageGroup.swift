import CarrierCore
import SwiftUI

/// The Storage group of the page: what the downloaded speech models take, and Show in Finder.
struct StorageGroup: View {
    var dictation = DictationController.shared

    var body: some View {
        SettingsGroup(title: "Storage") {
            SettingsTabRow(title: "Downloaded models", detail: "\(formatModelSize(dictation.store.usedBytes)) in the Carrier folder", first: true) {
                Button { dictation.showModelsInFinder() } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }
}
