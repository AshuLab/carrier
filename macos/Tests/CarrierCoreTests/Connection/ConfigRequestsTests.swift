import Foundation
import Testing
@testable import CarrierCore

// `editChatSettings` and the `config` capability (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6): the request is what the golden file says, it goes to the
// socket when the hello lists `config` and to `carrier config` (through a `ProcessRunner`) otherwise.

private let fixtures = testPaths().fixtures

private func hello(_ capabilities: String) -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

private func golden() throws -> (request: [String: Any], reply: [String: Any]) {
    let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("chat-edit-settings.json"))) as? [String: Any])
    let request = try #require(file["request"] as? [String: Any])
    let reply = try #require(file["reply"] as? [String: Any])
    return (request, reply)
}

/// What the golden request's changes are, as the Sessions page builds them: ages 7 and Never, a local start, and the default idle time (removed).
private let goldenChanges = ChatSettingChanges(
    ChatSettingChanges.ages(SessionAges(archive: .days(7), delete: .never)).values
        .merging(ChatSettingChanges.worktreeStart(.local).values) { $1 }.merging(ChatSettingChanges.idleClose(.tenMinutes).values) { $1 })

private func object(_ text: String) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

/// Answers each command with what it is given, and keeps what it was asked to run.
private final class FakeRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [ProcessCommand] = []
    private let result: Result<ProcessResult, Error>
    init(_ result: Result<ProcessResult, Error>) { self.result = result }
    var ran: [ProcessCommand] { lock.withLock { commands } }
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        lock.withLock { commands.append(command) }
        return try result.get()
    }
}

private let launched = ProcessCommand(program: "/usr/local/bin/carrier", arguments: ["config"], environment: ["CARRIER_HOME": "/scratch"], limit: 30)
private func launcher(_ runner: FakeRunner, command: ProcessCommand? = launched) -> CarrierConfigLauncher { CarrierConfigLauncher(runner: runner) { command } }

@Test func theSessionsPageBuildsItsChangesWithTheDefaultsRemoved() throws {
    #expect(ChatSettingChanges.ages(SessionAges()).values == ["archiveAfterDays": .remove, "deleteAfterDays": .remove])
    #expect(ChatSettingChanges.ages(SessionAges(archive: .never, delete: .days(40))).values == ["archiveAfterDays": .text("never"), "deleteAfterDays": .days(40)])
    #expect(ChatSettingChanges.worktreeStart(.remote).values == ["worktreeStart": .remove] && ChatSettingChanges.worktreeStart(.local).values == ["worktreeStart": .text("local")])
    #expect(ChatSettingChanges.idleClose(.tenMinutes).values == ["idleCloseMinutes": .remove] && ChatSettingChanges.idleClose(.oneHour).values == ["idleCloseMinutes": .days(60)])
    let wanted = try #require(try golden().request["changes"] as? NSDictionary)
    #expect(try object(goldenChanges.json) == wanted)
}

@Test func theRequestIsTheGoldenOneAndTheSocketGetsItWhenTheHelloListsConfig() async throws {
    let (request, reply) = try golden()
    let asked = Asked()
    let server = TestServer { connection in
        connection.send(hello("\"config\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        asked.add(line)
        var answer = reply
        answer["id"] = id
        connection.send(String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self) + "\n")
    }
    defer { server.stop() }
    let runner = FakeRunner(.success(ProcessResult(output: "", status: 0)))
    let saved = try await SocketChatHost(socketPath: { server.path }, configLauncher: launcher(runner)).editChatSettings(goldenChanges)
    let line = try #require(asked.all.first)
    var sent = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(sent.removeValue(forKey: "id") != nil)
    #expect(sent as NSDictionary == request as NSDictionary)
    #expect(saved.saved == ["archiveAfterDays": 7, "deleteAfterDays": "never", "worktreeStart": "local"])
    #expect(runner.ran.isEmpty)
}

@Test func aRefusalOfTheSocketKeepsItsCodeAndTheKeyPathAndKind() async throws {
    let server = TestServer { connection in
        connection.send(hello("\"config\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"idleCloseMinutes: must be 10, 30 or 60 (minutes)\",\"code\":\"config.problem\",\"params\":{\"path\":\"idleCloseMinutes\",\"problem\":\"invalid_union\"}}\n")
    }
    defer { server.stop() }
    let refusal = Refusal(code: "config.problem", params: ["path": "idleCloseMinutes", "problem": "invalid_union"], text: "idleCloseMinutes: must be 10, 30 or 60 (minutes)")
    await #expect(throws: ControlError.remote(refusal)) { _ = try await SocketChatHost(socketPath: { server.path }).editChatSettings(.idleClose(.oneHour)) }
}

@Test func aHostThatDoesNotListConfigIsNotSentTheRequestAndCarrierConfigGetsItOnStandardInput() async throws {
    let (request, reply) = try golden()
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"projects\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    let output = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self) + "\n"
    let runner = FakeRunner(.success(ProcessResult(output: output, status: 0)))
    let saved = try await SocketChatHost(socketPath: { older.path }, configLauncher: launcher(runner)).editChatSettings(goldenChanges)
    #expect(asked == false)
    let command = try #require(runner.ran.first)
    #expect(runner.ran.count == 1 && command.program == launched.program && command.arguments == ["config"] && command.environment == launched.environment)
    let input = try #require(command.input)
    #expect(String(decoding: input, as: UTF8.self).filter { $0 == "\n" }.count == 1)
    #expect(try object(String(decoding: input, as: UTF8.self)) == request as NSDictionary)
    #expect(saved.saved == ["archiveAfterDays": 7, "deleteAfterDays": "never", "worktreeStart": "local"])
}

@Test func withNoHostRunningCarrierConfigGetsTheRequestToo() async throws {
    let runner = FakeRunner(.success(ProcessResult(output: "{\"ok\":true,\"data\":{\"saved\":{\"worktreeStart\":\"local\"}}}\n", status: 0)))
    let saved = try await SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }, configLauncher: launcher(runner)).editChatSettings(.worktreeStart(.local))
    #expect(saved.saved == ["worktreeStart": "local"] && runner.ran.count == 1)
}

@Test func aRefusalOfCarrierConfigIsTheSameRefusalAndExitTwoOrAnythingElseIsNotRun() async throws {
    let refusal = "{\"ok\":false,\"error\":\"deleteAfterDays: must be greater than archiveAfterDays\",\"code\":\"config.problem\",\"params\":{\"path\":\"deleteAfterDays\",\"problem\":\"custom\"}}\n"
    func host(_ result: Result<ProcessResult, Error>, command: ProcessCommand? = launched) -> SocketChatHost {
        SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }, configLauncher: launcher(FakeRunner(result), command: command))
    }
    let words = "deleteAfterDays: must be greater than archiveAfterDays"
    await #expect(throws: ControlError.remote(Refusal(code: "config.problem", params: ["path": "deleteAfterDays", "problem": "custom"], text: words))) {
        _ = try await host(.success(ProcessResult(output: refusal, status: 1))).editChatSettings(.ages(SessionAges(archive: .days(30), delete: .days(10))))
    }
    // standard input that was not a request, a program that printed nothing, one that could not start, and no carrier to run
    await #expect(throws: ControlError.remote(Refusal(code: "request.invalid", text: "invalid request"))) {
        _ = try await host(.success(ProcessResult(output: "{\"ok\":false,\"error\":\"invalid request\",\"code\":\"request.invalid\"}\n", status: 2))).editChatSettings(.idleClose(.oneHour))
    }
    await #expect(throws: ControlError.remote(.configNotRun)) { _ = try await host(.success(ProcessResult(output: "", status: 0, timedOut: true))).editChatSettings(.idleClose(.oneHour)) }
    await #expect(throws: ControlError.remote(.configNotRun)) { _ = try await host(.failure(CocoaError(.fileNoSuchFile))).editChatSettings(.idleClose(.oneHour)) }
    await #expect(throws: ControlError.remote(.carrierNotFound)) { _ = try await host(.success(ProcessResult(output: "", status: 0)), command: nil).editChatSettings(.idleClose(.oneHour)) }
    await #expect(throws: ControlError.remote(.hostLacks("editChatSettings"))) {
        _ = try await SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }).editChatSettings(.idleClose(.oneHour))
    }
}

@Test func carrierConfigRunsTheWayCarrierStartsWithItsPathAndFolder() {
    let settings = SetupSettings(node: "/opt/node/bin/node", path: "/usr/bin")
    let binary = carrierConfigCommand(settings: settings, carrier: "/usr/local/bin/carrier", environment: ["HOME": "/Users/x", "CARRIER_HOME": "/scratch"])
    #expect(binary?.program == "/usr/local/bin/carrier" && binary?.arguments == ["config"] && binary?.environment["CARRIER_HOME"] == "/scratch")
    #expect(binary?.environment["PATH"] == enginePath(detected: "/usr/bin", node: "/opt/node/bin/node") && binary?.environment["HOME"] == "/Users/x")
    let script = carrierConfigCommand(settings: settings, carrier: "/src/main.ts", environment: [:], home: "/Users/x")
    #expect(script?.program == "/opt/node/bin/node" && script?.arguments == ["/src/main.ts", "config"] && script?.environment["CARRIER_HOME"] == "/Users/x/.carrier")
    #expect(carrierConfigCommand(settings: SetupSettings(), carrier: "/src/main.ts", environment: [:]) == nil)
    #expect(carrierConfigCommand(settings: settings, carrier: nil, environment: [:]) == nil)
}
