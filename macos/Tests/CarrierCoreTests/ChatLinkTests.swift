import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures.path

private func hello(_ capabilities: String = "\"agents\",\"list\",\"events\"") -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

private func row(_ id: String, archived: Bool = false) -> String {
    "{\"id\":\"\(id)\",\"agent\":\"claude\",\"harness\":\"claude\",\"folder\":\"/w\",\"title\":\"t\",\"state\":\"idle\",\"createdAt\":1,\"lastActiveAt\":2,\"archived\":\(archived),\"live\":true}"
}

/// A chat host that answers `list` from what the test sets and counts what it is asked, by connection and by request.
private final class ScriptHost: @unchecked Sendable {
    private let lock = NSLock()
    private var connected = 0
    private var asked: [String: Int] = [:]
    private var activeIds: [String] = []
    private var archivedIds: [String] = []
    private var gate: DispatchSemaphore?
    private var open: [ServerConnection] = []
    private var capabilities: String
    private(set) var server: TestServer!

    init(path: String? = nil, capabilities: String = "\"agents\",\"list\",\"events\"") {
        self.capabilities = capabilities
        let hello = hello(capabilities)
        server = TestServer(path: path) { [self] connection in
            locked { connected += 1; open.append(connection) }
            // what is shut down later must still be open: the server closes the descriptor after this returns, and another test may be given its number
            defer { locked { open.removeAll { $0.fd == connection.fd } } }
            connection.send(hello)
            while let line = connection.readLine() {
                let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
                guard let id = request?["id"] as? Int, let command = request?["cmd"] as? String else { return }
                let wait = locked { () -> DispatchSemaphore? in
                    asked[command, default: 0] += 1
                    return command == "list" ? gate : nil
                }
                // the answer is what the host held when it was asked, however long it is held
                let wanted = request?["archived"] as? Bool ?? false
                let rows = locked { (wanted ? archivedIds : activeIds).map { row($0, archived: wanted) }.joined(separator: ",") }
                wait?.wait()
                connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"sessions\":[\(rows)]}}\n")
            }
        }
    }

    var path: String { server.path }
    var connections: Int { locked { connected } }
    func asks(_ command: String) -> Int { locked { asked[command, default: 0] } }
    func set(active: [String], archived: [String] = []) { locked { (activeIds, archivedIds) = (active, archived) } }
    /// Holds the answers of `list` until `release`.
    func hold() { locked { gate = DispatchSemaphore(value: 0) } }
    func release() {
        let held = locked { () -> DispatchSemaphore? in
            defer { gate = nil }
            return gate
        }
        held?.signal()
    }
    /// What is connected is closed; the host still takes a connection.
    func closeConnections() { locked { open.forEach { _ = Darwin.shutdown($0.fd, SHUT_RDWR) } } }

    /// The host goes away: it closes what is connected and no longer takes a connection.
    func stop() {
        server.stop()
        locked { open.forEach { _ = Darwin.shutdown($0.fd, SHUT_RDWR) } }
    }

    private func locked<Value>(_ body: () -> Value) -> Value { lock.lock(); defer { lock.unlock() }; return body() }
}

/// What a test needs to let the link's reads go one by one: the wait between two reads parks here until the test releases it.
private actor Ticker {
    private(set) var waits: [TimeInterval] = []
    private var permits = 0
    private var parked: CheckedContinuation<Void, Never>?

    func park(_ seconds: TimeInterval) async {
        waits.append(seconds)
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { parked = $0 }
    }

    func release() {
        if let parked {
            self.parked = nil
            parked.resume()
        } else {
            permits += 1
        }
    }
}

private final class LinkClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current.addTimeInterval(seconds); lock.unlock() }
}

private func until(_ done: @escaping () async -> Bool) async -> Bool {
    for _ in 0..<600 {
        if await done() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

private func ids(_ update: SessionsUpdate) -> [String] { (update.active + update.archived).map(\.id) }

// What is asked of the host: one connection, one hello.

@Test func twentyReadsAreMadeOnOneConnectionWithOneHello() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let link = ChatLink(path: server.chatSocketPath)
    for _ in 0..<20 { _ = try await link.list(archived: false) }
    _ = try await link.capabilities()
    #expect(server.chatConnections == 1)
    #expect(server.chatRequests["list"] == 20)
}

@Test func theSocketHostReadsListEventsAndCapabilitiesOnOneConnectionAndAnActionKeepsItsOwn() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let session = try #require(try await host.list(archived: false).first).id
    for _ in 0..<5 { _ = try await host.events(session, after: 0, limit: 50) }
    _ = try await host.capabilities()
    _ = try await host.list(archived: true)
    #expect(server.chatConnections == 1 && server.chatRequests["events"] == 5)
    // an action is one connection of its own: the kept one is not held up by it
    _ = try await host.agents()
    #expect(server.chatConnections == 2)
    _ = try await host.list(archived: false)
    #expect(server.chatConnections == 2)
}

@Test func theCapabilitiesComeFromTheHelloAndAskTheHostNothing() async throws {
    let host = ScriptHost(capabilities: "\"agents\",\"list\",\"stopTask\"")
    defer { host.stop() }
    let link = ChatLink(path: host.path)
    for _ in 0..<5 { #expect(try await link.capabilities() == [.agents, .list, .stopTask]) }
    #expect(host.connections == 1 && host.asks("list") == 0)
}

@Test func twoListsAtTheSameTimeShareOneRequestAndTheNextIsAnother() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    host.set(active: ["a"])
    host.hold()
    let link = ChatLink(path: host.path)
    let first = Task { try await link.list(archived: false) }
    #expect(await until { host.asks("list") == 1 })
    let second = Task { try await link.list(archived: false) }
    // the same ask made while the first is under way is not another request: give it a moment to have been wrong
    try await Task.sleep(for: .milliseconds(50))
    host.release()
    let one = try await first.value.map(\.id), two = try await second.value.map(\.id)
    #expect(one == ["a"] && two == ["a"] && host.asks("list") == 1)
    // the archived list is another request, and an ask after the answer is a new one
    _ = try await link.list(archived: true)
    _ = try await link.list(archived: false)
    #expect(host.asks("list") == 3)
}

@Test func aReadThatBeganBeforeARefreshIsNotJoinedByTheReadTheRefreshAsksFor() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    host.set(active: [], archived: ["old"])
    host.hold()
    let link = ChatLink(path: host.path)
    // a read of the archived list under way (an older host's fallback, the new-session screen's) ...
    let before = Task { try await link.list(archived: true) }
    #expect(await until { host.asks("list") == 1 })
    // ... the app archives a session and says so
    host.set(active: [], archived: ["old", "new"])
    link.refresh(archived: true)
    let after = Task { try await link.list(archived: true) }
    try await Task.sleep(for: .milliseconds(50))
    host.release()
    // the one that began before still answers its own caller, and the one after the refresh is a read of its own
    #expect(try await before.value.map(\.id) == ["old"])
    #expect(try await after.value.map(\.id) == ["old", "new"] && host.asks("list") == 2)
    // the next ask, with nothing in between, is a read again and not the old one
    _ = try await link.list(archived: true)
    #expect(host.asks("list") == 3)
}

@Test func aConnectionTheHostClosedIsOpenedAgainWithItsHelloAndTheRequestStillAnswers() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    host.set(active: ["a"])
    let link = ChatLink(path: host.path)
    _ = try await link.list(archived: false)
    // the host closes what is connected (a restart of the process behind the same socket)
    host.closeConnections()
    #expect(try await link.list(archived: false).map(\.id) == ["a"])
    #expect(host.connections == 2)
}

@Test func aHostReplacedByAnotherWithOtherCapabilitiesIsHelloedAgain() async throws {
    let old = ScriptHost(capabilities: "\"agents\",\"list\"")
    let link = ChatLink(path: old.path)
    #expect(try await link.capabilities() == [.agents, .list])
    old.stop()
    let replacement = ScriptHost(path: old.path, capabilities: "\"agents\",\"list\",\"events\",\"stopTask\"")
    defer { replacement.stop() }
    #expect(try await link.capabilities() == [.agents, .list, .events, .stopTask])
    #expect(replacement.connections == 1)
}

@Test func aHostThatIsNotThereIsClosedAndAnErrorReplyKeepsTheConnection() async throws {
    let link = ChatLink(path: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock")
    await #expect(throws: ControlError.closed) { _ = try await link.list(archived: false) }
    // a host that lists nothing refuses in words, and the connection stays for the next ask
    let host = ScriptHost(capabilities: "\"agents\"")
    defer { host.stop() }
    let refusing = ChatLink(path: host.path)
    await #expect(throws: ControlError.remote("the chat host does not support list")) { _ = try await refusing.list(archived: false) }
    await #expect(throws: ControlError.remote("the chat host does not support list")) { _ = try await refusing.list(archived: false) }
    #expect(host.connections == 1)
}

// The sessions every listener shares.

private struct Rig {
    let host: ScriptHost
    let link: ChatLink
    let ticker = Ticker()
    let clock = LinkClock()

    init(path: String? = nil, archivedEvery: TimeInterval = 60, pace: TimeInterval = 2, looking: Bool = false, log: @escaping @Sendable (String) -> Void = { _ in }) {
        host = ScriptHost(path: path)
        let ticker = ticker
        let clock = clock
        link = ChatLink(path: host.path, archivedEvery: archivedEvery, now: { clock.now }, pace: { pace }, looking: { looking }, sleep: { await ticker.park($0) }, log: log)
    }
}

@Test func aNewListenerGetsTheLastUpdateAtOnceAsAReplayAndAskTheHostNothing() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"], archived: ["x"])
    var first = await rig.link.sessions().makeAsyncIterator()
    let update = try #require(await first.next())
    #expect(ids(update) == ["a", "x"] && update.authoritative && update.replayed == false && update.stale == false)
    let asked = rig.host.asks("list")
    var second = await rig.link.sessions().makeAsyncIterator()
    let replay = try #require(await second.next())
    #expect(ids(replay) == ["a", "x"] && replay.replayed && replay.authoritative == false)
    #expect(rig.host.asks("list") == asked && rig.host.connections == 1)
}

@Test func twoListenersAreServedByOneRead() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"])
    var one = await rig.link.sessions().makeAsyncIterator()
    var two = await rig.link.sessions().makeAsyncIterator()
    _ = await one.next()
    _ = await two.next()
    await rig.ticker.release()
    let again = try #require(await one.next())
    #expect(again.replayed == false)
    // the active list was read twice in all (and the archived one once), however many listened
    #expect(rig.host.asks("list") == 3 && rig.host.connections == 1)
}

@Test func theArchivedListIsReadEveryMinuteAndTheActiveOneEveryCycle() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"], archived: ["x"])
    var updates = await rig.link.sessions().makeAsyncIterator()
    #expect(try #require(await updates.next()).authoritative)
    #expect(rig.host.asks("list") == 2)
    rig.clock.advance(30)
    await rig.ticker.release()
    let half = try #require(await updates.next())
    #expect(half.authoritative == false && rig.host.asks("list") == 3)
    rig.clock.advance(30)
    await rig.ticker.release()
    let minute = try #require(await updates.next())
    #expect(minute.authoritative && rig.host.asks("list") == 5)
}

@Test func aRefreshOfTheArchivedListReadsItInTheNextCycleWhateverItsAgeAndAPlainOneDoesNot() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"], archived: ["x"])
    var updates = await rig.link.sessions().makeAsyncIterator()
    _ = await updates.next()
    // nothing left the active list; the archived list changed (a restore in another window, say)
    rig.host.set(active: ["a"], archived: ["x", "y"])
    rig.link.refresh(archived: false)
    await rig.ticker.release()
    var update = try #require(await updates.next())
    #expect(rig.host.asks("list") == 3 && update.archived.count == 1)
    rig.link.refresh(archived: true)
    await rig.ticker.release()
    update = try #require(await updates.next())
    #expect(rig.host.asks("list") == 5 && update.archived.count == 2 && update.authoritative)
}

@Test func anArchiveOfTheAppReadsTheArchivedListInTheNextCycleAndASessionThatLeavesTheActiveListToo() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a", "b"])
    var updates = await rig.link.sessions().makeAsyncIterator()
    _ = await updates.next()
    #expect(rig.host.asks("list") == 2)
    // the app archived `b`
    rig.host.set(active: ["a"], archived: ["b"])
    rig.link.refresh(archived: true)
    await rig.ticker.release()
    var update = try #require(await updates.next())
    #expect(rig.host.asks("list") == 4 && ids(update) == ["a", "b"] && update.authoritative)
    // something else archived `a`: it left the active list and the archived list is read in the same cycle
    rig.host.set(active: [], archived: ["a", "b"])
    await rig.ticker.release()
    update = try #require(await updates.next())
    #expect(rig.host.asks("list") == 6 && ids(update) == ["a", "b"])
}

@Test func anArchiveOfTheAppReadsTheArchivedListOnceAndNotInEveryCycleAfterIt() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"], archived: ["x"])
    var updates = await rig.link.sessions().makeAsyncIterator()
    _ = await updates.next()
    #expect(rig.host.asks("list") == 2)
    rig.link.refresh(archived: true)
    await rig.ticker.release()
    #expect(try #require(await updates.next()).authoritative && rig.host.asks("list") == 4)
    // the minute has not passed and nothing left the active list: this cycle reads the active list only
    await rig.ticker.release()
    let next = try #require(await updates.next())
    #expect(next.authoritative == false && rig.host.asks("list") == 5)
}

@Test func aSessionOfSomeoneElseCreatedAndArchivedWithinTheMinuteIsSeenAsArchivedAtOnce() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"])
    var updates = await rig.link.sessions().makeAsyncIterator()
    _ = await updates.next()
    // `b` appears and the archived list is not due: the cycle must still remember `b` as active
    rig.host.set(active: ["a", "b"])
    await rig.ticker.release()
    #expect(try #require(await updates.next()).authoritative == false)
    // something else archives `b` before the archived list is read again
    rig.host.set(active: ["a"], archived: ["b"])
    await rig.ticker.release()
    let update = try #require(await updates.next())
    #expect(ids(update) == ["a", "b"] && update.authoritative && update.archived.map(\.id) == ["b"])
}

@Test func aListenerThatNeverReadsHoldsOnlyTheNewestUpdate() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"])
    let idle = await rig.link.sessions()
    let collected = Collected()
    let driving = Task { for await update in await rig.link.sessions() { collected.add(update) } }
    defer { driving.cancel() }
    #expect(await until { collected.updates.count == 1 })
    for (count, active) in [["a", "b"], ["a", "b", "c"]].enumerated() {
        rig.host.set(active: active)
        await rig.ticker.release()
        #expect(await until { collected.updates.count == count + 2 })
    }
    var iterator = idle.makeAsyncIterator()
    let newest = try #require(await iterator.next())
    #expect(newest.active.map(\.id) == ["a", "b", "c"])
}

/// Every update a listener was given.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [SessionsUpdate] = []
    func add(_ update: SessionsUpdate) { lock.lock(); all.append(update); lock.unlock() }
    var updates: [SessionsUpdate] { lock.lock(); defer { lock.unlock() }; return all }
}

@Test func aHostThatGoesAwayIsToldOnceWithTheLastListsAndNeverAsAnEmptyOneAndComesBackAsAnswering() async throws {
    let rig = Rig()
    rig.host.set(active: ["a"], archived: ["x"])
    let collected = Collected()
    let stream = await rig.link.sessions()
    let listening = Task { for await update in stream { collected.add(update) } }
    #expect(await until { collected.updates.count == 1 })
    let path = rig.host.path
    rig.host.stop()
    await rig.ticker.release()
    #expect(await until { collected.updates.count == 2 })
    let stale = collected.updates[1]
    #expect(stale.stale && ids(stale) == ["a", "x"] && stale.authoritative == false)
    // the misses that follow say nothing more, and the wait doubles with each, up to half a minute
    for _ in 0..<5 { await rig.ticker.release() }
    #expect(await until { await rig.ticker.waits.count >= 7 })
    let waits = await rig.ticker.waits
    #expect(waits == [2, 4, 8, 16, 30, 30, 30])
    #expect(collected.updates.count == 2)
    // the host comes back at the same place
    let back = ScriptHost(path: path)
    defer { back.stop() }
    back.set(active: ["a", "b"])
    await rig.ticker.release()
    #expect(await until { collected.updates.count == 3 })
    let answering = collected.updates[2]
    #expect(answering.stale == false && ids(answering) == ["a", "b"] && answering.authoritative)
    // never an empty list for a host that did not answer
    #expect(collected.updates.allSatisfy { $0.stale || $0.active.isEmpty == false })
    listening.cancel()
}

@Test func whileSomeoneLooksTheWaitAfterAMissNeverPassesTenSeconds() async throws {
    let rig = Rig(looking: true)
    rig.host.set(active: ["a"])
    let listening = Task { for await _ in await rig.link.sessions() {} }
    defer { listening.cancel() }
    #expect(await until { await rig.ticker.waits.count == 1 })
    rig.host.stop()
    for count in 2...6 {
        await rig.ticker.release()
        #expect(await until { await rig.ticker.waits.count == count })
    }
    // a host restarted by hand is seen within 10 seconds, as the window's own poll did
    #expect(await rig.ticker.waits == [2, 4, 8, 10, 10, 10])
}

@Test func aHostThatWasNeverThereGivesOneStaleUpdateWithNoSessions() async throws {
    let ticker = Ticker()
    let link = ChatLink(path: "/tmp/cc-missing-\(UUID().uuidString.prefix(8)).sock", pace: { 2 }, looking: { false }, sleep: { await ticker.park($0) }, log: { _ in })
    var updates = await link.sessions().makeAsyncIterator()
    let update = try #require(await updates.next())
    #expect(update.stale && update.active.isEmpty && update.archived.isEmpty)
}

@Test func theFirstMissAfterAnAnswerIsLoggedOnceAndTheRestAreNot() async throws {
    let host = ScriptHost()
    host.set(active: ["a"])
    let ticker = Ticker()
    let logged = LockedLog()
    let link = ChatLink(path: host.path, pace: { 2 }, looking: { false }, sleep: { await ticker.park($0) }, log: { logged.add($0) })
    var updates = await link.sessions().makeAsyncIterator()
    _ = await updates.next()
    host.stop()
    for _ in 0..<3 { await ticker.release() }
    _ = await updates.next()
    #expect(await until { await ticker.waits.count >= 3 })
    #expect(logged.lines.count == 1)
}

private final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ line: String) { lock.lock(); all.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return all }
}

@Test func aSecondOutageAfterARecoveryIsLoggedAgain() async throws {
    let logged = LockedLog()
    let rig = Rig(log: { logged.add($0) })
    rig.host.set(active: ["a"])
    let path = rig.host.path
    let collected = Collected()
    let stream = await rig.link.sessions()
    let listening = Task { for await update in stream { collected.add(update) } }
    defer { listening.cancel() }
    #expect(await until { collected.updates.count == 1 })
    rig.host.stop()
    await rig.ticker.release()
    #expect(await until { collected.updates.count == 2 })
    #expect(logged.lines.count == 1)
    let back = ScriptHost(path: path)
    back.set(active: ["a"])
    await rig.ticker.release()
    #expect(await until { collected.updates.count == 3 })
    back.stop()
    await rig.ticker.release()
    #expect(await until { collected.updates.count == 4 })
    #expect(logged.lines.count == 2)
}

@Test func theReadsStopWhenTheLastListenerLeavesAndStartAgainWithTheNextOne() async throws {
    let rig = Rig()
    defer { rig.host.stop() }
    rig.host.set(active: ["a"])
    let listening = Task { for await _ in await rig.link.sessions() {} }
    #expect(await until { rig.host.asks("list") == 2 })
    listening.cancel()
    await listening.value
    await rig.ticker.release()
    await rig.ticker.release()
    try await Task.sleep(for: .milliseconds(100))
    #expect(rig.host.asks("list") == 2)
    var again = await rig.link.sessions().makeAsyncIterator()
    _ = await again.next()
    _ = await again.next()
    #expect(rig.host.asks("list") >= 3)
}

// The connection: what it does when one it kept is found closed, or the path is another.

private final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var total: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Test func aRequestThatFindsTheKeptConnectionClosedIsMadeOnceMoreOnANewOneAndASecondFailureIsTold() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    let connection = ChatConnection()
    _ = try await connection.perform(path: host.path) { $0.capabilities }
    // the connection looked open to the check made before the request and closed under it: it is made again, once
    let flaky = Attempts()
    let value = try await connection.perform(path: host.path) { _ in
        if flaky.next() == 1 { throw ControlError.closed }
        return 7
    }
    #expect(value == 7 && flaky.total == 2 && host.connections == 2)
    // a host that closes the new one too is told, and not asked a third time
    let broken = Attempts()
    await #expect(throws: ControlError.closed) {
        try await connection.perform(path: host.path) { (_: ControlClient) -> Int in
            _ = broken.next()
            throw ControlError.closed
        }
    }
    #expect(broken.total == 2)
}

@Test func aConnectionJustOpenedThatIsFoundClosedIsNotAskedAgain() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    let attempts = Attempts()
    await #expect(throws: ControlError.closed) {
        try await ChatConnection().perform(path: host.path) { (_: ControlClient) -> Int in
            _ = attempts.next()
            throw ControlError.closed
        }
    }
    #expect(attempts.total == 1 && host.connections == 1)
}

@Test func aRequestForAnotherPathIsMadeOnAnotherConnectionWithItsOwnHello() async throws {
    let one = ScriptHost(capabilities: "\"agents\",\"list\"")
    let two = ScriptHost(capabilities: "\"agents\",\"list\",\"events\"")
    defer { one.stop(); two.stop() }
    let connection = ChatConnection()
    #expect(try await connection.perform(path: one.path) { $0.capabilities } == [.agents, .list])
    #expect(try await connection.perform(path: two.path) { $0.capabilities } == [.agents, .list, .events])
    #expect(one.connections == 1 && two.connections == 1)
    // and back: the kept one is for the path it was opened for
    #expect(try await connection.perform(path: one.path) { $0.capabilities } == [.agents, .list])
    #expect(one.connections == 2)
}

@Test func theActiveAndTheArchivedListAtTheSameTimeAreTwoRequests() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    host.set(active: ["a"], archived: ["x"])
    host.hold()
    let link = ChatLink(path: host.path)
    let active = Task { try await link.list(archived: false) }
    #expect(await until { host.asks("list") == 1 })
    let archived = Task { try await link.list(archived: true) }
    host.release()
    let listed = try await active.value.map(\.id), archivedListed = try await archived.value.map(\.id)
    #expect(listed == ["a"] && archivedListed == ["x"])
    #expect(host.asks("list") == 2)
}

// The pace: what a recovery resets, and what a refresh cuts.

@Test func aHostThatAnswersAgainStartsTheBackoffOverAtTheNextMiss() async throws {
    let rig = Rig()
    rig.host.set(active: ["a"])
    let path = rig.host.path
    let stream = await rig.link.sessions()
    let collected = Collected()
    let listening = Task { for await update in stream { collected.add(update) } }
    defer { listening.cancel() }
    #expect(await until { await rig.ticker.waits.count == 1 })
    rig.host.stop()
    for count in 2...3 {
        await rig.ticker.release()
        #expect(await until { await rig.ticker.waits.count == count })
    }
    let back = ScriptHost(path: path)
    defer { back.stop() }
    back.set(active: ["a"])
    await rig.ticker.release()
    #expect(await until { await rig.ticker.waits.count == 4 })
    back.stop()
    await rig.ticker.release()
    #expect(await until { await rig.ticker.waits.count == 5 })
    // the pace while it answered, then the first doubling of the next miss, not the fourth
    let waits = await rig.ticker.waits
    #expect(waits == [2, 4, 8, 2, 4])
}

/// A link that waits as it does in the app (the nap `refresh` cuts), and what it was told.
private func napping(path: String, pace: TimeInterval = 10) -> ChatLink { ChatLink(path: path, pace: { pace }, looking: { false }, log: { _ in }) }

@Test func aRefreshCutsTheWaitOfTheNormalPaceAndTheListIsReadAtOnce() async throws {
    let host = ScriptHost()
    defer { host.stop() }
    host.set(active: ["a"])
    let link = napping(path: host.path, pace: 3600)
    let collected = Collected()
    let stream = await link.sessions()
    let listening = Task { for await update in stream { collected.add(update) } }
    defer { listening.cancel() }
    #expect(await until { collected.updates.count == 1 })
    host.set(active: ["a", "b"])
    link.refresh(archived: false)
    #expect(await until { collected.updates.count == 2 })
    #expect(ids(collected.updates[1]).contains("b"))
}

@Test func aRefreshCutsTheBackoffOfAHostThatWasDownAndIsUpAgain() async throws {
    let path = "/tmp/cc-late-\(UUID().uuidString.prefix(8)).sock"
    let link = napping(path: path)
    let collected = Collected()
    let stream = await link.sessions()
    let listening = Task { for await update in stream { collected.add(update) } }
    defer { listening.cancel() }
    #expect(await until { collected.updates.count == 1 })
    #expect(collected.updates[0].stale)
    // the host starts: the loop is in a wait of 20 seconds, and the app says the host is up
    let host = ScriptHost(path: path)
    defer { host.stop() }
    host.set(active: ["a"])
    link.refresh(archived: false)
    #expect(await until { collected.updates.count == 2 })
    #expect(collected.updates[1].stale == false && ids(collected.updates[1]) == ["a"])
}
