import SwiftUI

/// The Reset of the page that is open: set by the page when it appears, cleared when it goes, and read by the toolbar's menu.
@MainActor @Observable final class SettingsReset {
    private(set) var action: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    func set(_ owner: UUID, _ action: @escaping () -> Void) {
        self.owner = owner
        self.action = action
    }

    /// Only the page that set it clears it: the next page may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        action = nil
    }
}
