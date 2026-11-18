import CarrierCore
import SwiftUI

/// The Dictation group of the page: the switch, the speech model, the language, when the model is kept in memory and the microphone's state. With the switch off the rows under it are drawn at 40%.
struct DictationGroup: View {
    var dictation = DictationController.shared
    // the choices are the controller's to read and write; these make the group redraw when they change, Reset included
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationLanguageKey) private var savedLanguage: String?
    @AppStorage(AppPreferences.dictationKeepReadyKey) private var savedKeepReady = AppPreferences.defaultDictationKeepReady
    @AppStorage(AppPreferences.dictationReleaseAfterKey) private var savedReleaseAfter = AppPreferences.defaultDictationReleaseAfter

    var body: some View {
        let enabled = dictation.enabled
        SettingsGroup(title: "Dictation") {
            SettingsTabRow(
                title: "Dictation", detail: enabled ? "The microphone shows in the message box" : "Off: no microphone in the message box, nothing listens", first: true
            ) {
                Toggle("Dictation", isOn: Binding(get: { dictation.enabled }, set: { dictation.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
            }
            .live(.enabledSwitch, enabled: enabled)
            speechModelRow.live(.speechModel, enabled: enabled)
            languageRow.live(.language, enabled: enabled)
            SettingsTabRow(title: "Keep the speech model ready", detail: "Loads it when Carrier opens, so the first dictation does not wait for it") {
                Toggle("Keep the speech model ready", isOn: Binding(get: { AppPreferences().dictationKeepReady }, set: { dictation.setKeepReady($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            .live(.keepReady, enabled: enabled)
            SettingsTabRow(title: "Release the model after", detail: "Without dictating, to give its memory back; the next dictation loads it again") {
                ChoicePopUp(
                    label: "Release the model after", options: dictationReleaseChoices.map { (value: $0.minutes, title: $0.title) },
                    selection: Binding(get: { AppPreferences().dictationReleaseAfter }, set: { dictation.setReleaseAfter($0) })
                )
            }
            .live(.releaseAfter, enabled: enabled)
            microphoneRow.live(.microphone, enabled: enabled)
        }
    }

    @ViewBuilder private var speechModelRow: some View {
        let choice = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:))
        if let shown = choice.shown {
            SettingsTabRow(
                title: "Speech model",
                detail: choice.missing.map { "\($0.name) is not on disk: download it in the table or choose another" } ?? "\(shown.recognizer.title) · \(shown.partial.line)"
            ) {
                ChoicePopUp(
                    label: "Speech model", options: choice.options.map { (value: $0.id, title: $0.name) },
                    selection: Binding(get: { shown.id }, set: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) })
                )
            }
        }
    }

    @ViewBuilder private var languageRow: some View {
        if let choices = dictation.languages {
            SettingsTabRow(title: "Language", detail: choices.hint) {
                ChoicePopUp(
                    label: "Language", options: choices.offered.map { (value: $0, title: languageName($0)) },
                    selection: Binding(get: { choices.selected }, set: { dictation.choose(language: $0) })
                )
            }
        }
    }

    private var microphoneRow: some View {
        let microphone = dictation.microphone
        return SettingsTabRow(
            title: "Microphone",
            detail: microphone == .denied ? "macOS has it blocked for Carrier, so dictation cannot listen" : "Carrier asks macOS the first time you dictate"
        ) {
            HStack(spacing: 8) {
                switch microphone {
                case .allowed: StatusChip(text: "Allowed", tint: .green)
                case .denied:
                    StatusChip(text: "Not allowed", tint: .orange)
                    Button { MicrophoneAccess.openSystemSettings() } label: { Label(MicrophoneBlockedPopover.button, systemImage: "gearshape") }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                case .notAsked: StatusChip(text: "Not asked yet", tint: .secondary)
                }
            }
        }
    }

    private func languageName(_ code: String) -> String {
        code == automaticLanguage ? "Automatic" : Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}

private extension PartialText {
    var line: String { self == .atTheEnd ? "text arrives when you stop" : "text appears as you speak" }
}
