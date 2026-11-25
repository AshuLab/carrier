import CarrierCore

extension KeepAwakeController {
    /// The app's one controller: IOKit's assertions, a Carbon hot key and the system's notification centre.
    static let shared = KeepAwakeController(assertion: SystemKeepAwakeAssertion(), shortcuts: SystemGlobalShortcut(), centre: SystemNotificationCentre.shared)
}
