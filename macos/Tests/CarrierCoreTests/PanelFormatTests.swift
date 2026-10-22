import Foundation
import Testing
@testable import CarrierCore

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")

private func fixture() throws -> PanelSnapshot { try decodeSnapshot(Data(contentsOf: fixtureURL)) }

@Test func durationsUseTheTwoLargestUnits() {
    #expect(formatDuration(45_000) == "45s")
    #expect(formatDuration(185_000) == "3m 05s")
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
    #expect(stageTimeLine(running, now: snapshot.now) == "1m 00s in stage")
    #expect(activityLine(running, now: snapshot.now) == "active 10s ago")
    #expect(activityLine(fresh, now: snapshot.now) == "no activity yet")
    #expect(blockersLine(1) == "1 blocker")
    #expect(blockersLine(2) == "2 blockers")
}

@Test func theHeaderLines() throws {
    var snapshot = try fixture()
    #expect(uptimeLine(snapshot) == "up 1m 00s")
    #expect(reposLine(snapshot.repos) == "watching 2 repos")
    #expect(reposLine(1) == "watching 1 repo")
    #expect(nextCheckLine(snapshot) == "next check in 1m 00s")
    #expect(overviewSubtitle(snapshot, repos: 5) == "5 repos · up 1m 00s · next check in 1m 00s")
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
