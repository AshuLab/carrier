import Foundation

// What the Repos page says about when Carrier uses a repo that is saved (docs/specs/settings-apply-without-restart.md): that it
// applies it to the next epic when the connected engine lists `reload`, else that it reads it when it starts, which is true of a
// stopped Carrier and of an engine too old to reload.

/// `canReload`: the hello of the engine the app talks to lists `reload`.
public func settingsNote(state: ConnectionState?, canReload: Bool) -> String {
    if case .running? = state, canReload { return "Carrier applies it to the next epic" }
    return "Carrier reads it when it starts"
}
