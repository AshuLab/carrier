import Foundation

// The confirmation before stopping Carrier, as plain values.

public let confirmStopKey = "stop.confirm"

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}
