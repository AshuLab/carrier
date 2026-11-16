import CarrierCore
import SwiftUI

/// The Dictation page: one view per group (`DictationGroup`, `GlobalDictationGroup`, `SoundsGroup`, `CleanupGroup`, `SpeechModelsGroup`, `StorageGroup`). With the switch off the groups under it are drawn at 40% and take no
/// clicks (`dictationRowIsLive`).
struct DictationTabView: View {
    var dictation = DictationController.shared

    var body: some View {
        let enabled = dictation.enabled
        SettingsPageBody(reset: { dictation.reset() }) {
            DictationGroup()
            GlobalDictationGroup()
            SoundsGroup().live(.sounds, enabled: enabled)
            CleanupGroup().live(.cleanup, enabled: enabled)
            SpeechModelsGroup().live(.modelsTable, enabled: enabled)
            StorageGroup().live(.storage, enabled: enabled)
        }
    }
}

/// A capsule with a word in it: its color at 16% under the same color, so the state is never the color alone.
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

extension View {
    /// A row the switch can dim: at 40% and with no clicks, for keyboard and VoiceOver too, while Dictation is off.
    func live(_ row: DictationRow, enabled: Bool) -> some View {
        let live = dictationRowIsLive(row, enabled: enabled)
        return opacity(live ? 1 : 0.4).disabled(live == false)
    }
}
