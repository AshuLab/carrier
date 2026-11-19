import ApplicationServices
import CarrierCore
import SwiftUI

/// The card at the top of the Dictation page: the switch and, under it, whether dictation can work now (`dictationReadiness` decides what it says): the
/// microphone, Accessibility and the speech model, with what is in the way and a button for what macOS has to be told. With the switch off it only says so.
struct DictationStatusCard: View {
    var dictation = DictationController.shared
    @AppStorage(AppPreferences.dictationGlobalKey) private var global = AppPreferences.defaultDictationGlobal
    /// What macOS says of Accessibility now; asked again each time Carrier comes back to the front, since it is allowed in System Settings.
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        let readiness = dictationReadiness(
            enabled: dictation.enabled, microphone: dictation.microphone, accessibilityTrusted: trusted, globalOn: global, model: modelReadiness
        )
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol(readiness.tone)).font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(tint(readiness.tone))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(readiness.title).font(.scaled(15).weight(.bold))
                if readiness.items.isEmpty == false {
                    FlowLayout(spacing: 14) {
                        ForEach(readiness.items) { item in
                            HStack(spacing: 6) {
                                Circle().fill(color(item.mark)).frame(width: 7, height: 7).accessibilityHidden(true)
                                Text("\(item.title) · \(item.state)").font(.scaled(12)).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ForEach(readiness.notes, id: \.self) { note in
                    Text(note).font(.scaled(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(readiness.items.compactMap(\.fix), id: \.self) { fix in
                    Button { open(fix) } label: { Label(MicrophoneBlockedPopover.button, systemImage: "gearshape").labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        .accessibilityLabel(fix == .openMicrophoneSettings ? "Open System Settings for the microphone" : "Open System Settings for Accessibility")
                }
            }
            Spacer(minLength: 8)
            Toggle("Dictation", isOn: Binding(get: { dictation.enabled }, set: { dictation.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
        .accessibilityElement(children: .contain)
    }

    /// The model the page would use: the chosen one when it is on disk, and, when it is not, which one is missing (or on its way).
    private var modelReadiness: DictationModelReadiness {
        let choice = speechModelChoice(models: dictation.models, chosen: dictation.chosenModel, state: dictation.store.state(of:))
        if let missing = choice.missing {
            if case .downloading = dictation.store.state(of: missing) { return .downloading(missing.name) }
            return .missing(missing.name)
        }
        return .ready(choice.shown?.name ?? "Apple")
    }

    private func open(_ fix: DictationReadiness.Fix) {
        switch fix {
        case .openMicrophoneSettings: MicrophoneAccess.openSystemSettings()
        case .openAccessibilitySettings: FocusedField.openSettings()
        }
    }

    private func symbol(_ tone: DictationReadiness.Tone) -> String {
        switch tone {
        case .off: "power"
        case .ready: "checkmark"
        case .attention, .blocked: "exclamationmark"
        }
    }

    private func tint(_ tone: DictationReadiness.Tone) -> Color {
        switch tone {
        case .off: .gray
        case .ready: .green
        case .attention, .blocked: .orange
        }
    }

    private func color(_ mark: DictationReadiness.Mark) -> Color {
        switch mark {
        case .ok: .green
        case .attention: .orange
        case .off: .gray
        }
    }
}

/// The Language row of Speech recognition: what the chosen model can listen to, with a line that says why Automatic is or is not there.
struct LanguageGroup: View {
    var dictation = DictationController.shared
    // the choices are the controller's to read and write; these make the row redraw when they change, Reset included
    @AppStorage(AppPreferences.dictationModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationLanguageKey) private var savedLanguage: String?

    var body: some View {
        SettingsGroup(title: "") {
            if let choices = dictation.languages {
                SettingsTabRow(title: "Language", detail: choices.hint, first: true) {
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
    @AppStorage(AppPreferences.dictationKeepReadyKey) private var savedKeepReady = AppPreferences.defaultDictationKeepReady
    @AppStorage(AppPreferences.dictationReleaseAfterKey) private var savedReleaseAfter = AppPreferences.defaultDictationReleaseAfter

    var body: some View {
        let enabled = dictation.enabled
        SettingsGroup(title: "Memory", footer: "It is released 5, 15, 30 or 60 minutes after the last dictation, or never.") {
            SettingsTabRow(title: "Keep the speech model ready", detail: "Loads it when Carrier opens, so the first dictation does not wait for it", first: true) {
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
        }
    }
}
