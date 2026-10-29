import Foundation
import Testing
@testable import CarrierCore

private let complete = SetupSettings(
    carrier: "/n/bin/carrier", node: "/n/bin/node", path: "/usr/bin:/n/bin:/bin", configPath: "/h/.carrier/config.json"
)

@Test func theCommandLineIsNodeCarrierAndTheConfig() throws {
    let command = try #require(startCommand(settings: complete, engine: "/h/.carrier/engine", environment: ["HOME": "/h", "PATH": "/usr/bin"]))
    #expect(command.node == "/n/bin/node")
    #expect(command.arguments == ["/n/bin/carrier", "--config", "/h/.carrier/config.json"])
}

@Test func theEnvironmentGetsTheEnginePathAndKeepsTheRest() throws {
    let command = try #require(startCommand(settings: complete, engine: "/h/.carrier/engine", environment: ["HOME": "/h", "PATH": "/usr/bin"]))
    // node's directory first, then the rest of the detected one without repeating it
    #expect(command.environment["PATH"] == "/n/bin:/usr/bin:/bin")
    #expect(command.environment["HOME"] == "/h")
}

@Test func theLogAndTheSocketLiveUnderTheEnginesFolder() throws {
    let command = try #require(startCommand(settings: complete, engine: "/h/.carrier/engine", environment: [:]))
    #expect(command.orchestratorDir == "/h/.carrier/engine")
    #expect(command.logsDir == "/h/.carrier/engine/logs")
    #expect(command.logPath == "/h/.carrier/engine/logs/app-start.log")
    #expect(command.socketPath == "/h/.carrier/engine/state/control.sock")
}

@Test func withoutNodeCarrierOrAConfigPathThereIsNoCommandAndTheMissingOnesAreNamed() {
    var settings = complete
    settings.node = ""
    settings.configPath = ""
    #expect(startMissing(settings) == ["node", "config path"])
    #expect(startCommand(settings: settings, engine: "/h/.carrier/engine", environment: [:]) == nil)
    settings.carrier = ""
    #expect(startMissing(settings) == ["node", "carrier", "config path"])
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

@Test func theMenuItemIsEnabledOnlyWhenStoppedAndCompleteAndNotStarting() {
    #expect(startMenuState(state: .stopped, starting: false, missing: []) == ("Start Carrier", true))
    #expect(startMenuState(state: .stopped, starting: true, missing: []).enabled == false)
    #expect(startMenuState(state: .incompatible, starting: false, missing: []).enabled == false)
    #expect(startMenuState(state: .stopped, starting: false, missing: ["node", "config path"])
        == ("Start Carrier (missing: node, config path)", false))
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
