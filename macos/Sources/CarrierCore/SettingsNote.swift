import Foundation

// What the Repos page says about when Carrier uses a repo that is saved (docs/specs/settings-apply-without-restart.md): that it
// applies it to the next epic when the connected engine lists `reload`, else that it reads it when it starts, which is true of a
// stopped Carrier and of an engine too old to reload. A save the engine did not apply says so, whatever the engine can do.

/// `canReload`: the hello of the engine the app talks to lists `reload`. `kept`: the last save came back unapplied (the engine refused it
/// or did not answer), so the repo is not in use.
public func settingsNote(state: ConnectionState?, canReload: Bool, kept: Bool = false) -> String {
    if kept { return "Not in use: Carrier kept its previous settings" }
    if case .running? = state, canReload { return "Carrier applies this repo to the next epic" }
    return "Carrier reads this repo when it starts"
}
