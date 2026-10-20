import Foundation

/// The commands of the control socket that change something; the allowlist of what the menu can send.
public enum Command: String {
    case pause, resume, checkNow, stop
}

/// Sends one command on a connection of its own (the monitor's belongs to its thread) and waits for the reply.
/// Blocking: call it off the main thread. `stop` is answered with ok first and the connection closes after.
public func send(_ command: Command, socketPath: String) throws {
    guard let client = ControlClient.connect(path: socketPath) else { throw ControlError.closed }
    defer { client.close() }
    guard try client.hello() == 1 else { throw ControlError.badLine }
    _ = try client.request(command.rawValue)
}

extension PanelSnapshot {
    /// The epics a stop would interrupt: the ones with an agent working. Those that need a person are idle.
    public var runningEpics: Int { epics.filter { $0.status == .running }.count }

    /// Stopping asks first when it would interrupt agents; with none running it goes straight through.
    public var stopNeedsConfirmation: Bool { runningEpics > 0 }
}
