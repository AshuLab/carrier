import CarrierCore
import SwiftUI

/// The card at the top of the Dictation page: the switch and, under it, whether dictation can work now (`dictationReadiness` decides what it says): the
/// microphone, Accessibility and the speech model, with what is in the way and a button for what macOS has to be told. With the switch off it only says so.
struct DictationStatusCard: View {
    var dictation = DictationController.shared
    @AppStorage(Preference.dictationGlobal) private var global
    // the model in use is the controller's; this makes the card redraw when it changes, Reset included
    @AppStorage(Preference.dictationModel) private var savedModel
    /// What macOS says of Accessibility now; asked again each time Carrier comes back to the front, since it is allowed in System Settings.
    @State private var accessibility = AccessibilityState(trust: SystemAccessibilityTrust())

    var body: some View {
        let readiness = dictationReadiness(
            enabled: dictation.enabled, microphone: dictation.microphone, accessibilityTrusted: accessibility.trusted, globalOn: global, model: modelReadiness
        )
        HStack(alignment: .top, spacing: Tokens.Space.s14) {
            Glyph(symbol(readiness.tone), size: 18, bold: true).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(tint(readiness.tone))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Text(readiness.title).font(.scaled(15).weight(.bold))
                if readiness.items.isEmpty == false {
                    FlowLayout(spacing: Tokens.Space.s14) {
                        ForEach(readiness.items) { item in
                            HStack(spacing: Tokens.Space.s6) {
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
                    // each says what it opens, so two of them side by side are told apart and the spoken name is the one on the button
                    Button { open(fix) } label: { Label(fix == .openMicrophoneSettings ? "Open Microphone Settings" : "Open Accessibility Settings", icon: .settings).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
            Spacer(minLength: 8)
            Toggle("Dictation", isOn: Binding(get: { dictation.enabled }, set: { dictation.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
        }
        .padding(Tokens.Space.s14).frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in accessibility.refresh() }
        .accessibilityElement(children: .contain)
        // the search's "Microphone" lands on the card
        .settingsAnchored("microphone", group: "dictation")
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

    private func symbol(_ tone: DictationReadiness.Tone) -> AppIcon {
        switch tone {
        case .off: .power
        case .ready: .check
        case .attention, .blocked: .exclamation
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
