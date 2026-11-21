import Foundation
import Testing
@testable import CarrierCore

private let snapshotURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

private func snapshotJSON(now: Int) throws -> String {
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any])
    json["now"] = now
    return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
}

private func nowOf(_ state: ConnectionState) -> Int? {
    if case .running(let snapshot) = state { return snapshot.now }
    return nil
}

/// An engine that answers `snapshot` with a `now` that counts the answers, and counts what it is asked, by connection and by command.
/// `files` can be held, as the engine holds it while git works.
private final class ScriptEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var connected = 0
    private var asked: [String: Int] = [:]
    private var snapshots = 0
    private var live: [ServerConnection] = []
    private var commandsByConnection: [Int: [String]] = [:]
    private var gate: DispatchSemaphore?
    private var firstSnapshotGate: DispatchSemaphore?
    private(set) var server: TestServer!

    init(path: String? = nil) {
        let hello = "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"0.2.0\",\"capabilities\":[\"epic\",\"files\"]}\n"
        server = TestServer(path: path) { [self] connection in
            let number = locked { () -> Int in
                connected += 1
                live.append(connection)
                return connected
            }
            defer { locked { live.removeAll { $0.fd == connection.fd } } }
            connection.send(hello)
            while let line = connection.readLine() {
                let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
                guard let id = request?["id"] as? Int, let command = request?["cmd"] as? String else { return }
                let (now, wait) = locked { () -> (Int, DispatchSemaphore?) in
                    asked[command, default: 0] += 1
                    commandsByConnection[number, default: []].append(command)
                    if command == "snapshot" { snapshots += 1 }
                    return (snapshots, command == "files" ? gate : (command == "snapshot" && snapshots == 1 ? firstSnapshotGate : nil))
                }
                wait?.wait()
                if command == "snapshot" {
                    connection.send("{\"id\":\(id),\"ok\":true,\"data\":\((try? snapshotJSON(now: now)) ?? "{}")}\n")
                } else {
                    connection.send("{\"id\":\(id),\"ok\":true,\"data\":null}\n")
                }
            }
        }
    }

    var path: String { server.path }
    var connections: Int { locked { connected } }
    var open: Int { locked { live.count } }
    func asks(_ command: String) -> Int { locked { asked[command, default: 0] } }
    /// The commands each connection (numbered from 1, in the order they were accepted) was sent.
    var commands: [Int: [String]] { locked { commandsByConnection } }
    func hold() { locked { gate = DispatchSemaphore(value: 0) } }
    /// The engine does not answer the first `snapshot` until `release`.
    func holdFirstSnapshot() { locked { firstSnapshotGate = DispatchSemaphore(value: 0) } }
    func release() {
        let held = locked { () -> [DispatchSemaphore?] in
            defer { (gate, firstSnapshotGate) = (nil, nil) }
            return [gate, firstSnapshotGate]
        }
        held.forEach { $0?.signal() }
    }

    /// The engine goes away: what is connected is closed and no one is taken.
    func stop() {
        server.stop()
        locked { live.forEach { _ = Darwin.shutdown($0.fd, SHUT_RDWR) } }
    }

    private func locked<Value>(_ body: () -> Value) -> Value { lock.lock(); defer { lock.unlock() }; return body() }
}

private func until(_ done: @escaping () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if done() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// One listener of the link, which keeps its place in the stream between reads. Letting go of it is leaving.
/// A read that runs out of time ends the stream (a cancelled `next` does), so only a test that expects an answer waits with a bound.
private final class Listener: @unchecked Sendable {
    private var iterator: AsyncStream<ConnectionState>.AsyncIterator

    init(_ stream: AsyncStream<ConnectionState>) { iterator = stream.makeAsyncIterator() }

    /// The next `count` states, or fewer when `seconds` pass first.
    func take(_ count: Int, seconds: Double = 5) async -> [ConnectionState] {
        await withTaskGroup(of: [ConnectionState]?.self) { group in
            group.addTask {
                var got: [ConnectionState] = []
                while got.count < count, let state = await self.iterator.next() { got.append(state) }
                return got
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    /// Whether a `.stopped` comes within `seconds`.
    func untilStopped(seconds: Double = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            guard let state = await take(1, seconds: seconds).first else { return false }
            if state == .stopped { return true }
        }
        return false
    }
}

/// A link that reads at the pace the test gives: an hour by default, so a read is made only when the test asks (`refresh`).
private func link(_ engine: ScriptEngine, pace: TimeInterval = 3600) -> EngineLink {
    EngineLink(path: { engine.path }, pace: { pace }, retry: 0.02, log: { _ in })
}

// One owner for the menu and the window: one connection, one snapshot a read.

@Test func twoListenersShareOneConnectionAndOneSnapshotARead() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine)
    let (menu, window) = (Listener(link.states()), Listener(link.states()))
    let (m1, w1) = await (menu.take(1).compactMap(nowOf), window.take(1).compactMap(nowOf))
    #expect(m1 == [1] && w1 == [1])
    link.refresh()
    let (m2, w2) = await (menu.take(1).compactMap(nowOf), window.take(1).compactMap(nowOf))
    #expect(m2 == [2] && w2 == [2])
    #expect(engine.asks("snapshot") == 2 && engine.connections == 1)
}

@Test func aListenerThatJoinsLateGetsTheLastStateAtOnceWithoutAnotherRead() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine)
    let menu = Listener(link.states())
    #expect(await menu.take(1).compactMap(nowOf) == [1])
    let window = Listener(link.states())
    #expect(await window.take(1, seconds: 1).compactMap(nowOf) == [1])
    #expect(engine.asks("snapshot") == 1)
}

@Test func aRefreshCutsTheWaitShortAndOneThatCameDuringARead() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    // the real wait, an hour long: only a refresh can bring the next read
    let link = link(engine)
    let listener = Listener(link.states())
    #expect(await listener.take(1).compactMap(nowOf) == [1])
    link.refresh()
    #expect(await listener.take(1).compactMap(nowOf) == [2])
    // a refresh that finds the read under way is not lost: the next wait returns at once
    link.refresh()
    link.refresh()
    #expect(await listener.take(1).compactMap(nowOf).isEmpty == false)
}

/// The highest `now` a listener was told, kept by a task that iterates it.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var most = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return most }
    func keep(_ stream: AsyncStream<ConnectionState>) -> Task<Void, Never> {
        Task {
            for await state in stream {
                guard let now = nowOf(state) else { continue }
                lock.lock()
                most = max(most, now)
                lock.unlock()
            }
        }
    }
}

@Test func aListenerThatJoinsWhileAReadIsPublishedIsNotGivenAnOlderStateThanOneAlreadyTold() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.005)
    let seen = Seen()
    let keeper = seen.keep(link.states())
    defer { keeper.cancel() }
    #expect(await until { seen.value >= 1 })
    // the new listener is registered and not yet told the last state: give the reader the time to publish a newer one
    let toldBefore = Mutex2(1)
    let atRelease = LockedInt()
    link.beforeReplay = {
        guard toldBefore.take() else { return }
        let before = seen.value
        let deadline = Date().addingTimeInterval(0.3)
        while seen.value <= before && Date() < deadline { usleep(1000) }
        atRelease.set(seen.value)
    }
    let first = await Listener(link.states()).take(1).compactMap(nowOf)
    #expect(first.count == 1 && first[0] >= atRelease.value)
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var number = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return number }
    func set(_ new: Int) { lock.lock(); number = new; lock.unlock() }
}

@Test func aListenerThatNeverReadsHoldsOnlyTheNewestState() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.01)
    let neglected = Listener(link.states())
    // the ninth is asked once the eighth was published: what it holds is a read of the last moments, not the first one
    #expect(await until { engine.asks("snapshot") >= 9 })
    let held = await neglected.take(1).compactMap(nowOf)
    #expect(held.count == 1 && held[0] >= 8)
}

// The engine goes and comes back.

@Test func anEngineThatGoesIsStoppedForEveryoneAndTheLastRunningStateIsNotKeptAsCurrent() async {
    let engine = ScriptEngine()
    let path = engine.path
    // the retry is an hour: the `.stopped` the newcomer is given can only be the one kept, not a new read
    let link = EngineLink(path: { path }, pace: { 0.01 }, retry: 3600, log: { _ in })
    let menu = Listener(link.states())
    #expect(await menu.take(1).compactMap(nowOf).isEmpty == false)
    engine.stop()
    #expect(await menu.untilStopped())
    // someone who comes once the engine is seen gone is told it is stopped, not the running state of before
    #expect(await Listener(link.states()).take(1, seconds: 2) == [.stopped])
}

@Test func anEngineThatComesBackIsFoundAgainAtTheSamePlace() async {
    let engine = ScriptEngine()
    let path = engine.path
    let link = EngineLink(path: { path }, pace: { 0.01 }, retry: 0.02, log: { _ in })
    let listener = Listener(link.states())
    #expect(await listener.take(1).compactMap(nowOf).isEmpty == false)
    engine.stop()
    #expect(await listener.untilStopped())
    let replacement = ScriptEngine(path: path)
    defer { replacement.stop() }
    var running = false
    while let state = await listener.take(1).first {
        if nowOf(state) != nil {
            running = true
            break
        }
    }
    #expect(running && replacement.connections == 1)
}

@Test func theReadsStopWhenTheLastListenerLeavesAndAFreshOneIsNotToldWhatWasBefore() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine)
    var first: Listener? = Listener(link.states())
    #expect(await first?.take(1).compactMap(nowOf) == [1])
    first = nil
    // nobody listens: the connection is let go
    #expect(await until { engine.open == 0 })
    // someone new gets a read made for them, not the one kept from before
    #expect(await Listener(link.states()).take(1).compactMap(nowOf) == [2])
    #expect(engine.connections == 2)
}

@Test func aReadThatWasUnderWayWhenTheLastListenerLeftTellsTheNextOneNothing() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    engine.holdFirstSnapshot()
    let link = link(engine)
    var gone: Listener? = Listener(link.states())
    // a runner that starves the test for longer than the client's timeout makes the held read be asked again, so the counts are lower bounds
    #expect(await until { engine.asks("snapshot") >= 1 })
    gone = nil
    #expect(gone == nil)
    let next = Listener(link.states())
    #expect(await next.take(1).compactMap(nowOf).first.map { $0 >= 2 } == true)
    // the answer to the read of before arrives now: it is not the state of the moment, whoever asked for it
    engine.release()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(await next.take(1, seconds: 0.3).isEmpty)
}

@Test func whenNoEngineIsThereEveryListenerIsToldItIsStopped() async {
    let link = EngineLink(path: { "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock" }, pace: { 3600 }, retry: 3600, log: { _ in })
    let (a, b) = (Listener(link.states()), Listener(link.states()))
    let (x, y) = await (a.take(1), b.take(1))
    #expect(x == [.stopped] && y == [.stopped])
}

// The epic view's requests: the window's, on a connection of their own while it is open.

@Test func theEpicTickRunsOnAConnectionOfItsOwnAndTheSnapshotsStayOnTheirs() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    link.setTick { client in _ = try client.request("epic", requires: .epic, fields: ",\"repo\":\"a/b\",\"issue\":1") }
    #expect(await until { engine.asks("epic") >= 1 })
    // the snapshots are the first connection's alone, and the tick's requests the second's
    #expect(engine.commands[1]?.allSatisfy { $0 == "snapshot" } == true)
    #expect(engine.commands[2]?.allSatisfy { $0 == "epic" } == true)
    #expect(engine.connections == 2)
}

@Test func aFilesRequestHeldByTheEngineDoesNotHoldBackTheSnapshots() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    engine.hold()
    let link = link(engine)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    link.setTick { client in _ = try client.request("files", requires: .files, fields: ",\"repo\":\"a/b\",\"issue\":1") }
    #expect(await until { engine.asks("files") == 1 })
    // the engine answers a connection in order: the files the tick waits for are not between the menu and its snapshot,
    // and the link's lock is not held across it (a refresh and a snapshot would wait for the 5 s the files request takes to run out)
    let start = ContinuousClock.now
    link.refresh()
    #expect(await listener.take(1, seconds: 2).compactMap(nowOf) == [2])
    link.refresh()
    #expect(await listener.take(1, seconds: 2).compactMap(nowOf) == [3])
    #expect(ContinuousClock.now - start < .seconds(2))
    engine.release()
}

@Test func takingTheTickAwayStopsItAndLetsGoOfItsConnectionAndOfWhatItHeld() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.01)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    final class Held: @unchecked Sendable {}
    weak var weakHeld: Held?
    do {
        let held = Held()
        weakHeld = held
        link.setTick { client in _ = held; _ = try client.request("epic", requires: .epic, fields: ",\"repo\":\"a/b\",\"issue\":1") }
    }
    #expect(await until { engine.asks("epic") >= 2 })
    link.setTick(nil)
    #expect(await until { engine.open == 1 })
    let after = engine.asks("epic")
    try? await Task.sleep(for: .milliseconds(100))
    #expect(engine.asks("epic") == after)
    #expect(await until { weakHeld == nil })
}

@Test func aTickSetTwiceWithoutBeingTakenAwayReplacesTheFirstAndTakingItAwayEndsThePoll() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.01)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    final class Held: @unchecked Sendable {}
    weak var weakFirst: Held?
    let second = LockedInt()
    do {
        let held = Held()
        weakFirst = held
        link.setTick { _ in _ = held }
    }
    link.setTick { _ in second.set(second.value + 1) }
    #expect(await until { second.value >= 3 })
    #expect(await until { weakFirst == nil })
    // one connection for the poll, and one thread that taking the tick away ends
    #expect(engine.connections == 2)
    link.setTick(nil)
    #expect(await until { engine.open == 1 })
    let after = second.value
    try? await Task.sleep(for: .milliseconds(100))
    #expect(second.value == after)
}

@Test func aPollTakenAwayBeforeItsTurnNeverOpensAConnection() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.01)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    let leave = DispatchSemaphore(value: 0)
    let inside = LockedInt()
    link.setTick { _ in
        inside.set(1)
        _ = leave.wait(timeout: .now() + 5)
    }
    #expect(await until { inside.value == 1 })
    // the window closes, opens and closes again while the first poll is under way: the second thread waits its turn with its flag already set
    link.setTick(nil)
    link.setTick { _ in }
    link.setTick(nil)
    leave.signal()
    #expect(await until { engine.open == 1 })
    try? await Task.sleep(for: .milliseconds(200))
    #expect(engine.connections == 2)
}

private final class Overlap: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0, most = 0, ran = 0
    func enter() { lock.lock(); running += 1; most = max(most, running); lock.unlock() }
    func exit() { lock.lock(); running -= 1; ran += 1; lock.unlock() }
    var overlap: Int { lock.lock(); defer { lock.unlock() }; return most }
    var passes: Int { lock.lock(); defer { lock.unlock() }; return ran }
}

@Test func aTickPutBackWaitsForTheOneTakenAwayToFinishSoThePollerHasOneThread() async {
    let engine = ScriptEngine()
    defer { engine.stop() }
    let link = link(engine, pace: 0.01)
    let listener = Listener(link.states())
    _ = await listener.take(1)
    let inside = DispatchSemaphore(value: 0), leave = DispatchSemaphore(value: 0)
    let count = Overlap()
    let firstPass = Mutex2(1)
    link.setTick { _ in
        count.enter()
        defer { count.exit() }
        if firstPass.take() {
            inside.signal()
            _ = leave.wait(timeout: .now() + 5)
        }
    }
    #expect(inside.wait(timeout: .now() + 3) == .success)
    // the window closed and opened again while the poll was under way
    link.setTick(nil)
    link.setTick { _ in count.enter(); count.exit() }
    try? await Task.sleep(for: .milliseconds(150))
    leave.signal()
    #expect(await until { count.passes >= 3 })
    #expect(count.overlap == 1)
}

private final class Mutex2: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int
    init(_ count: Int) { self.count = count }
    /// True the first `count` times.
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; defer { count = max(count - 1, 0) }; return count > 0 }
}
