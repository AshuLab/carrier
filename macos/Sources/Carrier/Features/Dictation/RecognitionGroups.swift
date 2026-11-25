import CarrierCore
import SwiftUI

/// The Language row of Speech recognition: what the chosen model can listen to, with a line that says why Automatic is or is not there.
struct LanguageGroup: View {
    var dictation = DictationController.shared
    // the choices are the controller's to read and write; these make the row redraw when they change, Reset included
    @AppStorage(Preference.dictationModel) private var savedModel
    @AppStorage(Preference.dictationLanguage) private var savedLanguage

    var body: some View {
        SettingsGroup(title: "") {
            if let choices = dictation.languages {
                SettingsTabRow(id: "language", title: "Language", detail: choices.hint, first: true) {
                    ChoicePopUp(
                        label: "Language", options: choices.offered.map { (value: $0, title: dictationLanguageName($0)) },
                        selection: Binding(get: { choices.selected }, set: { dictation.choose(language: $0) })
                    )
                }
            }
        }
    }
}

/// A language as the page says it: Automatic, or its name in the language of the Mac.
func dictationLanguageName(_ code: String) -> String {
    code == automaticLanguage ? "Automatic" : Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
}

/// The Memory group: when the model is kept in memory. With Dictation off both rows are drawn at 40%.
struct MemoryGroup: View {
    var dictation = DictationController.shared
    @AppStorage(Preference.dictationModelKeepReady) private var savedKeepReady
    @AppStorage(Preference.dictationModelReleaseAfter) private var savedReleaseAfter

    var body: some View {
        let enabled = dictation.enabled
        SettingsGroup(id: "memory", title: "Memory", footer: "It is released 5, 15, 30 or 60 minutes after the last dictation, or never.") {
            SettingsTabRow(id: "keep-the-speech-model-ready", title: "Keep the speech model ready", detail: "Loads it when Carrier opens, so the first dictation does not wait for it", first: true) {
                Toggle("Keep the speech model ready", isOn: Binding(get: { AppPreferences().dictationKeepReady }, set: { dictation.setKeepReady($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            .live(.keepReady, enabled: enabled)
            SettingsTabRow(id: "release-the-model-after", title: "Release the model after", detail: "Without dictating, to give its memory back; the next dictation loads it again") {
                ChoicePopUp(
                    label: "Release the model after", options: dictationReleaseChoices.map { (value: $0.minutes, title: $0.title) },
                    selection: Binding(get: { AppPreferences().dictationReleaseAfter }, set: { dictation.setReleaseAfter($0) })
                )
            }
            .live(.releaseAfter, enabled: enabled)
        }
    }
}
