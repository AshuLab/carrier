import Foundation
import Testing
@testable import CarrierCore

// The engine's setup in the Health tab: the doctor's JSON, what a process that went wrong comes to, and when the store runs it.

private let sample = #"[{"name":"config","status":"ok"},{"name":"gh","status":"warn","detail":"old","fix":"brew upgrade gh"},{"name":"labels","status":"fail","detail":"missing","fix":"carrier init"}]"#

@Test func theDoctorsJSONDecodesIntoItsChecksWhateverTheExitCode() {
    let expected = DoctorState.checks([
        .init(name: "config", status: .ok), .init(name: "gh", status: .warn, detail: "old", fix: "brew upgrade gh"),
        .init(name: "labels", status: .fail, detail: "missing", fix: "carrier init"),
    ])
    #expect(doctorState(from: ProcessOutcome(exitCode: 1, stdout: sample)) == expected)
    #expect(doctorState(from: ProcessOutcome(exitCode: 0, stdout: sample + "\n")) == expected)
}

@Test func aDoctorThatDoesNotAnswerIsUnknownWithTheReasonAndNeverAPass() {
    let outcomes = [
        ProcessOutcome(startError: "no such file"), ProcessOutcome(timedOut: true), ProcessOutcome(exitCode: 2, stdout: "Error: no config"),
        ProcessOutcome(exitCode: 0, stdout: ""), ProcessOutcome(exitCode: 0, stdout: "[]"),
        ProcessOutcome(exitCode: 0, stdout: #"[{"name":"x","status":"great"}]"#),
    ]
    for outcome in outcomes {
        guard case .unknown(let reason) = doctorState(from: outcome) else { Issue.record("not unknown: \(outcome)"); continue }
        #expect(reason.hasPrefix("carrier doctor"))
    }
    #expect(doctorState(from: ProcessOutcome(startError: "no such file")) == .unknown("carrier doctor could not start: no such file"))
}

@Test func theCommandRunsTheDoctorOnTheConfigOfTheCarrierFolder() throws {
    let settings = SetupSettings(carrier: "/opt/carrier.mjs", node: "/usr/bin/node", path: "/usr/bin")
    let command = try #require(doctorCommand(settings: settings, environment: ["CARRIER_HOME": "/tmp/folder"], home: "/Users/x"))
    #expect(command.node == "/usr/bin/node")
    #expect(command.arguments == ["/opt/carrier.mjs", "doctor", "--config", "/tmp/folder/config.json", "--json"])
    #expect(command.environment["CARRIER_HOME"] == "/tmp/folder")
    #expect(doctorCommand(settings: SetupSettings(), environment: [:]) == nil)
}

private let settings = SetupSettings(carrier: "/opt/carrier.mjs", node: "/usr/bin/node", path: "/usr/bin")

private actor Runs {
    var count = 0
    func add() { count += 1 }
}

@MainActor @Test func theStoreRunsTheDoctorOnlyWithAConfigAndOnceAtATime() async {
    let runs = Runs()
    let store = DoctorStore { _ in
        await runs.add()
        try? await Task.sleep(for: .milliseconds(50))
        return ProcessOutcome(exitCode: 0, stdout: sample)
    }
    await store.check(settings: settings, environment: [:], configExists: false)
    let none = await runs.count
    #expect(store.state == .idle && none == 0)

    async let first: Void = store.check(settings: settings, environment: [:], configExists: true)
    try? await Task.sleep(for: .milliseconds(10))
    #expect(store.state == .running)
    await store.check(settings: settings, environment: [:], configExists: true)
    await first
    let once = await runs.count
    #expect(once == 1)
    if case .checks(let checks) = store.state { #expect(checks.count == 3) } else { Issue.record("no checks") }

    await store.check(settings: settings, environment: [:], configExists: true)
    let twice = await runs.count
    #expect(twice == 2)
}

@MainActor @Test func aStoreWithoutNodeOrCarrierSaysSoAndRunsNothing() async {
    let store = DoctorStore { _ in
        Issue.record("ran")
        return ProcessOutcome()
    }
    await store.check(settings: SetupSettings(), environment: [:], configExists: true)
    guard case .unknown = store.state else { Issue.record("not unknown"); return }
}
