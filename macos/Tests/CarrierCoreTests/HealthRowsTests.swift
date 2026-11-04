import Testing
@testable import CarrierCore

// The rows of the Health tab: what the host says of this Mac and what the app knows of Carrier.

private let allWell = CarrierFacts(carrierFound: true, installedVersion: "1.4.0", hostRunning: true, hostVersion: "1.4.0", hostReportsHealth: true, configExists: true, engineRunning: true)

private func health(git: ToolState = .ready, gh: ToolState = .ready, claude: ToolState = .ready, codex: ToolState = .ready) -> HostHealth {
    HostHealth(git: git, gh: gh, agents: [
        .init(name: "claude", harness: "claude", state: claude), .init(name: "codex", harness: "codex", state: codex),
    ])
}

@Test func thisMacListsGitGhAndEachAgentWithTheirState() throws {
    let mac = try #require(healthSections(host: health(gh: .signedOut, codex: .missing), facts: allWell).first)
    #expect(mac.title == "This Mac" && mac.note == nil)
    #expect(mac.rows.map(\.title) == ["git", "gh", "claude", "codex"])
    #expect(mac.rows.map(\.detail) == ["Ready", "Signed out", "Ready", "Not installed"])
    #expect(mac.rows.map(\.mark) == [.ok, .problem, .ok, .problem])
}

@Test func aRowAsksTheFixedListAboutItsToolAndState() throws {
    let mac = try #require(healthSections(host: health(git: .missing, claude: .signedOut), facts: allWell).first)
    #expect(mac.rows[0].tool == .git && mac.rows[0].state == .missing)
    #expect(mac.rows[2].tool == .agent(harness: "claude") && mac.rows[2].state == .signedOut)
    #expect(healthFix(.agent(harness: "claude"), mac.rows[2].state)?.label == "claude auth login")
}

@Test func anUnknownProbeIsNeitherAProblemNorReady() throws {
    let mac = try #require(healthSections(host: health(gh: .unknown), facts: allWell).first)
    #expect(mac.rows[1].mark == .neutral && mac.rows[1].detail == "Could not check")
}

@Test func withoutHealthTheMacSaysWhyAndCarrierIsStillThere() {
    var tooOld = allWell
    tooOld.hostReportsHealth = false
    let old = healthSections(host: nil, facts: tooOld)
    #expect(old[0].rows.isEmpty && old[0].note?.contains("too old") == true)
    #expect(old[1].title == "Carrier" && old[1].rows.count == 3)

    // a host that lists `health` but has not answered (in flight, or the request failed) is not called old
    let pending = healthSections(host: nil, facts: allWell)[0]
    #expect(pending.rows.isEmpty && pending.note?.contains("too old") == false && pending.note?.contains("Check again") == true)

    var stopped = allWell
    stopped.hostRunning = false
    #expect(healthSections(host: nil, facts: stopped)[0].note?.contains("not running") == true)
}

@Test func carrierIsFoundWithItsVersionOrNot() {
    #expect(healthSections(host: nil, facts: allWell)[1].rows[0] == HealthRow(title: "carrier", mark: .ok, detail: "Found · version 1.4.0"))
    var facts = allWell
    facts.installedVersion = nil
    #expect(healthSections(host: nil, facts: facts)[1].rows[0].detail == "Found")
    facts.carrierFound = false
    let row = healthSections(host: nil, facts: facts)[1].rows[0]
    #expect(row.mark == .problem && row.detail.hasPrefix("Not found"))
}

@Test func theChatHostRunsStaleOrNot() {
    func host(_ facts: CarrierFacts) -> HealthRow { healthSections(host: nil, facts: facts)[1].rows[1] }
    #expect(host(allWell) == HealthRow(title: "Chat host", mark: .ok, detail: "Running · version 1.4.0"))
    var older = allWell
    older.hostVersion = "1.3.0"
    #expect(host(older).mark == .problem && host(older).detail.contains("Restart it"))
    var unreadable = allWell
    unreadable.installedVersion = nil
    #expect(host(unreadable).mark == .ok)
    var stopped = allWell
    stopped.hostRunning = false
    #expect(host(stopped) == HealthRow(title: "Chat host", mark: .problem, detail: "Not running"))
}

@Test func theEngineIsNotConfiguredStoppedOrRunning() {
    func engine(_ facts: CarrierFacts) -> HealthRow { healthSections(host: nil, facts: facts)[1].rows[2] }
    var facts = allWell
    #expect(engine(facts) == HealthRow(title: "Engine", mark: .ok, detail: "Running"))
    facts.engineRunning = false
    #expect(engine(facts) == HealthRow(title: "Engine", mark: .neutral, detail: "Configured, stopped"))
    facts.configExists = false
    #expect(engine(facts).mark == .problem && engine(facts).detail.contains("not configured"))
}

@Test func theEnginesSetupListsTheDoctorsChecksWithTheirStateDetailAndFixText() {
    let checks = [
        DoctorCheck(name: "config", status: .ok), DoctorCheck(name: "gh", status: .warn, detail: "old", fix: "brew upgrade gh"),
        DoctorCheck(name: "labels", status: .fail, detail: "missing", fix: "carrier init"),
    ]
    let section = healthSections(host: nil, facts: allWell, doctor: .checks(checks))[2]
    #expect(section.title == "Engine setup" && section.note == nil)
    #expect(section.rows.map(\.title) == ["config", "gh", "labels"])
    #expect(section.rows.map(\.mark) == [.ok, .warning, .problem])
    #expect(section.rows.map(\.detail) == ["", "old", "missing"])
    #expect(section.rows.map(\.fix) == [nil, "brew upgrade gh", "carrier init"])
    #expect(section.rows.allSatisfy { $0.tool == nil })
}

@Test func theEnginesSetupNeedsTheConfigAndRunsNothingWithoutOne() {
    var facts = allWell
    facts.configExists = false
    for doctor in [DoctorState.idle, .running, .checks([DoctorCheck(name: "x", status: .ok)])] {
        let section = healthSections(host: nil, facts: facts, doctor: doctor)[2]
        #expect(section.rows.isEmpty && section.note?.contains("needs the config") == true)
    }
}

@Test func theEnginesSetupSaysItIsRunningAndShowsAnUnknownDoctorAsSuchWithItsReason() {
    #expect(healthSections(host: nil, facts: allWell, doctor: .running)[2].note?.contains("Running") == true)
    let row = healthSections(host: nil, facts: allWell, doctor: .unknown("did not finish"))[2].rows[0]
    #expect(row.mark == .neutral && row.detail == "Could not check: did not finish")
}
