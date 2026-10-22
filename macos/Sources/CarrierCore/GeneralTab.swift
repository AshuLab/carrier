import Foundation
import Observation

// The General tab of Settings as plain values: open at login, the confirmation before stopping, and the advanced rows
// (docs/specs/macos-app-redesign.md, story 30; docs/research/macos-app-login-item.md).

public let confirmStopKey = "stop.confirm"

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}

/// `SMAppService.Status`, as the login item reports it.
public enum LoginItemStatus: Equatable {
    case enabled, notRegistered, requiresApproval, notFound
}

/// The app's login item; the real one is `SMAppService.mainApp`, tests use a stub.
public protocol LoginItem {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// The Open at login row. The switch follows `status`, read each time, never a stored flag: the person can change it in
/// System Settings. `notFound` is a bundle never registered, so it is an ordinary off switch; only running outside a bundle
/// (nothing to register) disables the row.
@Observable public final class OpenAtLogin {
    private let item: LoginItem
    private let bundled: Bool
    public private(set) var status: LoginItemStatus
    /// Under the switch: what went wrong with the last attempt.
    public private(set) var error: String?

    public init(item: LoginItem, bundled: Bool) {
        self.item = item
        self.bundled = bundled
        status = item.status
    }

    public var enabled: Bool { bundled }
    public var isOn: Bool { status == .enabled }
    public var needsApproval: Bool { status == .requiresApproval }

    public var note: String? {
        if bundled == false { return "Only available from Carrier.app" }
        if needsApproval { return "Carrier is waiting for your approval in Login Items" }
        return error
    }

    public func refresh() { status = item.status }

    public func set(_ on: Bool) {
        guard bundled else { return }
        error = nil
        do {
            if on { try item.register() } else { try item.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
        if on, error == nil, status == .notFound {
            error = "Carrier can't register itself from here, move it to /Applications and try again"
        }
    }

    public func openSystemSettings() { item.openSystemSettings() }
}
