import Foundation
import Testing
@testable import CarrierCore

// "Ready for Carrier": the four rows of a repo from the doctor's checks, the role-to-check match and what reads as waiting.

private let config = Data(#"""
{"repos":[{"name":"o/r"},{"name":"o/own","agents":{"reviewer":{"profile":"bot-b"}}}],
 "profiles":{"me":{"kind":"gh"},"bot-a":{"kind":"forge"},"bot-b":{"kind":"forge"},"bot-c":{"kind":"forge"}},
 "agents":{"author":{"profile":"bot-a"},"reviewer":{"profile":"bot-c"}}}
"""#.utf8)

private func roles(_ repo: String) -> [RepoRoleRow] { repoRoles(json: config, repo: repo)?.rows ?? [] }

private func mint(_ agent: String, _ repo: String, _ profiles: [String], _ status: DoctorCheck.Status = .ok, detail: String? = nil, fix: String? = nil) -> DoctorCheck {
    DoctorCheck(name: "forge agent \(agent) can mint a token for \(repo)", status: status, detail: detail, fix: fix, repo: repo, profiles: profiles)
}

private func read(_ repo: String, _ status: DoctorCheck.Status = .ok) -> DoctorCheck {
    DoctorCheck(name: "your gh login can read \(repo)", status: status, repo: repo, profiles: ["me"])
}

private func solve(_ repo: String, _ status: DoctorCheck.Status = .ok, detail: String? = nil, fix: String? = nil) -> DoctorCheck {
    DoctorCheck(name: "\(repo) has the Solve labels", status: status, detail: detail, fix: fix, repo: repo, profiles: ["me"])
}

private func summary(_ checks: RepoChecks) -> [String] {
    checks.rows.map { "\($0.title): \($0.status)" + ($0.detail.map { " (\($0))" } ?? "") }
}

@Test func allOkGivesFourOkRows() {
    let doctor = DoctorState.checks([read("o/r"), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"]), solve("o/r")])
    let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor)
    #expect(summary(found) == ["Carrier can read it: ok", "Author can sign here: ok", "Reviewer can sign here: ok", "Solve is set up: ok"])
    #expect(found.note == nil)
}

@Test func aFailedSignCheckKeepsItsReasonAndFixAndNamesTheRole() throws {
    let doctor = DoctorState.checks([
        read("o/r"), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"], .fail, detail: "app not installed", fix: "install it"), solve("o/r"),
    ])
    let reviewer = try #require(repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor).rows.first { $0.role == .reviewer })
    #expect(reviewer.status == .fail && reviewer.detail == "app not installed" && reviewer.fix == "install it")
}

@Test func aFailedSolveCheckNamesTheMissingLabels() {
    let doctor = DoctorState.checks([read("o/r"), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"]), solve("o/r", .fail, detail: "missing solve:epic", fix: "run solve:setup")])
    let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor)
    #expect(summary(found).last == "Solve is set up: fail (missing solve:epic)")
    #expect(found.rows.last?.fix == "run solve:setup")
}

@Test func everyCheckTheDoctorDidNotReportReadsAsWaitingNotFailed() {
    // the read check failed, so there is no Solve check; the mints of the reviewer were never made
    let doctor = DoctorState.checks([read("o/r", .fail), mint("a", "o/r", ["bot-a"])])
    let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor)
    #expect(found.rows.map(\.status) == [.fail, .ok, .waiting, .waiting])
    let none = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: .checks([read("o/other")]))
    #expect(none.rows.map(\.status) == [.waiting, .waiting, .waiting, .waiting])
}

@Test func aDoctorThatHasNotAnsweredLeavesEveryRowWaitingWithTheReason() {
    for state in [DoctorState.idle, .running, .unknown("could not start")] {
        let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: state)
        #expect(found.rows.map(\.status) == [.waiting, .waiting, .waiting, .waiting])
    }
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .unknown("boom")).note == "Could not check: boom")
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .idle).note == nil)
}

@Test func aRoleWithItsOwnIdentityIsMatchedToTheCheckOfThatIdentity() {
    // o/own overrides the reviewer to bot-b; the global reviewer bot-c has a check there that is not the reviewer's
    let doctor = DoctorState.checks([mint("a", "o/own", ["bot-a"]), mint("b", "o/own", ["bot-b"], .fail, detail: "no app"), mint("c", "o/own", ["bot-c"])])
    let found = repoChecks(repo: "o/own", roles: roles("o/own"), doctor: doctor)
    #expect(found.rows[2].status == .fail && found.rows[2].detail == "no app")
}

@Test func twoRolesThatShareOneCheckShowItOnBoth() {
    // the doctor made one mint for the bot and lists both profile names that resolve to it
    let doctor = DoctorState.checks([mint("a", "o/r", ["bot-a", "bot-c"], .fail, detail: "no app")])
    let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor)
    #expect(found.rows[1].status == .fail && found.rows[2].status == .fail && found.rows[1].detail == found.rows[2].detail)
}

@Test func theReadCheckIsNotTakenForARolesWhenTheAuthorIsTheOrchestrator() {
    // the read check lists the orchestrator's profile, which is also the author's here; only the mint check is the author's
    let doctor = DoctorState.checks([read("o/r"), DoctorCheck(name: "your gh login can read o/r", status: .fail, repo: "o/r", profiles: ["bot-a"])])
    let found = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor)
    #expect(found.rows[1].status == .waiting)
}

@Test func theGoldenDoctorOutputOfTheFixtureShowsEachKindOfRowOnTheFixtureRepos() throws {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/doctor.json")
    let doctor = doctorState(from: ProcessOutcome(exitCode: 1, stdout: String(decoding: try Data(contentsOf: path), as: UTF8.self)))
    let fixture = Data(fixtureConfig.utf8)
    func found(_ repo: String) -> [RepoCheckRow.Status] {
        repoChecks(repo: repo, roles: repoRoles(json: fixture, repo: repo)?.rows ?? [], doctor: doctor).rows.map(\.status)
    }
    // the repo whose owner has no installed bot offers Use another identity on its failed sign check
    let api = repoChecks(repo: "acme/api", roles: repoRoles(json: fixture, repo: "acme/api")?.rows ?? [], doctor: doctor)
    #expect(api.rows.map(\.anotherIdentity) == [nil, nil, .reviewer, nil])
    #expect(found("acme/web") == [.ok, .ok, .ok, .ok])
    #expect(found("acme/api") == [.ok, .ok, .fail, .fail])
    #expect(found("acme/a-really-long-repository-name-for-the-sidebar") == [.fail, .ok, .ok, .waiting])
}

@Test func onlyAFailedSignCheckOffersAnotherIdentityForItsRole() {
    func offered(_ doctor: [DoctorCheck]) -> [AgentRole?] {
        repoChecks(repo: "o/r", roles: roles("o/r"), doctor: .checks(doctor)).rows.map(\.anotherIdentity)
    }
    #expect(offered([read("o/r"), mint("a", "o/r", ["bot-a"], .fail), mint("c", "o/r", ["bot-c"]), solve("o/r")]) == [nil, .author, nil, nil])
    #expect(offered([read("o/r"), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"], .fail), solve("o/r")]) == [nil, nil, .reviewer, nil])
    // a failed read or Solve check offers none, nor do ok, warn and waiting ones
    #expect(offered([read("o/r", .fail), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"], .warn), solve("o/r", .fail)]) == [nil, nil, nil, nil])
    #expect(offered([]) == [nil, nil, nil, nil])
}

@Test func activatingAnotherIdentityOpensThatRolesForm() throws {
    let doctor = DoctorState.checks([read("o/r"), mint("a", "o/r", ["bot-a"]), mint("c", "o/r", ["bot-c"], .fail), solve("o/r")])
    let rows = repoChecks(repo: "o/r", roles: roles("o/r"), doctor: doctor).rows
    var selection = RepoRoleSelection()
    selection.useAnotherIdentity(on: rows[1])  // an ok row opens nothing
    #expect(selection.editing == nil)
    selection.useAnotherIdentity(on: rows[2])
    #expect(selection.editing == .reviewer)
}
