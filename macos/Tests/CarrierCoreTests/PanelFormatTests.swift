import Foundation
import Testing
@testable import CarrierCore

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

private func fixture() throws -> PanelSnapshot { try decodeSnapshot(Data(contentsOf: fixtureURL)) }

@Test func durationsKeepSecondsOnlyUnderAMinute() {
    #expect(formatDuration(45_000) == "45s")
    #expect(formatDuration(185_000) == "3m")
    #expect(formatDuration(7_380_000) == "2h 03m")
    #expect(formatDuration(100_800_000) == "1d 4h")
    #expect(formatDuration(-5000) == "0s")
}

@Test func theStageChainMarksTheCurrentStage() {
    #expect(stageChain(.review) == [StageStep(name: "ship", current: false), StageStep(name: "review", current: true), StageStep(name: "fix", current: false)])
}

@Test func anEpicWithNoStageYetHasNoCurrentStage() {
    #expect(stageChain(nil).map(\.name) == ["ship", "review", "fix"])
    #expect(stageChain(nil).allSatisfy { $0.current == false })
}

@Test func theSlicesLineIsClosedOverTotalOrAbsent() throws {
    let epics = try fixture().epics
    #expect(slicesLine(epics[0].slices) == "3/5 slices")
    #expect(slicesLine(epics[1].slices) == nil)
    #expect(slicesLine(PanelEpic.Slices(done: 0, total: 0)) == nil)
}

@Test func theEpicLinesFollowTheSnapshotClock() throws {
    let snapshot = try fixture()
    let (running, fresh) = (snapshot.epics[0], snapshot.epics[1])
    #expect(roundLine(running) == "round 2/5")
    #expect(roundLine(fresh) == nil)
    #expect(stageTimeLine(running, now: snapshot.now) == "1m in stage")
    #expect(activityLine(running, now: snapshot.now) == "active 10s ago")
    #expect(activityLine(fresh, now: snapshot.now) == "no activity yet")
    #expect(blockersLine(1) == "1 blocker")
    #expect(blockersLine(2) == "2 blockers")
}

@Test func theHeaderLines() throws {
    var snapshot = try fixture()
    #expect(uptimeLine(snapshot) == "up 1m")
    #expect(reposLine(snapshot.repos) == "watching 2 repos")
    #expect(reposLine(1) == "watching 1 repo")
    #expect(nextCheckLine(snapshot) == "next check in 1m")
    #expect(overviewSubtitle(snapshot, repos: 5) == "5 repos · up 1m · next check in 1m")
    #expect(overviewSubtitle(snapshot, repos: 1).hasPrefix("1 repo ·"))
    snapshot.nextCheckAt = snapshot.now
    #expect(nextCheckLine(snapshot) == "checking now")
    snapshot.nextCheckAt = nil
    #expect(nextCheckLine(snapshot) == "starting")
}

@Test func onlyWebLinksOpenInTheBrowser() {
    #expect(browserURL("https://github.com/acme/web/pull/50") != nil)
    #expect(browserURL("file:///etc/passwd") == nil)
    #expect(browserURL("not a url") == nil)
}

@Test func finishedEpicsLinkToGitHub() throws {
    let done = try fixture().done
    #expect(donePullURL(done[0]) == "https://github.com/acme/web/pull/77")
    #expect(donePullURL(done[1]) == nil)
    #expect(doneIssueURL(done[1]) == "https://github.com/acme/api/issues/31")
    #expect(agoLine(done[0].finishedAt, now: 100_000) == "5s ago")
    #expect(agoLine(nil, now: 100_000) == "a while ago")
}

@Test func aCheckIsUnderWayUntilTheNextOneIsScheduledAgain() throws {
    var snapshot = try fixture()
    snapshot.now = 1_000_000
    snapshot.nextCheckAt = 1_060_000
    let start = Date(timeIntervalSince1970: 0)
    let asked = CheckAsked(at: start, nextCheckAt: 1_060_000)
    // nothing asked, nothing due
    #expect(isChecking(snapshot, asked: nil, now: start) == false)
    // just pressed: seen at least a second, whatever the snapshot says
    snapshot.nextCheckAt = 1_120_000
    #expect(isChecking(snapshot, asked: asked, now: start + 0.5))
    // the next check moved: the poll ended
    #expect(isChecking(snapshot, asked: asked, now: start + 2) == false)
    // not moved yet: still going, until the limit
    snapshot.nextCheckAt = 1_060_000
    #expect(isChecking(snapshot, asked: asked, now: start + 10))
    #expect(isChecking(snapshot, asked: asked, now: start + 31) == false)
    // one that is due counts, asked from here or not
    snapshot.nextCheckAt = 999_000
    #expect(isChecking(snapshot, asked: nil, now: start))
}

@Test func aLongPasteGoesWithTheMessageInAFencedBlockAndComesBackOutOfIt() {
    let log = (1...50).map { "line \($0)" }.joined(separator: "\n")
    let message = messageWithPastes("why does this fail?", pastes: [log, "second `code` ``` fence"])
    #expect(message.hasPrefix("why does this fail?\n\n```pasted\nline 1\n") && message.contains("````pasted\nsecond `code` ``` fence\n````"))
    let back = splitPastes(message)
    #expect(back.text == "why does this fail?" && back.pastes == [log, "second `code` ``` fence"])
    // no text, no pastes, an unclosed block and an ordinary fence are left as they are
    #expect(splitPastes(messageWithPastes("", pastes: [log])).text == "" && splitPastes(messageWithPastes("", pastes: [log])).pastes == [log])
    #expect(messageWithPastes("hi", pastes: []) == "hi")
    #expect(splitPastes("hi\n```pasted\nnever closed").pastes.isEmpty)
    #expect(splitPastes("hi\n```swift\nlet a = 1\n```").pastes.isEmpty)
}

@Test func whatAPasteHoldsIsSaidInOneLine() {
    #expect(pasteStats(String(repeating: "a", count: 3412)) == "3,412 chars · 1 line · ~853 tokens")
    #expect(pasteStats(Array(repeating: "x", count: 87).joined(separator: "\n")).contains("87 lines"))
}

@Test func aQueuedMessageWithAPasteShowsWhatWasTypedAndOneLineForTheText() {
    let message = messageWithPastes("why?", pastes: [Array(repeating: "x", count: 87).joined(separator: "\n")])
    #expect(messagePreview(message) == "why?\nPasted text · 87 lines")
    #expect(messagePreview(messageWithPastes("", pastes: ["a\nb"])) == "Pasted text · 2 lines")
    #expect(messagePreview("plain") == "plain")
}
