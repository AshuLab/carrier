import CarrierCore
import SwiftUI

/// The segments of the Dictation page.
enum DictationSegment: String, CaseIterable { case general = "General", history = "History", statistics = "Statistics" }

/// The Dictation page: segments over one view per group (`DictationGroup`, `GlobalDictationGroup`, `SoundsGroup`, `CleanupGroup`, `SpeechModelsGroup`, `StorageGroup` in General;
/// `HistoryGroup` in History, `StatisticsGroup` in Statistics). With the switch off the groups of General under it are drawn at 40% and take no clicks (`dictationRowIsLive`).
struct DictationTabView: View {
    var dictation = DictationController.shared
    @State private var segment = DictationSegment.general

    var body: some View {
        let enabled = dictation.enabled
        VStack(alignment: .leading, spacing: 12) {
            SegmentedChoice(options: DictationSegment.allCases.map { (value: $0, title: $0.rawValue, icon: nil) }, selection: $segment)
            switch segment {
            case .general:
                SettingsPageBody(reset: { dictation.reset() }) {
                    DictationGroup()
                    GlobalDictationGroup()
                    SoundsGroup().live(.sounds, enabled: enabled)
                    CleanupGroup().live(.cleanup, enabled: enabled)
                    SpeechModelsGroup().live(.modelsTable, enabled: enabled)
                    StorageGroup().live(.storage, enabled: enabled)
                }
            case .history:
                SettingsPageBody {
                    HistoryGroup()
                }
            case .statistics:
                SettingsPageBody {
                    StatisticsGroup()
                }
            }
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
