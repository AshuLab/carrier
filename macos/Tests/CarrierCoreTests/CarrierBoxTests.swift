import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

private func load(_ name: String, _ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    var snapshot = try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent(name)))
    change(&snapshot)
    return snapshot
}

@Test func aRunningCarrierShowsUptimeNextCheckAndIntake() throws {
    let box = carrierBox(try load("snapshot.json") { $0.problem = nil; $0.paused = false })
    #expect(box.title == "Carrier running")
    #expect(box.uptime == "up 1m")
    #expect(box.problem == nil)
    #expect(box.rows.first == .init(label: "Next check", value: "in 1m"))
    #expect(box.intake.value == "Active" && box.intake.actionTitle == "Pause" && box.intake.command == .pause)
}

@Test func nextCheckSaysCheckingNowOrStarting() throws {
    #expect(carrierBox(try load("snapshot.json") { $0.nextCheckAt = $0.now }).rows[0].value == "checking now")
    #expect(carrierBox(try load("snapshot.json") { $0.nextCheckAt = nil }).rows[0].value == "starting")
}

@Test func anEngineProblemIsCarried() throws {
    #expect(carrierBox(try load("snapshot.json")).problem == "GitHub is not answering")
}

@Test func pausedIntakeOffersResume() throws {
    let box = carrierBox(try load("snapshot.json"))
    #expect(box.intake.value == "Paused" && box.intake.actionTitle == "Resume" && box.intake.command == .resume)
}

@Test func theRateLimitNamesItsProfileAndResetTime() throws {
    let box = carrierBox(try load("snapshot.json"))
    #expect(box.rows[1] == .init(label: "GitHub rate limit (orchestrator profile)", value: "4,812 / 5,000 · resets in 30s"))
    let past = carrierBox(try load("snapshot.json") { $0.engine?.rateLimit?.resetAt = 1 })
    #expect(past.rows[1].value == "4,812 / 5,000 · reset")
}

@Test func noRateLimitNoRow() throws {
    let box = carrierBox(try load("snapshot.json") { $0.engine?.rateLimit = nil })
    #expect(box.rows.map(\.label) == ["Next check"])
}

@Test func eachWatchedRepoShowsItsLastCheckAndAFailureShowsItsError() throws {
    let box = carrierBox(try load("snapshot.json"))
    #expect(box.repos == [
        .init(name: "acme/web", url: "github.com/acme/web", status: .paused, ok: true, lastCheck: "2s ago", error: nil),
        .init(name: "acme/api", url: "github.com/acme/api", status: .failing, ok: false, lastCheck: "2s ago", error: "GitHub answered 502"),
    ])
    #expect(carrierBox(try load("snapshot.json") { $0.paused = false }).repos.map(\.status) == [.watching, .failing])
    let fresh = carrierBox(try load("snapshot.json") { $0.watched?[0].lastCheckedAt = nil; $0.watched?[1].error = nil })
    #expect(fresh.repos[0].lastCheck == "not checked yet")
    #expect(fresh.repos[1].error == "the last check failed")
}

@Test func anOlderEngineHasNoRateLimitNoRepoListAndStillCountsRepos() throws {
    let box = carrierBox(try load("snapshot-old-engine.json"))
    #expect(box.rows.map(\.label) == ["Next check"])
    #expect(box.repos.isEmpty)
    #expect(box.repoCount == 2)
}

@Test func theIntakeLinkSendsItsCommandToTheFixtureServer() throws {
    let server = try FixtureServer(fixtures: fixtures.path)
    defer { server.stop() }
    let box = carrierBox(try load("snapshot.json"))
    try send(box.intake.command, socketPath: server.socketPath)
}
