import Foundation
import Testing
@testable import CarrierCore

/// A fake engine on a real socket with the three things the app reads and changes: its version, its intake and its executions in flight.
/// `stop` makes it go away, as the real one does; `revive` brings the next one up at the same place.
private final class WorkingEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var server: TestServer?
    private var log: [String] = []
    private var version: String
    private var paused: Bool
    private var inFlight: Int
    private let path: String

    init(version: String = "0.1.0", paused: Bool = false, inFlight: Int = 0) {
        self.version = version
        self.paused = paused
        self.inFlight = inFlight
        path = "/tmp/cc-\(UUID().uuidString.prefix(8)).sock"
        serve()
    }

    var socketPath: String { path }
    var commands: [String] { locked { log } }
    var isPaused: Bool { locked { paused } }
    var isUp: Bool { locked { server != nil } }

    func set(inFlight: Int? = nil, paused: Bool? = nil) {
        locked {
            if let inFlight { self.inFlight = inFlight }
            if let paused { self.paused = paused }
        }
    }

    /// The installed `carrier` comes up: the new engine is not paused, as a fresh one is not.
    func revive(version: String) {
        locked { self.version = version; paused = false; inFlight = 0; log.append("start") }
        serve()
    }

    func close() { locked { server?.stop(); server = nil } }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private func serve() {
        let snapshot = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json"))) as! [String: Any]
        let one = (snapshot["sessions"] as! [[String: Any]])[0]
        let server = TestServer(path: path) { [self] connection in
            let version = locked { self.version }
            connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"\(version)\",\"capabilities\":[]}\n")
            while let line = connection.readLine() {
                guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = request["id"] as? Int, let cmd = request["cmd"] as? String else { continue }
                locked { log.append(cmd) }
                switch cmd {
                case "snapshot":
                    var reply = snapshot
                    reply["paused"] = locked { paused }
                    reply["sessions"] = Array(repeating: one, count: locked { inFlight })
                    let body = String(decoding: try! JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
                    connection.send("{\"id\":\(id),\"ok\":true,\"data\":\(body)}\n")
                case "pause", "resume":
                    locked { paused = cmd == "pause" }
                    connection.send("{\"id\":\(id),\"ok\":true}\n")
                case "stop":
                    connection.send("{\"id\":\(id),\"ok\":true}\n")
                    close()
                default:
                    connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"unknown request\"}\n")
                }
            }
        }
        locked { self.server = server }
    }
}

private let quick = Duration.milliseconds(20)

@Test func anIdleOlderEngineIsStoppedAndStartedWithoutPausingIt() async {
    let engine = WorkingEngine()
    defer { engine.close() }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) {
        engine.revive(version: "0.2.0")
        return true
    }
    #expect(result == .replaced)
    #expect(engine.commands == ["snapshot", "stop", "start"])
    #expect(engine.isPaused == false)
}

@Test func aStoppedEngineIsNotStarted() async {
    let started = Locked(false)
    let result = await replaceEngine(socketPath: "/tmp/cc-nobody.sock", installed: "0.2.0", poll: quick) { started.set(true); return true }
    #expect(result == .left)
    #expect(started.value == false)
}

@Test func anEngineThatIsNotOlderIsLeftAlone() async {
    let engine = WorkingEngine(version: "0.2.0", inFlight: 1)
    defer { engine.close() }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) { true }
    #expect(result == .left)
    #expect(engine.commands == ["snapshot"])
}

@Test func aWorkingEnginePausesWaitsForTheLastExecutionAndIsReplacedUnpaused() async {
    let engine = WorkingEngine(inFlight: 2)
    defer { engine.close() }
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        engine.set(inFlight: 1)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(engine.commands.contains("stop") == false)
        engine.set(inFlight: 0)
    }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) {
        engine.revive(version: "0.2.0")
        return true
    }
    #expect(result == .replaced)
    let commands = engine.commands
    #expect(commands.first == "snapshot")
    #expect(commands.filter { $0 == "pause" }.count == 1)
    #expect(commands.firstIndex(of: "pause")! < commands.firstIndex(of: "stop")!)
    #expect(commands.suffix(2) == ["stop", "start"])
    #expect(engine.isPaused == false)
}

@Test func anEngineThePersonHadPausedIsPausedAgainAfterTheReplacement() async {
    let engine = WorkingEngine(paused: true, inFlight: 1)
    defer { engine.close() }
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        engine.set(inFlight: 0)
    }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) {
        engine.revive(version: "0.2.0")
        return true
    }
    #expect(result == .replaced)
    // it was paused already, so the app paid no pause before the stop; it pauses the new engine
    #expect(engine.commands.drop { $0 != "stop" } == ["stop", "start", "pause"])
    #expect(engine.isPaused)
}

@Test func intakeThePersonResumesDuringTheWaitIsNotPausedAgain() async {
    let engine = WorkingEngine(inFlight: 1)
    defer { engine.close() }
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        engine.set(paused: false)
        try? await Task.sleep(for: .milliseconds(100))
        engine.set(inFlight: 0)
    }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) {
        engine.revive(version: "0.2.0")
        return true
    }
    #expect(result == .replaced)
    #expect(engine.commands.filter { $0 == "pause" }.count == 1)
    #expect(engine.isPaused == false)
}

@Test func aStartThatFailsIsReported() async {
    let engine = WorkingEngine()
    defer { engine.close() }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) { false }
    #expect(result == .failed("the installed carrier did not start"))
}

@Test func anEngineThePersonStopsDuringTheWaitIsNotStarted() async {
    let engine = WorkingEngine(inFlight: 1)
    defer { engine.close() }
    let started = Locked(false)
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        engine.close()
    }
    let result = await replaceEngine(socketPath: engine.socketPath, installed: "0.2.0", poll: quick) { started.set(true); return true }
    #expect(result == .left)
    #expect(started.value == false)
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
}
