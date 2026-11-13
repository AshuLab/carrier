import CarrierCore
import SwiftUI

/// The Dictation page: the switch, the speech model, the language, the microphone's state, the speech models table and Storage. With the switch off the rows under it are
/// drawn at 40% and take no clicks (`dictationRowIsLive`).
struct DictationTabView: View {
    var dictation = DictationController.shared
    // the choices are the controller's to read and write; these make the page redraw when they change, Reset included
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationLanguageKey) private var savedLanguage: String?
    @State private var filter: RecognizerID?
    /// The id of the model the trash asked to delete, while the confirmation is open.
    @State private var deleting: String?

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
            SettingsGroup(title: "Speech models", accessory: {
                HStack(spacing: 6) {
                    FilterChip(title: "All", on: filter == nil) { filter = nil }
                    ForEach(RecognizerID.allCases, id: \.self) { recognizer in
                        FilterChip(title: recognizer.title, on: filter == recognizer) { filter = filter == recognizer ? nil : recognizer }
                    }
                }
                .padding(.trailing, 14)
            }, content: {
                SpeechModelsTable(
                    rows: dictation.rows(filter: filter), choose: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) },
                    download: dictation.store.download, cancel: dictation.store.cancel, delete: { deleting = $0 }
                )
            })
            .live(.modelsTable, enabled: enabled)
            SettingsGroup(title: "Storage") {
                SettingsTabRow(title: "Downloaded models", detail: "\(formatModelSize(dictation.store.usedBytes)) in the Carrier folder", first: true) {
                    Button { dictation.showModelsInFinder() } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
            .live(.storage, enabled: enabled)
        }
        .alert(
            "Delete \(deleting.flatMap(modelNamed) ?? "the model")?", isPresented: Binding(get: { deleting != nil }, set: { if $0 == false { deleting = nil } })
        ) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let id = deleting { dictation.store.delete(id) }
                deleting = nil
            }
        } message: {
            Text("It frees its space on this Mac. You can download it again.")
        }
    }

    private func modelNamed(_ id: String) -> String? { dictation.models.first { $0.id == id }?.name }

    @ViewBuilder private var speechModelRow: some View {
        let choice = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:))
        if let shown = choice.shown {
            SettingsTabRow(
                title: "Speech model",
                detail: choice.missing.map { "\($0.name) is not on disk: download it in the table or choose another" } ?? "\(shown.recognizer.title) · \(shown.partial.line)"
            ) {
                ChoicePopUp(
                    label: "Speech model", options: choice.options.map { (value: $0.id, title: $0.name) },
                    selection: Binding(get: { shown.id }, set: { id in dictation.models.first { $0.id == id }.map(dictation.choose(model:)) }), width: 200
                )
            }
        }
    }

    @ViewBuilder private var languageRow: some View {
        if let choices = dictation.languages {
            SettingsTabRow(title: "Language", detail: choices.hint) {
                ChoicePopUp(
                    label: "Language", options: choices.offered.map { (value: $0, title: languageName($0)) },
                    selection: Binding(get: { choices.selected }, set: { dictation.choose(language: $0) }), width: 200
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

private extension View {
    /// A row the switch can dim: at 40% and with no clicks, for keyboard and VoiceOver too, while Dictation is off.
    func live(_ row: DictationRow, enabled: Bool) -> some View {
        let live = dictationRowIsLive(row, enabled: enabled)
        return opacity(live ? 1 : 0.4).disabled(live == false)
    }
}

private extension PartialText {
    var line: String { self == .atTheEnd ? "text arrives when you stop" : "text appears as you speak" }
}
