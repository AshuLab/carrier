import CarrierCore
import SwiftUI

/// The Global dictation group of the page: Dictate in any app, the switch of the shortcut that opens the widget in any app. With Dictation off the group is drawn at 40%.
struct GlobalDictationGroup: View {
    var dictation = DictationController.shared
    // the preference is read and written by the switch; this makes the group redraw when Reset changes it
    @AppStorage(AppPreferences.dictationGlobalKey) private var global = AppPreferences.defaultDictationGlobal

    var body: some View {
        SettingsGroup(title: "Global dictation") {
            SettingsTabRow(
                title: "Dictate in any app",
                detail: "\(GlobalHotKey.Shortcut.dictation.text) opens a widget in any app, and the same keys paste what you said at the cursor",
                first: true
            ) {
                Toggle("Dictate in any app", isOn: $global).labelsHidden().toggleStyle(.switch)
            }
            .live(.globalSwitch, enabled: dictation.enabled)
        }
    }
}
