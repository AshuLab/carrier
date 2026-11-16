import ApplicationServices
import CarrierCore
import SwiftUI

/// The Global dictation group of the page: Dictate in any app, the switch of the shortcut that opens the widget in any app. With Dictation off the group is drawn at 40%.
struct GlobalDictationGroup: View {
    var dictation = DictationController.shared
    // the preference is read and written by the switch; this makes the group redraw when Reset changes it
    @AppStorage(AppPreferences.dictationGlobalKey) private var global = AppPreferences.defaultDictationGlobal
    @AppStorage(AppPreferences.dictationAccessibilityExplainedKey) private var explained = false
    @State private var explaining = false

    var body: some View {
        SettingsGroup(title: "Global dictation") {
            SettingsTabRow(
                title: "Dictate in any app",
                detail: "\(GlobalHotKey.Shortcut.dictation.text) opens a widget in any app, and the same keys paste what you said at the cursor",
                first: true
            ) {
                Toggle("Dictate in any app", isOn: switchBinding).labelsHidden().toggleStyle(.switch)
            }
            .live(.globalSwitch, enabled: dictation.enabled)
        }
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
