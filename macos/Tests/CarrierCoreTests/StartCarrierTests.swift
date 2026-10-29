import Foundation
import Testing
@testable import CarrierCore

private let complete = SetupSettings(
    carrier: "/n/bin/carrier", node: "/n/bin/node", path: "/usr/bin:/n/bin:/bin"
)

@Test func theCommandLineIsNodeAndCarrierWithNoConfig() throws {
    let command = try #require(startCommand(settings: complete, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.node == "/n/bin/node")
    #expect(command.arguments == ["/n/bin/carrier"])
}

@Test func theEnvironmentCarriesTheCarrierFolder() throws {
    let home = try #require(startCommand(settings: complete, environment: [:], home: "/h"))
    #expect(home.environment["CARRIER_HOME"] == "/h/.carrier")
    let scratch = try #require(startCommand(settings: complete, environment: ["CARRIER_HOME": "/scratch"], home: "/h"))
    #expect(scratch.environment["CARRIER_HOME"] == "/scratch")
    #expect(scratch.logPath == "/scratch/engine/logs/app-start.log")
    #expect(scratch.socketPath == "/scratch/engine/state/control.sock")
}

@Test func theEnvironmentGetsTheEnginePathAndKeepsTheRest() throws {
    let command = try #require(startCommand(settings: complete, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    // node's directory first, then the rest of the detected one without repeating it
    #expect(command.environment["PATH"] == "/n/bin:/usr/bin:/bin")
    #expect(command.environment["HOME"] == "/h")
}

@Test func theLogAndTheSocketLiveUnderTheEnginesFolder() throws {
    let command = try #require(startCommand(settings: complete, environment: [:], home: "/h"))
    #expect(command.orchestratorDir == "/h/.carrier/engine")
    #expect(command.logsDir == "/h/.carrier/engine/logs")
    #expect(command.logPath == "/h/.carrier/engine/logs/app-start.log")
    #expect(command.socketPath == "/h/.carrier/engine/state/control.sock")
}

@Test func withoutNodeOrCarrierThereIsNoCommandAndTheMissingOnesAreNamed() {
    var settings = complete
    settings.node = ""
    #expect(startMissing(settings) == ["node"])
    #expect(startCommand(settings: settings, environment: [:], home: "/h") == nil)
    settings.carrier = ""
    #expect(startMissing(settings) == ["node", "carrier"])
    #expect(startMissing(complete).isEmpty)
}

@Test func theSocketAnsweringMeansRunning() {
    #expect(startOutcome(exitCode: nil, socketAnswered: true, elapsed: 2) == .running)
}

@Test func theSocketAnsweringWhileTheProcessIsStillRunningIsRunningNotAWaitForTheTimeout() {
    #expect(startOutcome(exitCode: nil, socketAnswered: true, elapsed: 14.9) == .running)
}

@Test func theSocketAnsweringAfterTheProcessExitedIsRunningBecauseAnotherCarrierCameUp() {
    // started elsewhere in the meantime: ours quit because the folder was taken, the one that holds it answers
    #expect(startOutcome(exitCode: 1, socketAnswered: true, elapsed: 1) == .running)
}

@Test func anExitBeforeTheSocketFailsWithItsCode() {
    #expect(startOutcome(exitCode: 1, socketAnswered: false, elapsed: 0.3) == .failed(.exited(1)))
    #expect(startOutcome(exitCode: 137, socketAnswered: false, elapsed: 9) == .failed(.exited(137)))
}

@Test func anExitWithCodeZeroBeforeTheSocketStillFails() {
    #expect(startOutcome(exitCode: 0, socketAnswered: false, elapsed: 0.3) == .failed(.exited(0)))
}

@Test func fifteenSecondsWithoutTheSocketFailsWhileTheProcessRuns() {
    #expect(startOutcome(exitCode: nil, socketAnswered: false, elapsed: 15) == .failed(.noSocket))
    #expect(startOutcome(exitCode: nil, socketAnswered: false, elapsed: 40) == .failed(.noSocket))
}

@Test func beforeFifteenSecondsAProcessWithoutTheSocketKeepsWaiting() {
    #expect(startOutcome(exitCode: nil, socketAnswered: false, elapsed: 0) == nil)
    #expect(startOutcome(exitCode: nil, socketAnswered: false, elapsed: 14.9) == nil)
}

@Test func theFailureTextsSayWhatHappened() {
    #expect(startFailureText(.exited(0)).contains("code 0"))
    #expect(startFailureText(.noSocket).contains("15 seconds"))
}

@Test func theTailOfTheLogIsItsLastLinesAndAnErrorCarrierPrintedIsInIt() {
    let log = (1...50).map { "line \($0)" }.joined(separator: "\n") + "\nconfig invalid: github.token is required\n\n"
    #expect(logTail(Data(log.utf8), lines: 3) == "line 49\nline 50\nconfig invalid: github.token is required")
}

@Test func anEmptyLogSaysSo() {
    #expect(logTail(Data()) == "(the start log is empty)")
}

@Test func theMenuItemIsEnabledOnlyWhenStoppedAndConfiguredAndCompleteAndNotStarting() {
    func item(_ state: ConnectionState = .stopped, starting: Bool = false, missing: [String] = [], configExists: Bool = true) -> (title: String, enabled: Bool) {
        startMenuState(state: state, starting: starting, missing: missing, configExists: configExists)
    }
    #expect(item() == ("Start Carrier", true))
    #expect(item(starting: true).enabled == false)
    #expect(item(.incompatible).enabled == false)
    #expect(item(missing: ["node", "carrier"]) == ("Start Carrier (missing: node, carrier)", false))
    #expect(item(configExists: false) == ("Start Carrier (engine not configured)", false))
    #expect(item(missing: ["node"], configExists: false).enabled == false)
}

@Test func noConfigMeansANoticeWithNoActionAndItsAbsenceMeansNone() throws {
    let notice = try #require(engineNotConfiguredNotice(configExists: false))
    #expect(notice.contains("not configured"))
    #expect(engineNotConfiguredNotice(configExists: true) == nil)
}

@Test func openingTheAppStartsCarrierOnlyWhenEveryConditionHolds() throws {
    let running = ConnectionState.running(try decodeSnapshot(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json"))))
    func decide(enabled: Bool = true, first: ConnectionState = .stopped, ready: Bool = true, fixture: Bool = false, tried: Bool = false) -> Bool {
        shouldStartOnOpen(enabled: enabled, firstState: first, startReady: ready, fixture: fixture, alreadyTried: tried)
    }
    #expect(decide())
    #expect(decide(enabled: false) == false)
    #expect(decide(first: running) == false)
    #expect(decide(first: .incompatible) == false)
    #expect(decide(ready: false) == false)
    #expect(decide(fixture: true) == false)
    #expect(decide(tried: true) == false)
}
