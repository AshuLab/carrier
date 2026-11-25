import Foundation
import Testing
@testable import CarrierCore

// The engine's setup in the Health tab: the doctor's JSON, what a process that went wrong comes to, and when the store runs it.

/// `doctorState` in English: the words it builds when the doctor cannot answer.
private func state(_ outcome: ProcessOutcome) -> DoctorState { doctorState(from: outcome, bundle: english.bundle, locale: english.locale) }

private let sample = #"[{"name":"config","status":"ok"},{"name":"gh","status":"warn","detail":"old","fix":"brew upgrade gh"},{"name":"labels","status":"fail","detail":"missing","fix":"carrier init"}]"#

@Test func theDoctorsJSONDecodesIntoItsChecksWhateverTheExitCode() {
    let expected = DoctorState.checks([
        .init(name: "config", status: .ok), .init(name: "gh", status: .warn, detail: "old", fix: "brew upgrade gh"),
        .init(name: "labels", status: .fail, detail: "missing", fix: "carrier init"),
    ])
    #expect(state(ProcessOutcome(exitCode: 1, stdout: sample)) == expected)
    #expect(state(ProcessOutcome(exitCode: 0, stdout: sample + "\n")) == expected)
}

@Test func theNewFieldsOfARepoCheckDecodeAndAnOutputWithoutThemStillDoes() {
    let with = #"[{"name":"forge agent a can mint a token for o/r","status":"fail","detail":"x","repo":"o/r","profiles":["a","b"]}]"#
    #expect(state(ProcessOutcome(exitCode: 1, stdout: with)) == .checks([
        .init(name: "forge agent a can mint a token for o/r", status: .fail, detail: "x", repo: "o/r", profiles: ["a", "b"]),
    ]))
    // `sample` is an older doctor's output: no `repo`, no `profiles`
    guard case .checks(let old) = state(ProcessOutcome(exitCode: 0, stdout: sample)) else { Issue.record("not checks"); return }
    #expect(old.allSatisfy { $0.repo == nil && $0.profiles == nil })
}

@Test func aDoctorThatDoesNotAnswerIsUnknownWithTheReasonAndNeverAPass() {
    let outcomes = [
        ProcessOutcome(startError: "no such file"), ProcessOutcome(timedOut: true), ProcessOutcome(exitCode: 2, stdout: "Error: no config"),
        ProcessOutcome(exitCode: 0, stdout: ""), ProcessOutcome(exitCode: 0, stdout: "[]"),
        ProcessOutcome(exitCode: 0, stdout: #"[{"name":"x","status":"great"}]"#),
    ]
    for outcome in outcomes {
        guard case .unknown(let reason) = state(outcome) else { Issue.record("not unknown: \(outcome)"); continue }
        #expect(reason.hasPrefix("carrier doctor"))
    }
    #expect(state(ProcessOutcome(startError: "no such file")) == .unknown("carrier doctor could not start: no such file"))
}

@Test func aConfigTheEngineRefusesComesBackWithTheDoctorsReason() {
    let stderr = "[12:00:00] info doctor starting\nInvalid config /tmp/engine.json:\n  repos.0.agents.reviewer.effort: Invalid option: expected one of \"low\"\n"
    #expect(state(ProcessOutcome(exitCode: 1, stdout: "", stderr: stderr)) == .refused(
        "Invalid config /tmp/engine.json:\n  repos.0.agents.reviewer.effort: Invalid option: expected one of \"low\""
    ))
    // the checks win over the noise on stderr
    #expect(state(ProcessOutcome(exitCode: 1, stdout: sample, stderr: "Invalid x")) != .refused("Invalid x"))
    let checks = repoChecks(repo: "o/r", roles: [], doctor: .refused("Invalid config: boom"))
    #expect(checks.note == "Carrier refuses the config: Invalid config: boom")
}

@Test func theCommandRunsTheDoctorOnTheConfigOfTheCarrierFolder() throws {
    let settings = SetupSettings(node: "/usr/bin/node", path: "/usr/bin")
    let command = try #require(doctorCommand(settings: settings, carrier: "/opt/carrier.js", environment: ["CARRIER_HOME": "/tmp/folder"], home: "/Users/x"))
    #expect(command.program == "/usr/bin/node")
    #expect(command.arguments == ["/opt/carrier.js", "doctor", "--config", "/tmp/folder/engine.json", "--json"])
    #expect(command.environment["CARRIER_HOME"] == "/tmp/folder")
    let binary = try #require(doctorCommand(settings: settings, carrier: "/opt/homebrew/bin/carrier", environment: [:], home: "/Users/x"))
    #expect(binary.program == "/opt/homebrew/bin/carrier")
    #expect(binary.arguments == ["doctor", "--config", "/Users/x/.carrier/engine.json", "--json"])
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
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: false, bundle: english.bundle, locale: english.locale)
    let none = await runs.count
    #expect(store.state == .idle && none == 0)

    async let first: Void = store.check(settings: settings, carrier: carrier, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
    try? await Task.sleep(for: .milliseconds(10))
    #expect(store.state == .running)
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
    await first
    let once = await runs.count
    #expect(once == 1)
    if case .checks(let checks) = store.state { #expect(checks.count == 3) } else { Issue.record("no checks") }

    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
    let twice = await runs.count
    #expect(twice == 2)
}

@MainActor @Test func aStoreWithoutCarrierSaysSoAndRunsNothing() async {
    let store = DoctorStore { _ in
        Issue.record("ran")
        return ProcessOutcome()
    }
    await store.check(settings: SetupSettings(), carrier: nil, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
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
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
    #expect(await runs.count == 1)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await runs.count == 1)
    await store.check(settings: settings, carrier: carrier, environment: [:], configExists: true, bundle: english.bundle, locale: english.locale)
    #expect(await runs.count == 2)
}

@Test func aDoctorThatDoesNotAnswerSaysWhyInSpanish() {
    func reason(_ outcome: ProcessOutcome) -> DoctorState { doctorState(from: outcome, bundle: spanish.bundle, locale: spanish.locale) }
    #expect(reason(ProcessOutcome(startError: "no such file")) == .unknown("carrier doctor no pudo iniciarse: no such file"))
    #expect(reason(ProcessOutcome(timedOut: true)) == .unknown("carrier doctor no terminó en 90 segundos y se detuvo"))
    #expect(reason(ProcessOutcome(exitCode: 2, stdout: "Error: no config")) == .unknown("carrier doctor imprimió algo que no son sus comprobaciones (salida 2)"))
    #expect(reason(ProcessOutcome(exitCode: 0, stdout: "[]")) == .unknown("carrier doctor no imprimió comprobaciones (salida 0)"))
    #expect(reason(ProcessOutcome(stdout: "")) == .unknown("carrier doctor imprimió algo que no son sus comprobaciones"))
}

@Test func aDoctorThatDoesNotAnswerSaysWhyInEnglishWithAndWithoutItsExitCode() {
    #expect(state(ProcessOutcome(exitCode: 2, stdout: "Error: no config")) == .unknown("carrier doctor printed something that is not its checks (exit 2)"))
    #expect(state(ProcessOutcome(stdout: "")) == .unknown("carrier doctor printed something that is not its checks"))
    #expect(state(ProcessOutcome(exitCode: 0, stdout: "[]")) == .unknown("carrier doctor printed no checks (exit 0)"))
}
