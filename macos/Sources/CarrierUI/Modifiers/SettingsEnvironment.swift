import CarrierCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the row the control sits in says its value is not valid.
    @Entry public var settingsInvalid = false
    /// The page being drawn and the identifier of the group a row is in, so a row knows the anchor the search finds it by (`settingsAnchor`).
    @Entry public var settingsPage: SettingsPage?
    @Entry var settingsGroup = ""
    /// The anchor the search just took the person to: its row shows itself for a moment.
    @Entry public var settingsHighlight: String?
    /// The page is a native `Form`: its groups are sections and its rows are labeled content, and the page's reset goes to the toolbar.
    @Entry public var settingsForm = false
    /// Where a page puts what its Reset does (`SettingsPageBody`), for the window's toolbar to run after asking.
    @Entry public var settingsReset: SettingsReset?
}
