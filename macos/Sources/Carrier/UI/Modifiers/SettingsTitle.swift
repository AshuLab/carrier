import SwiftUI

/// What a screen of a page says of itself in the window's toolbar when it is not the page's own title: a provider's name, an account's.
struct SettingsTitle: Equatable {
    let text: String
    let subtitle: String
}

struct SettingsTitleKey: SwiftUI.PreferenceKey {
    static let defaultValue: SettingsTitle? = nil
    static func reduce(value: inout SettingsTitle?, nextValue: () -> SettingsTitle?) { value = nextValue() ?? value }
}
