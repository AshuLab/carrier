import Foundation

// What the Behavior and Repos pages say about when Carrier uses what is saved (docs/specs/settings-apply-without-restart.md): that it
// applies it to the next epic when the connected engine lists `reload`, else that it reads it when it starts, which is true of a stopped
// Carrier and of an engine too old to reload.

public enum SettingsNoteSubject {
    /// the Behavior page's values
    case values
    /// a repo the engine has not loaded
    case repo
}

/// `canReload`: the hello of the engine the app talks to lists `reload`.
public func settingsNote(_ subject: SettingsNoteSubject, state: ConnectionState?, canReload: Bool) -> String {
    var applies = false
    if case .running? = state { applies = canReload }
    switch (subject, applies) {
    case (.values, true): return "Carrier applies these to the next epic"
    case (.values, false): return "Carrier reads these when it starts"
    case (.repo, true): return "Carrier applies it to the next epic"
    case (.repo, false): return "Carrier reads it when it starts"
    }
}
