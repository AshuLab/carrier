import Foundation
import Testing
@testable import CarrierCore

// `setWatchedRepos` and `editBehavior` and the engine's `config` capability (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6): each request is what its golden file says
// (written by `UPDATE_FIXTURES=1 pnpm test`, where Node's schema accepts it), it goes to the socket when the hello lists `config` and to `carrier config` (through a `ProcessRunner`) otherwise.

private let fixtures = testPaths().fixtures

private func golden(_ name: String) throws -> (request: [String: Any], reply: [String: Any]) {
    let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(name))) as? [String: Any])
    return (try #require(file["request"] as? [String: Any]), try #require(file["reply"] as? [String: Any]))
}

private func hello(_ capabilities: String) -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

private func object(_ data: Data) throws -> NSDictionary { try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary) }

/// What the Behavior page builds for the golden: a poll every 2.5 minutes, debug logs, the default window and limits except 8 reviews and no limit on the run time.
private func goldenBehavior() -> EngineConfig {
    var config = EngineConfig()
    config.pollIntervalMinutes = 2.5
    config.logLevel = "debug"
    config.maxReviews = 8
    config.maxExecutionHours = nil
    return config
}

private let goldenRepos = EngineConfigChange.watchedRepos(["acme/web", "AshuLab/carrier", "new/one"])

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

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
private func launcher(_ runner: FakeRunner) -> CarrierConfigLauncher { CarrierConfigLauncher(runner: runner) { launched } }

@Test func eachRequestTheAppBuildsEncodesAsItsGoldenSaysWithoutItsId() throws {
    for (name, change) in [("engine-set-watched-repos.json", goldenRepos), ("engine-edit-behavior.json", EngineConfigChange.behavior(goldenBehavior()))] {
        let (request, _) = try golden(name)
        #expect(try object(change.request) == request as NSDictionary, Comment(rawValue: name))
        // one line, which is what `carrier config` reads
        #expect(String(decoding: change.request, as: UTF8.self).filter { $0 == "\n" }.count == 1)
    }
}

@Test func theGoldenRepliesDecodeIntoWhatTheEngineDid() throws {
    for name in ["engine-set-watched-repos.json", "engine-edit-behavior.json"] {
        let data = try #require(try golden(name).reply["data"])
        let reply = try JSONDecoder().decode(EngineConfigReply.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(reply.engine == .applied && reply.outcome == .applied && reply.reason == nil)
    }
}

@Test func theThreeAnswersOfTheEngineAreWhatThePagesShowOfAReload() throws {
    func decode(_ json: String) throws -> EngineConfigReply { try JSONDecoder().decode(EngineConfigReply.self, from: Data(json.utf8)) }
    #expect(try decode(#"{"saved":{},"engine":"notRunning"}"#).outcome == .nobody)
    let refused = try decode(#"{"saved":{"repos":[]},"engine":"refused","reason":{"code":"config.problem","params":{"path":"repos[2]","problem":"notARepo"},"error":"repos.2.name: must be owner/name"}}"#)
    #expect(refused.outcome == .refused(Refusal(code: "config.problem", params: ["path": "repos[2]", "problem": "notARepo"], text: "repos.2.name: must be owner/name")))
}

@Test func theBehaviorValuesAreAllSentAndNodeTakesOutTheDefaults() throws {
    let changes = try #require(try object(EngineConfigChange.behavior(EngineConfig()).request)["changes"] as? NSDictionary)
    #expect(changes == ["pollIntervalMinutes": 5, "logLevel": "info", "finishedWindowDays": 15, "limits": ["maxConcurrentEpics": 3, "maxReviews": 5, "maxExecutionRetries": 3, "maxExecutionHours": 4, "githubCallTimeoutSeconds": 30]] as NSDictionary)
    var config = EngineConfig()
    config.pollIntervalMinutes = .nan
    #expect(EngineConfigChange.behavior(config).fields == "")
}

@Test func theSocketGetsTheGoldenRequestWithAnIdWhenTheHelloListsConfig() async throws {
    let (request, reply) = try golden("engine-set-watched-repos.json")
    let asked = Asked()
    let server = TestServer { connection in
        connection.send(hello("\"reload\",\"config\""))
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        asked.add(line)
        var answer = reply
        answer["id"] = id
        connection.send(String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self) + "\n")
    }
    defer { server.stop() }
    let runner = FakeRunner(.success(ProcessResult(output: "", status: 0)))
    let answer = try await EngineConfigSender(socketPath: { server.path }, launcher: launcher(runner)).send(goldenRepos)
    let line = try #require(asked.all.first)
    var sent = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(sent.removeValue(forKey: "id") != nil)
    #expect(sent as NSDictionary == request as NSDictionary)
    #expect(answer.outcome == .applied && runner.ran.isEmpty)
}

@Test func anEngineThatDoesNotListConfigIsNotSentTheRequestAndCarrierConfigGetsItOnStandardInput() async throws {
    let (request, reply) = try golden("engine-edit-behavior.json")
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"reload\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    let output = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self) + "\n"
    let runner = FakeRunner(.success(ProcessResult(output: output, status: 0)))
    let answer = try await EngineConfigSender(socketPath: { older.path }, launcher: launcher(runner)).send(.behavior(goldenBehavior()))
    #expect(asked == false && answer.outcome == .applied)
    let command = try #require(runner.ran.first)
    #expect(runner.ran.count == 1 && command.program == launched.program && command.arguments == ["config"] && command.environment == launched.environment)
    let input = try #require(command.input)
    #expect(try object(input) == request as NSDictionary)
}

@Test func withNoEngineRunningCarrierConfigGetsTheRequestAndItsNotRunningIsNobodyToAsk() async throws {
    let runner = FakeRunner(.success(ProcessResult(output: "{\"ok\":true,\"data\":{\"saved\":{\"repos\":[]},\"engine\":\"notRunning\"}}\n", status: 0)))
    let sender = EngineConfigSender(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }, launcher: launcher(runner))
    let answer = try await sender.send(.watchedRepos([]))
    #expect(answer.outcome == .nobody && runner.ran.count == 1)
}

@Test func aRefusalOfTheSocketOrOfCarrierConfigKeepsItsCodeAndTheKeyPathAndKind() async throws {
    let words = "nope must be owner/name"
    let refusal = Refusal(code: "config.problem", params: ["path": "repos[1]", "problem": "notARepo"], text: words)
    let server = TestServer { connection in
        connection.send(hello("\"config\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"\(words)\",\"code\":\"config.problem\",\"params\":{\"path\":\"repos[1]\",\"problem\":\"notARepo\"}}\n")
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(refusal)) { _ = try await EngineConfigSender(socketPath: { server.path }).send(.watchedRepos(["a/b", "nope"])) }
    let printed = "{\"ok\":false,\"error\":\"\(words)\",\"code\":\"config.problem\",\"params\":{\"path\":\"repos[1]\",\"problem\":\"notARepo\"}}\n"
    let none = { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }
    await #expect(throws: ControlError.remote(refusal)) {
        _ = try await EngineConfigSender(socketPath: none, launcher: launcher(FakeRunner(.success(ProcessResult(output: printed, status: 1))))).send(.watchedRepos(["a/b", "nope"]))
    }
    // no carrier to run, a program that could not start, and a sender with no way to run `carrier`
    await #expect(throws: ControlError.remote(.configNotRun)) { _ = try await EngineConfigSender(socketPath: none).send(.watchedRepos([])) }
    await #expect(throws: ControlError.remote(.configNotRun)) {
        _ = try await EngineConfigSender(socketPath: none, launcher: launcher(FakeRunner(.failure(CocoaError(.fileNoSuchFile))))).send(.watchedRepos([]))
    }
}

@MainActor @Test func aSaveKeepsWhatTheEngineAnsweredAndSaysWhyItWasRefused() async {
    let status = ReloadStatus(reload: { .nobody })
    let engine = FakeEngineConfig()
    engine.reply = EngineConfigReply(engine: .notRunning)
    #expect(await saveEngineConfig(.behavior(EngineConfig()), send: engine.send, status: status) == .saved)
    #expect(status.outcome == .nobody && engine.sent == [.behavior(EngineConfig())])
    engine.failure = ControlError.remote(Refusal(code: "config.problem", params: ["path": "limits.maxReviews", "problem": "tooSmall"], text: "Must be 1 or more"))
    #expect(await saveEngineConfig(.behavior(EngineConfig()), send: engine.send, status: status) == .refused("Must be 1 or more"))
    engine.failure = ControlError.timeout
    #expect(await saveEngineConfig(.behavior(EngineConfig()), send: engine.send, status: status).problem != nil)
    #expect(status.outcome == .nobody)
}
