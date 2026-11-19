import CarrierCore
import SwiftUI

/// The Dictation page of Settings: a first screen with whether dictation works now (`DictationStatusCard`) and the screens it opens, each a place of the
/// window's history (‹ ›), as the Providers page does: Speech recognition (`SpeechModelsGroup`, `LanguageGroup`, `MemoryGroup`, `StorageGroup`), Global
/// dictation (`GlobalDictationGroup`, `WidgetGroup`), Cleanup (`CleanupGroup`), Sounds (`SoundsGroup`), History (`HistoryGroup`) and Statistics
/// (`StatisticsGroup`). With the switch off the settings inside the screens are drawn at 40% and take no clicks (`dictationRowIsLive`); the rows that open a
/// screen, History and Statistics stay as they are. The page's Reset is the toolbar's, on the first screen only.
struct DictationTabView: View {
    var dictation = DictationController.shared
    /// Where the page is: nothing for the first screen, or the path of one of its screens (`DictationScreen`).
    var place = SettingsPlace(.dictation)
    var go: (SettingsPlace) -> Void = { _ in }
    // the cleanup's choices are the controller's, and a defaults it does not publish: these make the toolbar's line and the Cleanup row redraw when they change
    @AppStorage(AppPreferences.dictationCleanupEnabledKey) private var cleanupOn = false
    @AppStorage(AppPreferences.dictationCleanupServerKey) private var cleanupServer: String?
    // what the summaries of the first screen say is stored in these; they make it redraw when a screen changes one, Reset included
    @AppStorage(AppPreferences.dictationGlobalKey) private var global = AppPreferences.defaultDictationGlobal
    @AppStorage(AppPreferences.dictationShortcutKey) private var shortcutText = ""
    @AppStorage(AppPreferences.dictationActivationKey) private var activation = DictationActivation.toggle
    @AppStorage(AppPreferences.dictationWidgetStyleKey) private var widgetStyle = DictationWidgetStyle.medium
    @AppStorage(AppPreferences.dictationStartSoundOnKey) private var startOn = DictationSounds().startOn
    @AppStorage(AppPreferences.dictationStartSoundKey) private var start = DictationSounds.defaultStart
    @AppStorage(AppPreferences.dictationEndSoundOnKey) private var endOn = DictationSounds().endOn
    @AppStorage(AppPreferences.dictationEndSoundKey) private var end = DictationSounds.defaultEnd
    @AppStorage(AppPreferences.dictationSoundVolumeKey) private var volume = DictationSounds.defaultVolume
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationLanguageKey) private var savedLanguage: String?

    private var screen: DictationScreen? { place.path.first.flatMap(DictationScreen.init(rawValue:)) }

    var body: some View {
        let enabled = dictation.enabled
        // the id makes each screen its own body: the Reset it offers (the first screen's alone) is taken in when it appears and given back when it goes
        SettingsPageBody(reset: screen == nil ? { dictation.reset() } : nil) {
            switch screen {
            case .none: first
            case .recognition?:
                offNotice
                SpeechModelsGroup(dictation: dictation).live(.modelsTable, enabled: enabled)
                LanguageGroup(dictation: dictation).live(.language, enabled: enabled)
                MemoryGroup(dictation: dictation)
                StorageGroup(dictation: dictation).live(.storage, enabled: enabled)
            case .global?:
                offNotice
                GlobalDictationGroup(dictation: dictation)
                WidgetGroup(dictation: dictation)
            case .cleanup?:
                offNotice
                CleanupGroup().live(.cleanup, enabled: enabled)
            case .sounds?:
                offNotice
                SoundsGroup().live(.sounds, enabled: enabled)
            case .history?: HistoryGroup(dictation: dictation)
            case .statistics?: StatisticsGroup(dictation: dictation)
            }
        }
        .id(screen)
        .preference(key: SettingsTitleKey.self, value: screen.map { SettingsTitle(text: $0.title, subtitle: summary($0)) })
    }

    @ViewBuilder private var first: some View {
        SettingsGroup(title: "") {
            DictationStatusCard(dictation: dictation)
        }
        SettingsGroup(title: "Set up") {
            ForEach([DictationScreen.recognition, .global, .cleanup, .sounds], id: \.self) { opens($0) }
        }
        SettingsGroup(title: "Your dictations") {
            opens(.history)
            opens(.statistics)
        }
    }

    /// What a screen that Dictation's switch dims says first, with the way to turn it on: a person who comes by a search finds the screen locked.
    @ViewBuilder private var offNotice: some View {
        if dictation.enabled == false {
            SettingsGroup(title: "") {
                HStack(spacing: 12) {
                    Glyph(.power, size: 14).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("Dictation is off, so what is set here waits. Turn it on to change it.").font(.scaled(12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Turn on") { dictation.setEnabled(true) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize()
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func opens(_ screen: DictationScreen) -> some View {
        NavigationRow(title: screen.title, detail: screen.detail, action: { go(SettingsPlace(.dictation, path: [screen.rawValue])) }) {
            // two lines before a cut: at a narrow window and a large text the summary wraps and does not lose its last word
            Text(summary(screen)).font(.scaled(12)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What a screen holds, in a few words: under its row, and under its title in the toolbar.
    private func summary(_ screen: DictationScreen) -> String {
        switch screen {
        case .recognition:
            let model = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:)).shown?.name ?? "Apple"
            return dictation.languages.map { "\(model) · \(dictationLanguageName($0.selected))" } ?? model
        case .global:
            return dictation.enabled && global ? "\(AppPreferences().dictationShortcut.text) · \(activation == .hold ? "Hold" : "Toggle") · \(widgetStyle.title)" : "Off"
        case .cleanup:
            return cleanupOn ? "On · \(cleanupServer.flatMap(CleanupServer.init(rawValue:))?.title ?? "no server yet")" : "Off"
        case .sounds:
            if startOn == false, endOn == false { return "Off" }
            return "\(startOn ? start : "—") · \(endOn ? end : "—") · \(volume)%"
        case .history:
            let count = dictation.records.entries.count
            return count == 0 ? "No dictations yet" : "\(count) \(count == 1 ? "dictation" : "dictations")"
        case .statistics:
            let month = dictationFigures(dictation.records.counts, range: .month, now: Date()).current.dictations
            return month == 0 ? "Nothing yet" : "\(month.formatted()) in 30 days"
        }
    }
}

/// A capsule with a word in it: its color at 16% under the same color, so the state is never the color alone.
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(.scaled(11).weight(.medium)).foregroundStyle(tint)
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
