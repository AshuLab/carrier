import Foundation

// The engine older than the installed `carrier`, replaced when it is free: it was running and has no execution in flight.
// A stopped engine is never started here (0010). While executions run, intake is paused so the queue cannot keep it busy.

public enum EngineReplaced: Equatable {
    /// Nothing was changed: stopped, not older, or gone while the app waited.
    case left
    case replaced
    /// The engine was not stopped, or was stopped and did not come up (the start shows its own alert).
    case failed(String)
}

private struct EngineState {
    let version: String
    let paused: Bool
    let inFlight: Int
}

private func readEngine(_ path: String) throws -> EngineState {
    guard let client = ControlClient.connect(path: path) else { throw ControlError.closed }
    defer { client.close() }
    let version = try client.supportedHello().version ?? ""
    let snapshot = try decodeSnapshot(client.request("snapshot"))
    return EngineState(version: version, paused: snapshot.paused, inFlight: snapshot.sessions?.count ?? snapshot.runningEpics)
}

/// Reads the engine again every `poll` while it works, so the app is not blocked. `beforeStop` is called right before the stop, `start`
/// starts the installed `carrier`. The intake the person had paused is paused again on the new engine; one the person resumed during the
/// wait stays resumed. An engine that cannot be read (stopped by the person, or too busy to answer) ends the wait with `.left`.
// ponytail: an execution that starts between the last read and the stop is closed with the engine; a guard in the engine if it bites
// ponytail: an app that quits during the wait leaves intake paused, and the next launch reads that as the person's
public func replaceEngine(
    socketPath: String, installed: String, poll: Duration = .seconds(5), beforeStop: () -> Void = {}, start: () async -> Bool
) async -> EngineReplaced {
    guard var state = try? readEngine(socketPath) else { return .left }
    let wasPaused = state.paused
    var pausedByApp = false
    while true {
        switch engineReplacement(running: state.version, installed: installed, executionsInFlight: state.inFlight) {
        case .keep: return .left
        case .replace: break
        case .pauseAndWait:
            if state.paused == false, pausedByApp == false {
                pausedByApp = true
                try? send(.pause, socketPath: socketPath)
            }
            try? await Task.sleep(for: poll)
            guard let next = try? readEngine(socketPath) else { return .left }
            state = next
            continue
        }
        break
    }
    beforeStop()
    do { try send(.stop, socketPath: socketPath) } catch { return .failed("the engine did not accept the stop: \(error)") }
    // ponytail: polls the socket for 15 s, no signal from the engine that it is gone
    let deadline = Date().addingTimeInterval(15)
    while ControlClient.connect(path: socketPath) != nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(250)) }
    // a socket that still answers would make the start look like it worked
    guard ControlClient.connect(path: socketPath) == nil else { return .failed("the engine did not go away after the stop") }
    guard await start() else { return .failed("the installed carrier did not start") }
    if wasPaused, state.paused { try? send(.pause, socketPath: socketPath) }
    return .replaced
}
