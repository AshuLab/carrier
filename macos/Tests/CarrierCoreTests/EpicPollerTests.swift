import Foundation
import Testing
@testable import CarrierCore

private let web = EpicRef(repo: "acme/web", issue: 12)
private let api = EpicRef(repo: "acme/api", issue: 3)
private let execution = "a1b2c3d4-0001-4000-8000-000000000001"

/// A poller on a clock the test moves, against the fixture engine. `tick(at:)` polls at that second and returns the commands sent by it.
private final class Rig {
    let engine: FixtureEngine
    let client: ControlClient
    let poller: EpicPoller
    var seconds: TimeInterval = 0
    var updates: [EpicRef] = []

    init(capabilities: [String] = ["sessions", "events", "epic", "files"]) throws {
        engine = FixtureEngine(capabilities: capabilities)
        client = try #require(ControlClient.connect(path: engine.path))
        _ = try client.hello()
        let box = UpdateBox()
        var clock: () -> Date = { Date() }
        let poller = EpicPoller(now: { clock() }, onUpdate: { key, _ in box.append(key) })
        self.poller = poller
        self.box = box
        clock = { [unowned self] in Date(timeIntervalSince1970: self.seconds) }
    }

    private let box: UpdateBox
    var changed: [EpicRef] { box.all }

    func tick(at time: TimeInterval) throws -> [String] {
        seconds = time
        let before = engine.commands.count
        try poller.poll(client)
        return Array(engine.commands.dropFirst(before))
    }

    deinit { engine.stop() }
}

private final class UpdateBox {
    private let lock = NSLock()
    private var keys: [EpicRef] = []
    func append(_ key: EpicRef) { lock.lock(); keys.append(key); lock.unlock() }
    var all: [EpicRef] { lock.lock(); defer { lock.unlock() }; return keys }
}

@Test func nothingIsAskedWithoutAnEpicOnScreen() throws {
    let rig = try Rig()
    #expect(try rig.tick(at: 0).isEmpty)
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 1) == ["epic", "sessions"])
}

@Test func theEpicEveryThreeSecondsAndTheSessionsEveryFiveStartingWhenItOpens() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))

    var sent: [TimeInterval: [String]] = [:]
    for second in 0...15 { sent[TimeInterval(second)] = try rig.tick(at: TimeInterval(second)) }
    let epics = sent.filter { $0.value.contains("epic") }.keys.sorted()
    let sessions = sent.filter { $0.value.contains("sessions") }.keys.sorted()
    #expect(epics == [0, 3, 6, 9, 12, 15])
    #expect(sessions == [0, 5, 10, 15])
    #expect(sent.values.allSatisfy { $0.allSatisfy { ["epic", "sessions"].contains($0) } })
}

@Test func theEventsEverySecondWithTheCursorOfTheLastReplyOnlyWhileARunningTranscriptIsVisible() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 0) == ["epic", "sessions"])
    #expect(try rig.tick(at: 1).isEmpty)

    rig.poller.show(EpicFocus(epic: web, epicRunning: true, transcript: execution))
    #expect(try rig.tick(at: 1.2) == ["events"])
    #expect(try rig.tick(at: 1.7).isEmpty)
    #expect(try rig.tick(at: 2.2) == ["events"])
    #expect(try rig.tick(at: 3.2) == ["epic", "events"])

    let events = rig.engine.requests.filter { $0["cmd"] as? String == "events" }
    #expect(events.map { $0["after"] as? Int } == [0, 119, 119])
    #expect(events.allSatisfy { $0["executionId"] as? String == execution && $0["limit"] as? Int == 200 })

    // the transcript is hidden: no more, and shown again it is asked at once
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 3.4).isEmpty)
    rig.poller.show(EpicFocus(epic: web, epicRunning: true, transcript: execution))
    #expect(try rig.tick(at: 3.5) == ["events"])
}

@Test func theFilesWhenTheTabOpensThenEveryTenSecondsOnlyWhileTheEpicRuns() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 0) == ["epic", "sessions"])

    // the tab is hidden: never, however long
    #expect(try rig.tick(at: 12).contains("files") == false)

    rig.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true))
    #expect(try rig.tick(at: 13).contains("files"))
    #expect(try rig.tick(at: 22).contains("files") == false)
    #expect(try rig.tick(at: 23).contains("files"))

    // hide and show again: asked at once
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 24).contains("files") == false)
    rig.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true))
    #expect(try rig.tick(at: 25).contains("files"))

    // the epic stopped running: once when the tab opens, then no more
    rig.poller.show(EpicFocus(epic: web, epicRunning: false, filesTabVisible: true))
    #expect(try rig.tick(at: 60).contains("files") == false)
    rig.poller.show(EpicFocus(epic: web, epicRunning: false))
    rig.poller.show(EpicFocus(epic: web, epicRunning: false, filesTabVisible: true))
    #expect(try rig.tick(at: 61).contains("files"))
    #expect(try rig.tick(at: 100).contains("files") == false)
}

@Test func closingTheWindowStopsEverythingAndOpeningAgainStartsOver() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, transcript: execution))
    #expect(try rig.tick(at: 0).sorted() == ["epic", "events", "files", "sessions"])

    rig.poller.show(nil)
    #expect(try rig.tick(at: 1).isEmpty)
    #expect(try rig.tick(at: 100).isEmpty)

    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 101) == ["epic", "sessions"])
}

@Test func changingEpicAsksTheNewOneAtOnceAndNothingMoreForTheOldOne() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    #expect(try rig.tick(at: 0) == ["epic", "sessions"])

    rig.poller.show(EpicFocus(epic: api, epicRunning: true))
    #expect(try rig.tick(at: 1) == ["epic", "sessions"])
    #expect(try rig.tick(at: 2).isEmpty)
    let repos = rig.engine.requests.map { $0["repo"] as? String }
    #expect(repos == ["acme/web", "acme/web", "acme/api", "acme/api"])
    #expect(Set(rig.poller.data.keys) == [web, api])
}

@Test func aRequestIsNeverSentWhenTheHelloLeftTheCapabilityOut() throws {
    let rig = try Rig(capabilities: ["epic"])
    rig.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, transcript: execution))
    #expect(try rig.tick(at: 0) == ["epic"])
    #expect(try rig.tick(at: 1).isEmpty)
    #expect(rig.poller.data[web]?.sessions == nil)
    #expect(rig.poller.data[web]?.transcripts.isEmpty == true)

    let none = try Rig(capabilities: [])
    none.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, transcript: execution))
    #expect(try none.tick(at: 0).isEmpty)
}

@Test func aFailingRequestIsNotAskedAgainAndTheOthersGoOn() throws {
    let engine = FixtureEngine(capabilities: ["sessions", "events", "epic", "files"], fail: ["sessions"])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true))

    try poller.poll(client)
    now = Date(timeIntervalSince1970: 5)
    try poller.poll(client)
    #expect(engine.commands == ["epic", "sessions", "epic"])
    #expect(poller.data[web]?.epic != nil && poller.data[web]?.sessions == nil)
}

@Test func theUpdateIsReportedOnlyWhenAReplyChangedSomething() throws {
    let rig = try Rig()
    rig.poller.show(EpicFocus(epic: web, epicRunning: true))
    _ = try rig.tick(at: 0)
    #expect(rig.changed == [web, web])
    _ = try rig.tick(at: 3) // the same epic reply again
    #expect(rig.changed.count == 2)
}

@Test func theCursorAdvancesADuplicateIsIgnoredAndEventsStayInOrder() {
    func event(_ id: Int) -> ExecEvent { ExecEvent(id: id, at: id * 10, kind: "say") }
    func reply(_ ids: [Int], next: Int, running: Bool = true) -> EventsReply { EventsReply(events: ids.map(event), next: next, running: running, structured: true) }

    var transcript = Transcript()
    #expect(transcript.next == 0)
    transcript.apply(reply([1, 2, 3], next: 3))
    #expect(transcript.next == 3)

    // 3 again and 4 and 5 out of order within the reply
    transcript.apply(reply([3, 5, 4], next: 5))
    #expect(transcript.events.map(\.id) == [1, 2, 3, 4, 5])
    #expect(transcript.next == 5)

    // a late reply: nothing new and the cursor never goes back
    transcript.apply(reply([2], next: 2))
    #expect(transcript.events.map(\.id) == [1, 2, 3, 4, 5])
    #expect(transcript.next == 5)

    // an event that arrives behind a higher one is put where it belongs
    transcript.apply(reply([7, 6], next: 7, running: false))
    #expect(transcript.events.map(\.id) == [1, 2, 3, 4, 5, 6, 7])
    #expect(transcript.running == false)
}

@Test func theEventsStopWhenTheReplySaysTheSessionEnded() throws {
    let ended = #"{"events":[{"id":1,"at":2,"kind":"say"}],"next":1,"running":false,"structured":true}"#
    let engine = FixtureEngine(capabilities: ["events"], replies: ["events": ended])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, transcript: execution))

    try poller.poll(client)
    now = Date(timeIntervalSince1970: 5)
    try poller.poll(client)
    #expect(engine.commands == ["events"])
    #expect(poller.data[web]?.transcripts[execution]?.events.count == 1)
}

@Test func theEventsOfTheSessionsToCountAreReadOnceEachInTheFirstPollsAfterTheRest() throws {
    let other = "a1b2c3d4-0002-4000-8000-000000000002"
    let ended = #"{"events":[{"id":1,"at":2,"kind":"say"}],"next":1,"running":false,"structured":true}"#
    let engine = FixtureEngine(capabilities: ["sessions", "events", "epic", "files"], replies: ["events": ended])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, counting: [execution, other]))

    var sent: [[String]] = []
    for second in 0...3 {
        now = Date(timeIntervalSince1970: TimeInterval(second))
        let before = engine.commands.count
        try poller.poll(client)
        sent.append(Array(engine.commands.dropFirst(before)))
    }
    // both sessions in the first poll: a page is a request, not a second
    #expect(sent == [["epic", "sessions", "events", "events"], [], [], ["epic"]])
    #expect(engine.requests.compactMap { $0["executionId"] as? String } == [execution, other])
    #expect(Set(poller.data[web]?.transcripts.keys ?? [:].keys) == [execution, other])
}

@Test func aFullPageIsFollowedByTheNextOneFromTheCursor() throws {
    let page = (1...200).map { #"{"id":\#($0),"at":1,"kind":"say"}"# }.joined(separator: ",")
    let engine = FixtureEngine(capabilities: ["events"], replies: ["events": #"{"events":[\#(page)],"next":200,"running":false,"structured":true}"#])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    let poller = EpicPoller(onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, counting: [execution]))
    try poller.poll(client)
    // the next page follows in the same poll, from the cursor (this engine answers the same page forever, so the poll stops at its limit)
    #expect(engine.requests.map { $0["after"] as? Int } == [0] + Array(repeating: 200, count: EpicPoller.pagesPerPoll - 1))
}

@Test func aPollReadsNoMoreThanItsPagesAndTheRestWaitsForTheNextOne() throws {
    let ended = #"{"events":[{"id":1,"at":2,"kind":"say"}],"next":1,"running":false,"structured":true}"#
    let engine = FixtureEngine(capabilities: ["events"], replies: ["events": ended])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    let sessions = (0..<(EpicPoller.pagesPerPoll + 2)).map { String(format: "a1b2c3d4-%04d-4000-8000-000000000001", $0) }
    let poller = EpicPoller(onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, counting: sessions))
    try poller.poll(client)
    #expect(engine.requests.count == EpicPoller.pagesPerPoll)
    try poller.poll(client)
    #expect(Set(engine.requests.compactMap { $0["executionId"] as? String }) == Set(sessions))
}

@Test func aSessionTheEngineRefusesEndsWithAnEmptyTranscriptAndNotALoadingThatNeverEnds() throws {
    let engine = FixtureEngine(capabilities: ["events"], replies: [:])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    let poller = EpicPoller(onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, counting: [execution]))
    try poller.poll(client)
    #expect(transcriptBody(poller.data[web]?.transcripts[execution]) != .loading)
}

@Test func aSessionWithoutAParserHasItsTailReadWithItsEvents() throws {
    let plain = #"{"events":[],"next":0,"running":true,"structured":false}"#
    let engine = FixtureEngine(capabilities: ["events"], replies: ["events": plain, "tail": #"["ran tests","edited a.ts"]"#])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    let poller = EpicPoller(onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: true, transcript: execution))
    try poller.poll(client)
    #expect(engine.commands == ["events", "tail"])
    #expect(transcriptBody(poller.data[web]?.transcripts[execution]) == .tail(["ran tests", "edited a.ts"]))
}

@Test func thePollerSaysWhatTheHelloListedOnlyWhenItChanges() throws {
    var told: [Set<ControlClient.Capability>] = []
    let poller = EpicPoller(onCapabilities: { told.append($0) }, onUpdate: { _, _ in })
    for capabilities in [["epic"], ["epic"], ["epic", "resumeEpic"]] {
        let engine = FixtureEngine(capabilities: capabilities)
        defer { engine.stop() }
        let client = try #require(ControlClient.connect(path: engine.path))
        _ = try client.hello()
        try poller.poll(client)
    }
    #expect(told == [[.epic], [.epic, .resumeEpic]])
}

// MARK: fragments

private let diffReply = #"{"rows":[{"sign":"@","text":"@@ -1 +1 @@"},{"sign":"+","text":"x"}],"truncated":false,"note":null}"#
private let token = OpenFile(section: "slice-121", path: "src/token.ts")

@Test func aFragmentIsAskedOnceWhenItsRowFirstOpensAndKeptWhenItClosesAndOpensAgain() throws {
    let engine = FixtureEngine(capabilities: ["epic", "fileDiff"], replies: ["fileDiff": diffReply])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })

    poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true))
    try poller.poll(client)
    #expect(engine.commands == ["epic"])

    poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [token]))
    now = Date(timeIntervalSince1970: 1)
    try poller.poll(client)
    #expect(engine.commands == ["epic", "fileDiff"])
    #expect(engine.requests.last?["section"] as? String == "slice-121" && engine.requests.last?["path"] as? String == "src/token.ts")
    let kept = poller.data[web]?.fragments[token]
    #expect(kept == .rows([DiffRow(sign: .hunk, text: "@@ -1 +1 @@"), DiffRow(sign: .added, text: "x")], truncated: false))

    // a merged slice does not change while it is read: closed, opened again, ten polls later, still the first reply
    for second in 2...30 {
        now = Date(timeIntervalSince1970: TimeInterval(second))
        poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: second % 2 == 0 ? [] : [token]))
        try poller.poll(client)
    }
    #expect(engine.commands.filter { $0 == "fileDiff" }.count == 1)
    #expect(poller.data[web]?.fragments[token] == kept)
}

@Test func aFragmentThatFailsSaysSoAndTheRestGoesOn() throws {
    let engine = FixtureEngine(capabilities: ["epic", "files", "fileDiff"], fail: ["fileDiff"])
    defer { engine.stop() }
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    let other = OpenFile(section: "slice-121", path: "src/other.ts")

    poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [token]))
    try poller.poll(client)
    #expect(engine.commands == ["epic", "files", "fileDiff"])
    #expect(poller.data[web]?.fragments[token] == .failed)
    #expect(poller.data[web]?.files != nil && poller.data[web]?.epic != nil)

    // a refused file says nothing about the others: the next row is still asked
    poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [token, other]))
    now = Date(timeIntervalSince1970: 1)
    try poller.poll(client)
    #expect(engine.commands == ["epic", "files", "fileDiff", "fileDiff"])
    #expect(engine.requests.last?["path"] as? String == "src/other.ts")
}

@Test func aFragmentThatFailedIsAskedAgainEveryTenSecondsWhileItsRowStaysOpen() throws {
    let failing = FixtureEngine(capabilities: ["fileDiff"], fail: ["fileDiff"])
    let working = FixtureEngine(capabilities: ["fileDiff"], replies: ["fileDiff": diffReply])
    defer { [failing, working].forEach { $0.stop() } }
    let (broken, good) = (try diffClient(failing), try diffClient(working))
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    poller.show(EpicFocus(epic: web, epicRunning: false, filesTabVisible: true, openFiles: [token]))

    for second in 0...15 {
        now = Date(timeIntervalSince1970: TimeInterval(second))
        try poller.poll(broken)
    }
    #expect(failing.commands == ["fileDiff", "fileDiff"])
    #expect(poller.data[web]?.fragments[token] == .failed)

    // the failure was transient: the next ask fills the row, and it is then kept
    now = Date(timeIntervalSince1970: 20)
    try poller.poll(good)
    #expect(working.commands == ["fileDiff"])
    #expect(poller.data[web]?.fragments[token] == .rows([DiffRow(sign: .hunk, text: "@@ -1 +1 @@"), DiffRow(sign: .added, text: "x")], truncated: false))
    now = Date(timeIntervalSince1970: 40)
    try poller.poll(good)
    #expect(working.commands == ["fileDiff"])
}

@Test func noFragmentIsAskedOfAnEngineWithoutFileDiff() throws {
    let rig = try Rig(capabilities: ["epic"])
    rig.poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [token]))
    #expect(try rig.tick(at: 0) == ["epic"])
    #expect(try rig.tick(at: 1).isEmpty)
    #expect(rig.poller.data[web]?.fragments.isEmpty != false)
}

private let laneToken = OpenFile(section: "lane-1", path: "src/auth/token.ts")
private let otherReply = #"{"rows":[{"sign":"@","text":"@@ -1 +1,2 @@"},{"sign":"+","text":"x"},{"sign":"+","text":"y"}],"truncated":false,"note":null}"#

/// Two engines that answer `fileDiff` differently, or fail it: the poller is handed whichever client a test wants for a poll.
private func diffClient(_ engine: FixtureEngine) throws -> ControlClient {
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    return client
}

@Test func anOpenLaneRowIsAskedEveryTenSecondsWhileTheEpicRunsAndTheOldFragmentStaysUntilTheNewOne() throws {
    let first = FixtureEngine(capabilities: ["fileDiff"], replies: ["fileDiff": diffReply])
    let second = FixtureEngine(capabilities: ["fileDiff"], replies: ["fileDiff": otherReply])
    let failing = FixtureEngine(capabilities: ["fileDiff"], fail: ["fileDiff"])
    defer { [first, second, failing].forEach { $0.stop() } }
    let (one, two, broken) = (try diffClient(first), try diffClient(second), try diffClient(failing))
    var now = Date(timeIntervalSince1970: 0)
    let box = UpdateBox()
    let poller = EpicPoller(now: { now }, onUpdate: { key, _ in box.append(key) })
    poller.show(EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [laneToken]))

    // asked at once, then every ten seconds; an unchanged reply redraws nothing
    for second in 0...25 {
        now = Date(timeIntervalSince1970: TimeInterval(second))
        try poller.poll(one)
        #expect(poller.data[web]?.fragments[laneToken] != nil)
    }
    #expect(first.commands == ["fileDiff", "fileDiff", "fileDiff"])
    #expect(box.all.count == 1)
    let old = poller.data[web]?.fragments[laneToken]

    // a failed refresh keeps the last fragment
    now = Date(timeIntervalSince1970: 30)
    try poller.poll(broken)
    #expect(failing.commands == ["fileDiff"])
    #expect(poller.data[web]?.fragments[laneToken] == old)

    // the new fragment replaces the old one when it arrives, and not before
    now = Date(timeIntervalSince1970: 35)
    try poller.poll(two)
    #expect(second.commands.isEmpty && poller.data[web]?.fragments[laneToken] == old)
    now = Date(timeIntervalSince1970: 40)
    try poller.poll(two)
    #expect(poller.data[web]?.fragments[laneToken] == .rows([DiffRow(sign: .hunk, text: "@@ -1 +1,2 @@"), DiffRow(sign: .added, text: "x"), DiffRow(sign: .added, text: "y")], truncated: false))
}

@Test func anOpenLaneRowIsAskedOnceWhenTheEpicIsNotRunningAndNotAtAllOnceItIsClosed() throws {
    let engine = FixtureEngine(capabilities: ["fileDiff"], replies: ["fileDiff": diffReply])
    defer { engine.stop() }
    let client = try diffClient(engine)
    var now = Date(timeIntervalSince1970: 0)
    let poller = EpicPoller(now: { now }, onUpdate: { _, _ in })
    let tick = { (second: Int, focus: EpicFocus) in
        now = Date(timeIntervalSince1970: TimeInterval(second))
        poller.show(focus)
        try poller.poll(client)
    }

    for second in stride(from: 0, through: 40, by: 5) { try tick(second, EpicFocus(epic: web, epicRunning: false, filesTabVisible: true, openFiles: [laneToken])) }
    #expect(engine.commands == ["fileDiff"])

    // running again, then the row closed (the tab closed too: the view hands no open rows then): no more asking
    try tick(50, EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [laneToken]))
    #expect(engine.commands.count == 2)
    for second in stride(from: 55, through: 90, by: 5) { try tick(second, EpicFocus(epic: web, epicRunning: true, filesTabVisible: true)) }
    #expect(engine.commands.count == 2)
    // opened again while the epic runs: asked at once, the kept fragment on screen meanwhile
    try tick(91, EpicFocus(epic: web, epicRunning: true, filesTabVisible: true, openFiles: [laneToken]))
    #expect(engine.commands.count == 3)
}
