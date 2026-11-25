import CarrierCore
import SwiftUI

// What a screen of Settings hands the window's toolbar (its Save, an action or several, the widths a row's controls share).

extension EnvironmentValues {
    /// Where a screen that edits something puts its Save for the toolbar (`SettingsSave`).
    @Entry var settingsSave: SettingsSave?
    /// Where a screen puts a toggle or action button in the toolbar (`SettingsHeaderAction`), such as Pin on a project's page.
    @Entry var settingsHeaderAction: SettingsHeaderAction?
    /// Where a screen puts several action buttons in the toolbar, on one glass capsule (`SettingsHeaderButtons`), such as Check now and Watch a project on Watching.
    @Entry var settingsHeaderButtons: SettingsHeaderButtons?
}

/// The action pills a screen puts in the Settings window's toolbar, side by side on one glass capsule: set while the screen is open, cleared when it goes.
/// Only what is shown is kept (`SettingsHeaderButton`); each one's action is looked up by its title when it is pressed.
@MainActor @Observable final class SettingsHeaderButtons {
    private(set) var buttons: [SettingsHeaderButton] = []
    @ObservationIgnored private var runs: [String: () -> Void] = [:]
    @ObservationIgnored private var owner: UUID?

    func set(_ owner: UUID, _ buttons: [(button: SettingsHeaderButton, run: () -> Void)]) {
        self.owner = owner
        runs = Dictionary(buttons.map { ($0.button.title, $0.run) }, uniquingKeysWith: { first, _ in first })
        if self.buttons != buttons.map(\.button) { self.buttons = buttons.map(\.button) }
    }

    func run(_ title: String) { runs[title]?() }

    /// Only the screen that set them clears them: the next screen may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        runs = [:]
        buttons = []
    }
}

/// A toggle or action pill a screen puts in the Settings window's toolbar (Pin on a project's page): set while the screen is open, cleared when it goes.
@MainActor @Observable final class SettingsHeaderAction {
    private(set) var title: String?
    private(set) var icon = AppIcon.pin
    private(set) var active = false
    private(set) var help = ""
    private(set) var run: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    func set(_ owner: UUID, title: String, icon: AppIcon, active: Bool, help: String = "", run: @escaping () -> Void) {
        self.owner = owner
        self.title = title
        self.icon = icon
        self.active = active
        self.help = help
        self.run = run
    }

    /// Only the screen that set it clears it: the next screen may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        title = nil
        active = false
        help = ""
        run = nil
    }
}

/// The save of the screen that is open (an account's editor): set by the screen while it has something to save, read by the toolbar's button.
@MainActor @Observable final class SettingsSave {
    private(set) var title: String?
    private(set) var icon = AppIcon.check
    private(set) var enabled = false
    private(set) var run: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    /// `icon` is the verb's own (Save a check, Add a plus), as the guide gives each button.
    func set(_ owner: UUID, title: String, icon: AppIcon = .check, enabled: Bool, run: @escaping () -> Void) {
        self.owner = owner
        self.title = title
        self.icon = icon
        self.enabled = enabled
        self.run = run
    }

    /// Only the screen that set it clears it: the next one may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        title = nil
        enabled = false
        run = nil
    }
}

/// How wide a field or a slider of a row is, the same on every page so they end and begin on one line down the card.
let settingsSelectWidth: CGFloat = 210

/// How wide a slider of a row is: the width of the selects, which is at least 200 pt, so the track is long enough to aim at.
let settingsSliderWidth: CGFloat = settingsSelectWidth
