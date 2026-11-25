import Foundation
import Testing
@testable import CarrierCore

// The five requests that change `providers.json` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6): each is encoded as its golden file says, goes to the socket when
// the hello lists `config` and to `carrier config` (through a `ProcessRunner`) otherwise, and the reply says what the engine did with the file.

private let fixtures = testPaths().fixtures

private func hello(_ capabilities: String) -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

private func golden(_ name: String) throws -> (request: [String: Any], reply: [String: Any]) {
    let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("\(name).json"))) as? [String: Any])
    return (try #require(file["request"] as? [String: Any]), try #require(file["reply"] as? [String: Any]))
}

private var edited: AccountDraft {
    var draft = AccountDraft()
    draft.displayName = " Work "
    draft.icon = .bolt
    draft.configDir = "~/.claude-work"
    draft.autoCompact = "250000"
    draft.launchArgs = "--chrome\n"
    return draft
}

/// Each golden file, with the request as the Providers page builds it and what the engine's answer is in it.
let providersGoldenTable: [(golden: String, request: ProvidersRequest, outcome: ReloadOutcome)] = [
    ("chat-set-accounts", .setAccounts([DetectedAccount(name: "agy", harness: "agy")]), .nobody),
    ("chat-add-account", .addAccount(name: "claude-work", harness: "claude", configDir: "~/.claude-work"), .applied),
    ("chat-edit-account", .editAccount(name: "claude-work", draft: edited), .applied),
    ("chat-remove-account", .removeAccount(name: "spare"), .refused(Refusal(code: "config.problem", params: ["path": "agents.author.provider", "problem": "providerNotDeclared"], text: "agents.author.provider: the account \"spare\" is not declared"))),
    ("chat-set-text-generator", .setTextGenerator(TextGeneratorChoice(server: "ollama", model: "qwen3:8b")), .nobody),
]

private func object(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

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
    func spawnDetached(_ command: ProcessCommand, log: String) throws -> any SpawnedProcess { throw ControlError.closed }
    func detectShell() async -> Detection? { nil }
}

private let launched = ProcessCommand(program: "/usr/local/bin/carrier", arguments: ["config"], environment: ["CARRIER_HOME": "/scratch"], limit: 30)
private func launcher(_ runner: FakeRunner) -> CarrierConfigLauncher { CarrierConfigLauncher(runner: runner) { launched } }

@Test func eachRequestIsEncodedAsItsGoldenFileSays() throws {
    for row in providersGoldenTable {
        let (request, _) = try golden(row.golden)
        #expect(try object(row.request.line) == request as NSDictionary, Comment(rawValue: row.golden))
        // what `carrier config` reads: the same request, one line, no id
        let line = try object(row.request.request)
        #expect(row.request.request.filter { $0 == UInt8(ascii: "\n") }.count == 1 && line == request as NSDictionary)
        // what the socket's request carries after its cmd
        let socket = try object(Data("{\"id\":1,\"cmd\":\"\(row.request.command)\"\(row.request.fields)}".utf8))
        #expect(socket.allKeys.count == request.count + 1 && socket["cmd"] as? String == request["cmd"] as? String, Comment(rawValue: row.golden))
    }
}

@Test func theSocketGetsEachRequestWhenTheHelloListsConfigAndTheReplyTellsWhatTheEngineDid() async throws {
    for row in providersGoldenTable {
        let (request, reply) = try golden(row.golden)
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
        let saved = try await SocketChatHost(socketPath: { server.path }, configLauncher: launcher(runner)).changeProviders(row.request)
        let first = try #require(asked.all.first)
        var sent = try #require(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
        #expect(sent.removeValue(forKey: "id") != nil)
        #expect(sent as NSDictionary == request as NSDictionary, Comment(rawValue: row.golden))
        #expect(saved.outcome == row.outcome, Comment(rawValue: row.golden))
        #expect(runner.ran.isEmpty)
        server.stop()
    }
}

@Test func aHostThatDoesNotListConfigIsNotAskedAndCarrierConfigGetsTheRequestOnStandardInput() async throws {
    for row in providersGoldenTable {
        let (request, reply) = try golden(row.golden)
        var asked = false
        let older = TestServer { connection in
            connection.send(hello("\"projects\""))
            asked = connection.readRequestId() != nil
        }
        defer { older.stop() }
        let output = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self) + "\n"
        let runner = FakeRunner(.success(ProcessResult(output: output, status: 0)))
        let saved = try await SocketChatHost(socketPath: { older.path }, configLauncher: launcher(runner)).changeProviders(row.request)
        #expect(asked == false)
        let command = try #require(runner.ran.first)
        #expect(runner.ran.count == 1 && command.program == launched.program && command.arguments == ["config"] && command.environment == launched.environment)
        let input = try #require(command.input)
        #expect(try object(input) == request as NSDictionary, Comment(rawValue: row.golden))
        #expect(saved.outcome == row.outcome, Comment(rawValue: row.golden))
    }
}

@Test func withNoHostRunningCarrierConfigGetsAProvidersRequestToo() async throws {
    let runner = FakeRunner(.success(ProcessResult(output: "{\"ok\":true,\"data\":{\"saved\":{},\"engine\":\"notRunning\"}}\n", status: 0)))
    let saved = try await SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }, configLauncher: launcher(runner)).changeProviders(.removeAccount(name: "a"))
    #expect(saved.outcome == .nobody && runner.ran.count == 1)
}

@Test func aRefusalKeepsItsCodeItsParamsAndItsWordsOverTheSocketAndThroughCarrierConfig() async throws {
    let words = "claude is used by Author, Chat agent claude, so it stays. Point those at another account first."
    let refusal = Refusal(code: "account.inUse", params: ["name": "claude", "uses": "Author, Chat agent claude"], text: words)
    let server = TestServer { connection in
        connection.send(hello("\"config\""))
        guard let id = connection.readRequestId() else { return }
        connection.send("{\"id\":\(id),\"ok\":false,\"error\":\"\(words)\",\"code\":\"account.inUse\",\"params\":{\"name\":\"claude\",\"uses\":\"Author, Chat agent claude\"}}\n")
    }
    defer { server.stop() }
    await #expect(throws: ControlError.remote(refusal)) { _ = try await SocketChatHost(socketPath: { server.path }).changeProviders(.removeAccount(name: "claude")) }
    let printed = "{\"ok\":false,\"error\":\"\(words)\",\"code\":\"account.inUse\",\"params\":{\"name\":\"claude\",\"uses\":\"Author, Chat agent claude\"}}\n"
    let runner = FakeRunner(.success(ProcessResult(output: printed, status: 1)))
    await #expect(throws: ControlError.remote(refusal)) {
        _ = try await SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }, configLauncher: launcher(runner)).changeProviders(.removeAccount(name: "claude"))
    }
    // no carrier to run and no host: said in words, never written
    await #expect(throws: ControlError.remote(.hostLacks("removeAccount"))) {
        _ = try await SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }).changeProviders(.removeAccount(name: "claude"))
    }
}

@Test func whatTheEngineDidIsReadFromTheReply() throws {
    func saved(_ json: String) throws -> ProvidersSaved { try JSONDecoder().decode(ProvidersSaved.self, from: Data(json.utf8)) }
    #expect(try saved(#"{"saved":{},"engine":"applied"}"#).outcome == .applied)
    #expect(try saved(#"{"saved":{},"engine":"notRunning"}"#).outcome == .nobody)
    let kept = try saved(#"{"saved":{},"engine":"refused","engineReason":{"error":"repos.0: not a repository","code":"config.problem","params":{"path":"repos.0","problem":"notARepo"}}}"#).outcome
    #expect(kept == .refused(Refusal(code: "config.problem", params: ["path": "repos.0", "problem": "notARepo"], text: "repos.0: not a repository")))
    // an engine that was there and did not answer, a refusal that says nothing, and a word a newer host adds
    #expect(try saved(#"{"saved":{},"engine":"refused","engineReason":{"error":"The engine did not answer","code":"providers.engineNoAnswer","params":{}}}"#).outcome == .noAnswer)
    #expect(try saved(#"{"saved":{},"engine":"refused"}"#).outcome == .noAnswer)
    #expect(try saved(#"{"saved":{},"engine":"restarting"}"#).outcome == .unsupported)
    #expect(reloadWords(kept) == "Saved, but Carrier kept its settings: \(Copy.text("config.problem", ["path": "repos.0", "problem": "notARepo"]) ?? "")")
}
