import Foundation
import Testing
@testable import CarrierCore

private func stuck(_ kind: String?, status: PanelEpic.Status = .needsHuman) -> PanelEpic {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: .ship, round: nil, maxReviews: 5, blockers: 0, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil,
        slices: nil, executionId: nil
    )
    epic.needsHumanKind = kind
    return epic
}

private let failures = ["retries_exhausted", "timeout", "auth", "workspace", "pr_invalid"]
private let allKinds = ["review_limit", "agent_needs_human"] + failures

@Test func aStoppedEpicGetsACardWithTheReasonInWordsWhateverTheKind() {
    let titles = allKinds.map { resumeCard(stuck($0), canResume: true)?.title }
    #expect(titles == [
        "Review limit reached", "The agent needs you", "Retries exhausted", "Timed out", "Authentication failed", "Workspace problem",
        "Pull request invalid",
    ])
}

@Test func theCardIsOrangeWhenInputIsNeededAndRedWhenSomethingFailed() {
    #expect(allKinds.map { resumeCard(stuck($0), canResume: true)?.attention } == [.input, .input] + Array(repeating: .error, count: 5))
}

@Test func theWordsSayWhatResumingDoesForTheKind() {
    for kind in failures {
        #expect(resumeCard(stuck(kind), canResume: true)?.words == "Fix the cause first, then resume to start the epic again from ship.")
    }
    #expect(resumeCard(stuck("review_limit"), canResume: true)?.words == "Resuming gives the epic 5 new review rounds.")
    var more = stuck("review_limit")
    more.maxReviews = 3
    #expect(resumeCard(more, canResume: true)?.words == "Resuming gives the epic 3 new review rounds.")
    #expect(resumeCard(stuck("agent_needs_human"), canResume: true)?.words == "Do what the agent asked on the pull request first, then resume.")
}

@Test func aKindTheAppDoesNotKnowIsOrangeWithItsReasonAndGenericWords() {
    var odd = stuck("from_the_future")
    odd.needsHumanReason = "something new"
    let card = resumeCard(odd, canResume: true)
    #expect(card?.title == "Something new" && card?.attention == .input && card?.words == "Deal with the cause first, then resume.")
    #expect(resumeCard(stuck(nil), canResume: true)?.title == "Needs you")
}

@Test func theButtonShowsOnlyForAnEngineThatCanBeAsked() {
    for kind in allKinds {
        let (asked, notAsked) = (resumeCard(stuck(kind), canResume: true), resumeCard(stuck(kind), canResume: false))
        #expect(asked?.showsButton == true && notAsked?.showsButton == false)
        // the reason and the words stay either way
        #expect(asked?.title == notAsked?.title && asked?.words == notAsked?.words)
    }
}

@Test func anEpicThatIsNotStoppedHasNoCard() {
    #expect(resumeCard(stuck("timeout", status: .running), canResume: true) == nil)
    #expect(resumeCard(stuck(nil, status: .running), canResume: true) == nil)
}

@Test func theSheetSaysWhatWillHappen() {
    #expect(resumeCard(stuck("auth"), canResume: true)?.sheet == [
        "solve:epic:ready goes back on the issue.",
        "The epic starts again from ship, reusing its worktree and its pull request.",
        "The review rounds start over.",
        "If the cause is not fixed, it stops here again.",
    ])
}

// MARK: the request

private func connect(_ engine: FixtureEngine) throws -> ControlClient {
    let client = try #require(ControlClient.connect(path: engine.path))
    _ = try client.hello()
    return client
}

@Test func resumeEpicSendsTheRepositoryAndTheNumber() throws {
    let engine = FixtureEngine(capabilities: ["resumeEpic"], replies: ["resumeEpic": "null"])
    defer { engine.stop() }
    #expect(try connect(engine).resumeEpic(repo: "acme/web", issue: 12))
    let sent = engine.requests
    #expect(sent.count == 1 && sent[0]["cmd"] as? String == "resumeEpic" && sent[0]["repo"] as? String == "acme/web" && sent[0]["issue"] as? Int == 12)
}

@Test func nothingIsSentToAnEngineThatDoesNotListResumeEpic() throws {
    let engine = FixtureEngine(capabilities: ["epic"])
    defer { engine.stop() }
    #expect(try connect(engine).resumeEpic(repo: "acme/web", issue: 12) == false)
    #expect(engine.commands.isEmpty)
}

@Test func aBadRepositoryIsRefusedBeforeItIsSent() throws {
    let engine = FixtureEngine(capabilities: ["resumeEpic"])
    defer { engine.stop() }
    #expect(throws: ControlError.remote("not a valid epic")) { try connect(engine).resumeEpic(repo: "a\"b/web", issue: 12) }
    #expect(throws: ControlError.remote("not a valid epic")) { try connect(engine).resumeEpic(repo: "acme/web", issue: 0) }
    #expect(engine.commands.isEmpty)
}

@Test func aRefusalDoesNotTakeTheCapabilityAway() throws {
    let engine = FixtureEngine(capabilities: ["resumeEpic"], fail: ["resumeEpic"])
    defer { engine.stop() }
    let client = try connect(engine)
    #expect(throws: ControlError.remote("internal error")) { try client.resumeEpic(repo: "acme/web", issue: 12) }
    #expect(client.capabilities.contains(.resumeEpic))
}

@Test func theResultCoversAnAnsweredRequestAndTheWaysItFails() {
    let engine = FixtureEngine(capabilities: ["resumeEpic"], replies: ["resumeEpic": "null"])
    defer { engine.stop() }
    #expect(resumeEpic(socketPath: engine.path, repo: "acme/web", issue: 12) == .resumed)
    let refusing = FixtureEngine(capabilities: ["resumeEpic"], fail: ["resumeEpic"])
    defer { refusing.stop() }
    #expect(resumeEpic(socketPath: refusing.path, repo: "acme/web", issue: 12) == .refused("internal error"))
    let old = FixtureEngine(capabilities: ["epic"])
    defer { old.stop() }
    #expect(resumeEpic(socketPath: old.path, repo: "acme/web", issue: 12) == .unsupported)
    #expect(resumeEpic(socketPath: "/tmp/carrier-no-such-socket", repo: "acme/web", issue: 12) == .stopped)
}

// MARK: the words of a refusal

@Test func eachRefusalHasItsOwnWords() {
    #expect(ResumeRefusal.allCases.map(\.rawValue) == ["unknown epic", "not stopped", "github unavailable", "did not restart"])
    #expect(ResumeRefusal.allCases.map { resumeFailureWords(.refused($0.rawValue)) } == [
        "Carrier does not know this epic.",
        "This epic is not stopped, so there is nothing to resume.",
        "GitHub did not answer, so nothing was resumed. Try again.",
        "The label is back on the issue, but the epic did not start within thirty seconds. The next check will take it.",
    ])
}

@Test func anythingElseGetsAGenericLineAndTheOtherResultsTheirOwn() {
    #expect(resumeFailureWords(.refused("internal error")) == "Carrier could not resume this epic (internal error).")
    #expect(resumeFailureWords(.stopped) == "Carrier is not running.")
    #expect(resumeFailureWords(.unsupported) == "This Carrier cannot resume epics. Update it.")
    #expect(resumeFailureWords(.resumed) == nil)
}

// MARK: the fixture

@Test func theFixtureServerListsAndAnswersResumeEpic() throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    #expect(resumeEpic(socketPath: server.socketPath, repo: "acme/api", issue: 6) == .resumed)
}

@Test func theGoldenSnapshotHasAStoppedEpicOfEachKindAndOthersThatAreNotStopped() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")
    let epics = try decodeSnapshot(Data(contentsOf: url)).epics
    #expect(Set(epics.filter { $0.status == .needsHuman }.compactMap(\.needsHumanKind)) == Set(allKinds))
    #expect(epics.filter { $0.status == .running }.allSatisfy { resumeCard($0, canResume: true) == nil })
    #expect(epics.filter { $0.status == .needsHuman }.allSatisfy { resumeCard($0, canResume: true) != nil })
}

// MARK: a Resume in flight

private func snapshot(_ epics: [PanelEpic]) throws -> PanelSnapshot {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")
    var snapshot = try decodeSnapshot(Data(contentsOf: url))
    snapshot.epics = epics
    return snapshot
}

@Test func aResumeInFlightSurvivesUntilTheSnapshotShowsTheEpicOutOfNeedsHuman() throws {
    let (store, ref) = (EpicStore(), EpicRef(repo: "acme/web", issue: 12))
    store.startResuming(ref)
    store.answeredResume(ref, refusal: nil) // the engine said the epic started: the snapshot may not have caught up
    store.settleResuming(try snapshot([stuck("timeout")]))
    #expect(store.resuming == [ref])
    store.settleResuming(try snapshot([stuck("timeout", status: .running)]))
    #expect(store.resuming.isEmpty)
}

@Test func aResumeEndsWhenASnapshotAfterTheAnswerStillShowsTheEpicStopped() throws {
    let (store, ref) = (EpicStore(), EpicRef(repo: "acme/web", issue: 12))
    store.startResuming(ref)
    store.answeredResume(ref, refusal: nil, at: 1_000)
    var before = try snapshot([stuck("timeout")])
    before.now = 900 // generated before the answer: the epic may not have left needs-human in it yet
    store.settleResuming(before)
    #expect(store.resuming == [ref])
    var after = try snapshot([stuck("workspace")])
    after.now = 1_100 // generated after the answer and the epic is stopped: it failed again at once
    store.settleResuming(after)
    #expect(store.resuming.isEmpty)
}

@Test func aRefusalEndsTheResumeAndKeepsItsWordsWhileTheEpicStaysStopped() throws {
    let (store, ref) = (EpicStore(), EpicRef(repo: "acme/web", issue: 12))
    store.startResuming(ref)
    store.answeredResume(ref, refusal: "GitHub did not answer, so nothing was resumed. Try again.")
    #expect(store.resuming.isEmpty && store.resumeRefusals[ref] != nil)
    store.settleResuming(try snapshot([stuck("timeout")]))
    #expect(store.resumeRefusals[ref] != nil)
    store.startResuming(ref)
    #expect(store.resumeRefusals[ref] == nil)
    store.answeredResume(ref, refusal: "x")
    store.settleResuming(try snapshot([]))
    #expect(store.resumeRefusals.isEmpty)
}
