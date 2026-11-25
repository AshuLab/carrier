import SwiftUI

/// The Reset of the page that is open: set by the page when it appears, cleared when it goes, and read by the toolbar's menu.
@MainActor @Observable public final class SettingsReset {
    public private(set) var action: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    public init() {}

    public func set(_ owner: UUID, _ action: @escaping () -> Void) {
        self.owner = owner
        self.action = action
    }

    /// Only the page that set it clears it: the next page may have set its own before this one has gone.
    public func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        action = nil
    }
}
