import AppKit
import ApplicationServices
import CarrierCore
import SwiftUI

/// The Global dictation group of the page: Dictate in any app, the switch of the shortcut that opens the widget in any app. With Dictation off the group is drawn at 40%.
struct GlobalDictationGroup: View {
    var dictation = DictationController.shared
    // the preference is read and written by the switch; this makes the group redraw when Reset changes it
    @AppStorage(AppPreferences.dictationGlobalKey) private var global = AppPreferences.defaultDictationGlobal
    @AppStorage(AppPreferences.dictationAccessibilityExplainedKey) private var explained = false
    @AppStorage(AppPreferences.dictationShortcutKey) private var shortcutText = ""
    @AppStorage(AppPreferences.dictationActivationKey) private var activation = DictationActivation.toggle
    @AppStorage(AppPreferences.dictationWidgetStyleKey) private var widgetStyle = DictationWidgetStyle.medium
    @AppStorage(AppPreferences.dictationWidgetPositionKey) private var widgetPosition = DictationWidgetPosition.bottom
    @State private var explaining = false
    /// What macOS says now; it is asked again each time Carrier comes back to the front, since the person allows it in System Settings.
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        SettingsGroup(title: "Global dictation") {
            SettingsTabRow(
                title: "Dictate in any app",
                detail: "\(AppPreferences().dictationShortcut.text) opens a widget in any app, and pastes what you said at the cursor",
                first: true
            ) {
                Toggle("Dictate in any app", isOn: switchBinding).labelsHidden().toggleStyle(.switch)
            }
            .live(.globalSwitch, enabled: dictation.enabled)
            accessibilityRow.live(.globalSwitch, enabled: dictation.enabled)
            Group {
                ShortcutRecorderRow(shortcutText: shortcutText)
                SettingsTabRow(title: "Activation", detail: "Toggle: press to start, press again to finish. Hold: speak while the keys are down") {
                    SegmentedChoice(options: [(DictationActivation.toggle, "Toggle", nil), (.hold, "Hold", nil)], selection: $activation).accessibilityLabel("Activation")
                }
                SettingsTabRow(title: "Widget style", detail: "Pill is a badge with a microphone and no text; Small, Medium and Large are a box of 2, 3 and 4 lines") {
                    SegmentedChoice(options: DictationWidgetStyle.allCases.map { ($0, $0.title, nil) }, selection: $widgetStyle).accessibilityLabel("Widget style")
                }
                SettingsTabRow(title: "Position", detail: "Top centre under the menu bar or bottom centre above the Dock, on the display of the window in front") {
                    SegmentedChoice(options: DictationWidgetPosition.allCases.map { ($0, $0.title, nil) }, selection: $widgetPosition).accessibilityLabel("Widget position")
                }
                SettingsPreview { DictationWidgetPreview(style: widgetStyle, hint: dictationHint(shortcut: AppPreferences().dictationShortcut, activation: activation)) }
            }
            .live(.globalSwitch, enabled: dictation.enabled && global)
        }
.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
        .alert("Carrier needs Accessibility", isPresented: $explaining) {
            Button("Continue") {
                explained = true
                // macOS asks, and lists Carrier in Privacy & Security › Accessibility for the person to allow
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(
                "To paste what you say into the app you are in, Carrier needs to see which field has the cursor, and to press ⌘V for you. "
                    + "It never reads what is in the fields, and it does not paste into password fields. Without it, the text goes on the clipboard instead.")
        }
    }

    private var accessibilityRow: some View {
        SettingsTabRow(
            title: "Accessibility",
            detail: trusted ? "Carrier can see which field has the cursor and paste into it" : "Without it the text goes on the clipboard instead of being pasted"
        ) {
            HStack(spacing: 8) {
                StatusChip(text: trusted ? "Allowed" : "Not allowed", tint: trusted ? .green : .orange)
                Button { FocusedField.openSettings() } label: { Label("Open System Settings", systemImage: "gearshape") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
    }

    /// Turning it on the first time explains what Accessibility is for before macOS asks.
    private var switchBinding: Binding<Bool> {
        Binding(
            get: { global },
            set: {
                global = $0
                explaining = $0 && shouldExplainAccessibility(explained: explained, trusted: AXIsProcessTrusted())
            })
    }
}

/// The Shortcut row: the keys shown, Record to press new ones (Esc or Cancel keeps the old) and, when a combination is refused, the reason. While it listens the
/// controller lets go of the registered shortcut, so pressing it records it. `shortcutText` makes the row draw again when the saved shortcut changes.
private struct ShortcutRecorderRow: View {
    let shortcutText: String
    @State private var recording = false
    @State private var monitor: Any?
    @State private var refusal: String?

    var body: some View {
        SettingsTabRow(title: "Shortcut", detail: "With Carrier in front on a session it dictates into the message box, with no widget", problem: refusal) {
            HStack(spacing: 8) {
                Text(recording ? "Press the keys…" : AppPreferences().dictationShortcut.text)
                    .font(.scaled(12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recording ? Color.themeAccent : Color.primary)
                    .frame(minWidth: 96).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(recording ? 0.12 : 0.08)))
                    .overlay { if recording { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.themeAccent, lineWidth: 1.5) } }
                    .accessibilityLabel("Dictation shortcut").accessibilityValue(recording ? "Listening for the new keys" : AppPreferences().dictationShortcut.text)
                Button { recording ? stop() : start() } label: { Label(recording ? "Cancel" : "Record", systemImage: recording ? "xmark" : "record.circle") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        refusal = nil
        recording = true
        AccessibilityNotification.Announcement("Press the new keys, or Escape to cancel").post()
        GlobalDictationController.shared.recording = true
        // the next key comes here and not to the window's shortcuts: this monitor sees it first, and it is not passed on
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels, and a combination with no modifier is told why it was refused and the recorder keeps listening
            guard event.keyCode != 53 else { stop(); return nil }
            switch recordShortcut(keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers ?? "", modifiers: .init(event.modifierFlags)) {
            case .accepted(let shortcut):
                AppPreferences().dictationShortcut = shortcut
                stop()
                AccessibilityNotification.Announcement("Shortcut set to \(shortcut.text)").post()
            case .refused(let reason):
                refusal = reason
                // a row's problem is not read aloud by itself
                AccessibilityNotification.Announcement(reason).post()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalDictationController.shared.recording = false
    }
}
