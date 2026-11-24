import Foundation
import Testing
@testable import CarrierCore

// Starting Carrier through `ProcessRunner`: what the model asks the platform for and what it makes of the answer, with a fake runner and a fake socket.

private struct Scratch {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("launcher-\(UUID().uuidString)")
    var config: String { folder.appendingPathComponent("engine.json").path }

    init(config: Bool = true) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if config { try Data("{}".utf8).write(to: URL(fileURLWithPath: self.config)) }
    }

    func command(path: String = "/usr/bin") -> StartCommand {
        StartCommand(
            program: "/opt/carrier", arguments: ["start"], environment: ["PATH": path], processDir: folder.appendingPathComponent("engine").path,
            logPath: folder.appendingPathComponent("engine/logs/app-start.log").path, socketPath: folder.appendingPathComponent("control.sock").path)
    }
}

private final class FakeSocket: HostSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var open: Bool
    private(set) var asked: [String] = []
    init(open: Bool) { self.open = open }
    func open(_ now: Bool) { lock.withLock { open = now } }
    func answers(at path: String) -> Bool { lock.withLock { asked.append(path); return open } }
    func hello(at path: String) -> HostHello { .nobody }
}

private func launcher(_ runner: FakeProcessRunner, _ socket: FakeSocket) -> CarrierLauncher {
    CarrierLauncher(runner: runner, socket: socket, poll: .milliseconds(1))
}

private final class Kept: @unchecked Sendable { var settings = SetupSettings(node: "/n/node", path: "/old") }

private func retry(_ kept: Kept, scratch: Scratch) -> StartRetry {
    StartRetry(settings: { kept.settings }, command: { scratch.command(path: $0.path) }, save: { kept.settings = $0 })
}

@Test func aStartDoesNotBeginWithoutEngineJsonOrWithoutACommand() async throws {
    let missing = try Scratch(config: false)
    let runner = FakeProcessRunner(spawns: [.init(exitCode: nil)])
    let start = CarrierStart(launcher: launcher(runner, FakeSocket(open: true)), configPath: { missing.config })
    #expect(await start.start(missing.command()) == .notStarted)
    let present = try Scratch()
    let other = CarrierStart(launcher: launcher(runner, FakeSocket(open: true)), configPath: { present.config })
    #expect(await other.start(nil) == .notStarted)
    #expect(runner.spawned.isEmpty)
}

@Test func aStartWhileAnotherIsUnderWayDoesNothingAndTheFirstGoesOn() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: nil)])
    let socket = FakeSocket(open: false)
    let start = CarrierStart(launcher: launcher(runner, socket), configPath: { scratch.config })
    let first = Task { await start.start(scratch.command()) }
    while runner.spawned.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
    #expect(start.starting)
    #expect(await start.start(scratch.command()) == .notStarted)
    socket.open(true)
    #expect(await first.value == .up)
    #expect(runner.spawned.count == 1 && start.starting == false)
}

@Test func aStartSpawnsTheCommandAndGoesUpWhenTheSocketAnswers() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: nil)])
    let socket = FakeSocket(open: true)
    let result = await launcher(runner, socket).launch(scratch.command())
    #expect(result == nil)
    let spawn = try #require(runner.spawned.first)
    #expect(spawn.command == ProcessCommand(program: "/opt/carrier", arguments: ["start"], environment: ["PATH": "/usr/bin"]) && spawn.log == scratch.command().logPath)
    #expect(socket.asked == [scratch.command().socketPath])
    var isFolder: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: scratch.command().logsDir, isDirectory: &isFolder) && isFolder.boolValue)
}

@Test func anExitBeforeTheSocketOpensIsAFailureWithTheEndOfTheLog() async throws {
    let scratch = try Scratch()
    let log = (1...40).map { "line \($0)" }.joined(separator: "\n")
    let runner = FakeProcessRunner(spawns: [.init(exitCode: 3, log: log)])
    let failure = try #require(await launcher(runner, FakeSocket(open: false)).launch(scratch.command()))
    #expect(failure.reason == "Carrier exited with code 3 before it opened its control socket.")
    #expect(failure.tail.hasPrefix("line 11") && failure.tail.hasSuffix("line 40"))
    #expect(runner.shellAsked == 0)
}

@Test func aSocketThatAnswersWinsOverAnExit() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: 0)])
    #expect(await launcher(runner, FakeSocket(open: true)).launch(scratch.command()) == nil)
}

@Test func aProgramThatCannotBeStartedIsAFailure() async throws {
    struct Refused: Error {}
    final class Refusing: ProcessRunner, @unchecked Sendable {
        func run(_ command: ProcessCommand) async throws -> ProcessResult { throw Refused() }
        func spawnDetached(_ command: ProcessCommand, log: String) throws -> any SpawnedProcess { throw Refused() }
        func detectShell() async -> Detection? { nil }
    }
    let scratch = try Scratch()
    let failure = try #require(await CarrierLauncher(runner: Refusing(), socket: FakeSocket(open: false), poll: .milliseconds(1)).launch(scratch.command(), name: "The chat host"))
    #expect(failure.reason.hasPrefix("The chat host could not be started:") && failure.tail == "(the start log is empty)")
}

@Test func aMissingToolAsksTheShellAgainAndStartsOnceMoreWithTheCommandItMakes() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(
        spawns: [.init(exitCode: 1, log: "Error: spawn agent-forge ENOENT"), .init(exitCode: nil)], detection: Detection(node: nil, path: "/new"))
    let socket = FakeSocket(open: false)
    let kept = Kept()
    // the second spawn is the one that comes up
    let attempt = Task { await launcher(runner, socket).launch(scratch.command(path: "/old"), retry: retry(kept, scratch: scratch)) }
    while runner.spawned.count < 2 { try await Task.sleep(for: .milliseconds(1)) }
    socket.open(true)
    #expect(await attempt.value == nil)
    #expect(runner.shellAsked == 1 && runner.spawned[1].command.environment == ["PATH": "/new"])
    #expect(kept.settings == SetupSettings(node: "/n/node", path: "/new"))
}

@Test func aMissingToolIsNotTriedAgainWhenTheShellGivesTheSameCommand() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: 1, log: "spawn agent-forge ENOENT")], detection: Detection(node: nil, path: "/old"))
    let failure = try #require(await launcher(runner, FakeSocket(open: false)).launch(scratch.command(path: "/old"), retry: retry(Kept(), scratch: scratch)))
    #expect(runner.spawned.count == 1 && runner.shellAsked == 1)
    #expect(failure.reason.hasSuffix("agent-forge is not on the PATH of your shell either, which was read again just now. Install it, or add its folder to the PATH of your shell, and start again."))
}

@Test func aMissingToolWithAShellThatDoesNotAnswerSaysSoAndStartsNothingMore() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: 1, log: "spawn agent-forge ENOENT")], detection: nil)
    let failure = try #require(await launcher(runner, FakeSocket(open: false)).launch(scratch.command(), retry: retry(Kept(), scratch: scratch)))
    #expect(runner.spawned.count == 1 && failure.reason.hasSuffix(toolNotFoundText("agent-forge", shellAnswered: false)))
}

@Test func aMissingToolIsNotRetriedWithoutAWayToBuildAnotherCommand() async throws {
    let scratch = try Scratch()
    let runner = FakeProcessRunner(spawns: [.init(exitCode: 1, log: "spawn agent-forge ENOENT")], detection: Detection(path: "/new"))
    let failure = await launcher(runner, FakeSocket(open: false)).launch(scratch.command(), name: "The chat host")
    #expect(failure?.reason == "The chat host exited with code 1 before it opened its control socket." && runner.shellAsked == 0 && runner.spawned.count == 1)
}
