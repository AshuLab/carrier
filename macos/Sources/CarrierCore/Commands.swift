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
    guard try client.hello().protocolVersion == 1 else { throw ControlError.badLine }
    _ = try client.request(command.rawValue)
}

extension PanelSnapshot {
    /// The epics a stop would interrupt: the ones with an agent working. Those that need a person are idle.
    public var runningEpics: Int { epics.filter { $0.status == .running }.count }

    /// Stopping asks first when it would interrupt agents; with none running it goes straight through.
    public var stopNeedsConfirmation: Bool { runningEpics > 0 }
}

/// Opening the Review tab asks the engine to check GitHub now, but not more than once in `every` seconds per app run.
public struct CheckThrottle {
    private let every: TimeInterval
    private let now: () -> Date
    private var last: Date?

    public init(every: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.every = every
        self.now = now
    }

    /// True when a check may go out now; that moment starts the next wait.
    public mutating func take() -> Bool {
        let moment = now()
        if let last, moment.timeIntervalSince(last) < every { return false }
        last = moment
        return true
    }
}
