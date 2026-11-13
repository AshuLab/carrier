import Foundation
import Testing
@testable import CarrierCore

private let note = "Carrier reads it when it starts"
private let engine = "/Users/ana/.carrier/engine"
private func snapshot(_ watched: [(String, Bool)]) throws -> PanelSnapshot {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json")
    var snapshot = try decodeSnapshot(Data(contentsOf: url))
    let agents = try #require(snapshot.watched?.first).agents
    snapshot.watched = watched.map { PanelSnapshot.Watched(repo: $0.0, lastCheckedAt: snapshot.now - 120_000, ok: $0.1, error: $0.1 ? nil : "GitHub refused it", agents: agents) }
    return snapshot
}

@Test func aRepoTheEngineKnowsShowsItsEpicsAndItsLastCheck() throws {
    var live = try snapshot([("a/b", true)])
    live.epics = []
    live.queue = []
    let row = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: live)[0]
    let status = repoStatus(row, engine: engine, home: "/Users/ana", cloneExists: true, notLoaded: note)
    #expect(status.epics == "None ready · none running" && status.lastCheck == "Checked 2m ago" && status.note == nil)
    #expect(status.clone == "~/.carrier/engine/repos/a/b" && status.clonePath == "\(engine)/repos/a/b")
    #expect(status.canRevealClone && status.gitHubURL?.absoluteString == "https://github.com/a/b")
}

@Test func theEpicsReadyRunningAndWaitingAreSaid() {
    let row = RepoRow(name: "a/b", health: .ok, line: "Checked 2m ago", epics: RepoEpics(running: 1, queued: 3, needsYou: 2), isNew: false, isLoaded: true)
    #expect(repoStatus(row, engine: engine, cloneExists: true, notLoaded: note).epics == "3 ready · 1 running · 2 needs you")
}

@Test func aRepoThatFailedStillShowsTheEnginesReason() throws {
    let row = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: try snapshot([("a/b", false)]))[0]
    #expect(repoStatus(row, engine: engine, cloneExists: true, notLoaded: note).lastCheck == "GitHub refused it")
}

@Test func aRepoTheEngineHasNotLoadedSaysCarrierReadsItWhenItStarts() throws {
    let live = try snapshot([("a/b", true)])
    // in the file, not loaded; and in the draft, not in the file yet
    for row in repoRows(draft: ["later/one", "new/repo"], saved: ["later/one"], snapshot: live) {
        let status = repoStatus(row, engine: engine, cloneExists: false, notLoaded: note)
        #expect(status.epics == nil && status.lastCheck == nil && status.note == note)
    }
}

@Test func whileCarrierIsStoppedEveryRepoSaysCarrierReadsItWhenItStarts() {
    let row = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil)[0]
    let status = repoStatus(row, engine: engine, cloneExists: true, notLoaded: note)
    #expect(status.epics == nil && status.lastCheck == nil && status.note == note)
}

@Test func revealIsAbsentForARepoNeverCloned() {
    let row = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil)[0]
    let status = repoStatus(row, engine: engine, cloneExists: false, notLoaded: note)
    #expect(status.canRevealClone == false && status.gitHubURL != nil)
}
