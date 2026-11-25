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
                SettingsTabRow(id: "language", title: Copy.dictationLanguage(), detail: choices.hint, first: true) {
                    ChoicePopUp(
                        label: Copy.dictationLanguage(), options: choices.offered.map { (value: $0, title: dictationLanguageName($0)) },
                        selection: Binding(get: { choices.selected }, set: { dictation.choose(language: $0) })
                    )
                }
            }
        }
    }
}

/// A language as the page says it: Automatic, or its name in the language of the Mac.
func dictationLanguageName(_ code: String) -> String {
    code == automaticLanguage ? Copy.dictationLanguageAutomatic() : Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
}

/// The Memory group: when the model is kept in memory. With Dictation off both rows are drawn at 40%.
struct MemoryGroup: View {
    var dictation = DictationController.shared
    @AppStorage(Preference.dictationModelKeepReady) private var savedKeepReady
    @AppStorage(Preference.dictationModelReleaseAfter) private var savedReleaseAfter

    var body: some View {
        let enabled = dictation.enabled
        SettingsGroup(id: "memory", title: Copy.dictationGroupMemory(), footer: Copy.dictationMemoryFooter()) {
            SettingsTabRow(id: "keep-the-speech-model-ready", title: Copy.dictationKeepReady(), detail: Copy.dictationKeepReadyDetail(), first: true) {
                Toggle(Copy.dictationKeepReady(), isOn: Binding(get: { AppPreferences().dictationKeepReady }, set: { dictation.setKeepReady($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            .live(.keepReady, enabled: enabled)
            SettingsTabRow(id: "release-the-model-after", title: Copy.dictationReleaseTitle(), detail: Copy.dictationReleaseDetail()) {
                ChoicePopUp(
                    label: Copy.dictationReleaseTitle(), options: dictationReleaseChoices.map { (value: $0.minutes, title: $0.title()) },
                    selection: Binding(get: { AppPreferences().dictationReleaseAfter }, set: { dictation.setReleaseAfter($0) })
                )
            }
            .live(.releaseAfter, enabled: enabled)
        }
    }
}
