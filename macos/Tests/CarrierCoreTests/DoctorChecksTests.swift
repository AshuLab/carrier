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

@Test func theNewFieldsOfARepoCheckDecodeAndAnOutputWithoutThemStillDoes() {
    let with = #"[{"name":"forge agent a can mint a token for o/r","status":"fail","detail":"x","repo":"o/r","profiles":["a","b"]}]"#
    #expect(doctorState(from: ProcessOutcome(exitCode: 1, stdout: with)) == .checks([
        .init(name: "forge agent a can mint a token for o/r", status: .fail, detail: "x", repo: "o/r", profiles: ["a", "b"]),
    ]))
    // `sample` is an older doctor's output: no `repo`, no `profiles`
    guard case .checks(let old) = doctorState(from: ProcessOutcome(exitCode: 0, stdout: sample)) else { Issue.record("not checks"); return }
    #expect(old.allSatisfy { $0.repo == nil && $0.profiles == nil })
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
    let settings = SetupSettings(node: "/usr/bin/node", path: "/usr/bin")
    let command = try #require(doctorCommand(settings: settings, carrier: "/opt/carrier.js", environment: ["CARRIER_HOME": "/tmp/folder"], home: "/Users/x"))
    #expect(command.program == "/usr/bin/node")
    #expect(command.arguments == ["/opt/carrier.js", "doctor", "--config", "/tmp/folder/config.json", "--json"])
    #expect(command.environment["CARRIER_HOME"] == "/tmp/folder")
    let binary = try #require(doctorCommand(settings: settings, carrier: "/opt/homebrew/bin/carrier", environment: [:], home: "/Users/x"))
    #expect(binary.program == "/opt/homebrew/bin/carrier")
    #expect(binary.arguments == ["doctor", "--config", "/Users/x/.carrier/config.json", "--json"])
    #expect(doctorCommand(settings: SetupSettings(), carrier: nil, environment: [:]) == nil)
}

private let settings = SetupSettings(node: "/usr/bin/node", path: "/usr/bin")
private let carrier: String? = "/opt/carrier.js"

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
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: false)
    let none = await runs.count
    #expect(store.state == .idle && none == 0)

    async let first: Void = store.check(settings: settings, carrier: carrier, environment: [:], configExists: true)
    try? await Task.sleep(for: .milliseconds(10))
    #expect(store.state == .running)
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true)
    await first
    let once = await runs.count
    #expect(once == 1)
    if case .checks(let checks) = store.state { #expect(checks.count == 3) } else { Issue.record("no checks") }

    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true)
    let twice = await runs.count
    #expect(twice == 2)
}

@MainActor @Test func aStoreWithoutCarrierSaysSoAndRunsNothing() async {
    let store = DoctorStore { _ in
        Issue.record("ran")
        return ProcessOutcome()
    }
    await store.check(settings: SetupSettings(), carrier: nil, environment: [:], configExists: true)
    guard case .unknown = store.state else { Issue.record("not unknown"); return }
}

@MainActor @Test func theDoctorRunsOnlyWhenAskedForOnOpeningThePageAndOnCheckAgain() async {
    let runs = Runs()
    let store = DoctorStore { _ in
        await runs.add()
        return ProcessOutcome(exitCode: 0, stdout: sample)
    }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await runs.count == 0 && store.state == .idle)
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true)
    #expect(await runs.count == 1)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await runs.count == 1)
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true)
    #expect(await runs.count == 2)
}
