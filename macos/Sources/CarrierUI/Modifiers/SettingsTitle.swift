import SwiftUI

/// What a screen of a page says of itself in the window's toolbar when it is not the page's own title: a provider's name, an account's.
public struct SettingsTitle: Equatable {
    public let text: String
    public let subtitle: String

    public init(text: String, subtitle: String) { self.text = text; self.subtitle = subtitle }
}

public struct SettingsTitleKey: SwiftUI.PreferenceKey {
    public static let defaultValue: SettingsTitle? = nil
    public static func reduce(value: inout SettingsTitle?, nextValue: () -> SettingsTitle?) { value = nextValue() ?? value }
}
