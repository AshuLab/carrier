import Foundation

// What the Behavior and Repos tabs' footer offers and says, from what Carrier is doing. The engine reads `config.json` only when it
// starts, so with Carrier running a save can also restart it.

public struct BehaviorFooter: Equatable {
    public var message: String
    /// Carrier is running: "Save and restart" is the main button and "Save only" the other; otherwise a plain "Save".
    public var offersRestart: Bool
    public var canSave: Bool
    public var canRestart: Bool
}

/// `dirty`: the values differ from the file's. `valid`: nothing the engine would refuse. `startMissing`: what Start Carrier lacks.
/// `noun` is what the tab edits, for the line about the running Carrier ("values", "list").
public func behaviorFooter(state: ConnectionState?, dirty: Bool, valid: Bool, startMissing: [String], noun: String = "values") -> BehaviorFooter {
    var running = false
    if case .running? = state { running = true }
    let canSave = dirty && valid
    guard running else {
        return BehaviorFooter(
            message: dirty ? "Carrier is stopped." : "Carrier reads these when it starts.",
            offersRestart: false, canSave: canSave, canRestart: false
        )
    }
    var message = dirty ? "Carrier is running with the old \(noun)." : "Carrier reads these when it starts."
    if dirty, startMissing.isEmpty == false { message += " Restart is off: Start Carrier needs \(startMissing.joined(separator: ", "))." }
    return BehaviorFooter(message: message, offersRestart: true, canSave: canSave, canRestart: canSave && startMissing.isEmpty)
}

/// What to say before a restart that would interrupt `epics` running epics; nil when none would be (or the person switched the question off).
public func restartWarning(epics: Int, asks: Bool) -> String? {
    guard asks, epics > 0 else { return nil }
    return "Restart interrupts \(epics) running \(epics == 1 ? "epic" : "epics"). "
        + "\(epics == 1 ? "It resumes" : "They resume") from where \(epics == 1 ? "it was" : "they were") when Carrier starts again."
}
