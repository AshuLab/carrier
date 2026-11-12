import CarrierCore
import SwiftUI

/// The Dictation page: the switch, the speech model, the language and the microphone's state. With the switch off the rows under it are
/// drawn at 40% and take no clicks (`dictationRowIsLive`).
struct DictationTabView: View {
    var dictation = DictationController.shared
    // the choices are the controller's to read and write; these make the page redraw when they change, Reset included
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationLanguageKey) private var savedLanguage: String?

    var body: some View {
        let enabled = dictation.enabled
        SettingsPageBody(reset: { dictation.reset() }) {
            SettingsGroup(title: "Dictation") {
                SettingsTabRow(
                    title: "Dictation", detail: enabled ? "The microphone shows in the message box" : "Off: no microphone in the message box, nothing listens", first: true
                ) {
                    Toggle("Dictation", isOn: Binding(get: { dictation.enabled }, set: { dictation.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
                }
                .live(.enabledSwitch, enabled: enabled)
                speechModelRow.live(.speechModel, enabled: enabled)
                languageRow.live(.language, enabled: enabled)
                microphoneRow.live(.microphone, enabled: enabled)
            }
        }
    }

    @ViewBuilder private var speechModelRow: some View {
        if let model = dictation.model {
            SettingsTabRow(title: "Speech model", detail: "\(model.recognizer.title) · \(model.partial.line)") {
                Picker("Speech model", selection: Binding(get: { model.id }, set: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) })) {
                    ForEach(dictation.models) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    @ViewBuilder private var languageRow: some View {
        if let choices = dictation.languages {
            SettingsTabRow(title: "Language", detail: choices.hint) {
                Picker("Language", selection: Binding(get: { choices.selected }, set: { dictation.choose(language: $0) })) {
                    ForEach(choices.offered, id: \.self) { Text(languageName($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
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
                    StatusChip(text: "Not allowed", tint: .red)
                    Button(MicrophoneBlockedPopover.button) { MicrophoneAccess.openSystemSettings() }
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

/// A capsule with a word in it: its color at 16% under the same color, so the state is never the color alone.
private struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

private extension View {
    /// A row the switch can dim: at 40% and with no clicks, for keyboard and VoiceOver too, while Dictation is off.
    func live(_ row: DictationRow, enabled: Bool) -> some View {
        let live = dictationRowIsLive(row, enabled: enabled)
        return opacity(live ? 1 : 0.4).disabled(live == false)
    }
}

private extension RecognizerID {
    var title: String {
        switch self {
        case .apple: "Apple"
        case .fluidAudio: "FluidAudio"
        case .whisper: "Whisper"
        }
    }
}

private extension PartialText {
    var line: String { self == .atTheEnd ? "text arrives when you stop" : "text appears as you speak" }
}
