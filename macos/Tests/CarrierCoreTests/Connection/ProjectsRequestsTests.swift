import Foundation
import Testing
@testable import CarrierCore

// The nine requests that change `projects.json` and `projectsFolder` of `chat.json` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6): each is encoded as
// its golden says (`chat-edit-projects.json`, written by `src/chat/server.test.ts`), goes to the socket when the hello lists `config` and to `carrier config` otherwise.

private let goldenFile = testPaths().fixtures.appendingPathComponent("chat-edit-projects.json")
private let alpha = "/Users/example/work/alpha", alpha2 = "/Users/example/work/alpha-2", gamma = "/Users/example/work/gamma"

/// Each golden case, with the change the app builds for it.
private let changes: [(name: String, change: ProjectsChange)] = [
    ("addProject", .add(folder: gamma)),
    ("addProjectExisting", .add(folder: gamma + "/")),
    ("removeProject", .remove(path: "/Users/example/work/beta")),
    ("editProject", .edit(path: alpha, key: "name", value: .text("Alpha"))),
    ("moveProject", .move(path: alpha, folder: alpha2)),
    ("editProjectIcon", .editIcon(path: alpha2, changes: ["color": .remove, "mark": .text("bolt")])),
    ("editProjectDefaults", .editDefaults(path: alpha2, changes: ["model": .remove, "workIn": .text("worktree")])),
    ("editProjectTags", .editTags(path: alpha2, add: ["C", " d "], remove: ["a"])),
    ("setProjectActions", .setActions(path: alpha2, actions: [ProjectAction(name: "Install", command: "pnpm i", when: .newWorktree, onFail: .stop)])),
    ("setProjectsFolder", .setFolder("/Users/example/projects")),
    ("missing", .remove(path: "/Users/example/work/none")),
    ("refused", .edit(path: gamma, key: "name", value: .flag(true))),
]

private func golden(_ name: String) throws -> (request: [String: Any], reply: [String: Any]) {
    let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: goldenFile)) as? [String: [String: Any]])
    let entry = try #require(file[name])
    return (try #require(entry["request"] as? [String: Any]), try #require(entry["reply"] as? [String: Any]))
}

private func hello(_ capabilities: String) -> String {
    "{\"event\":\"hello\",\"protocol\":1,\"pid\":42,\"startedAt\":1000,\"version\":\"x\",\"capabilities\":[\(capabilities)]}\n"
}

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
    private let output: String
    private let status: Int32
    init(output: String, status: Int32) { (self.output, self.status) = (output, status) }
    var ran: [ProcessCommand] { lock.withLock { commands } }
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        lock.withLock { commands.append(command) }
        return ProcessResult(output: output, status: status)
    }
}

private let launched = ProcessCommand(program: "/usr/local/bin/carrier", arguments: ["config"], environment: ["CARRIER_HOME": "/scratch"], limit: 30)

/// Whether the reply of a golden case is a refusal, and what it says.
private func refusal(of reply: [String: Any]) -> Refusal? { reply["ok"] as? Bool == false ? Refusal.read(reply) : nil }

@Test(arguments: changes.map(\.name)) func eachRequestIsEncodedAsItsGoldenFileSays(name: String) throws {
    let change = try #require(changes.first { $0.name == name }?.change)
    let request = try golden(name).request
    var sent = change.body
    sent["cmd"] = change.cmd
    #expect(sent as NSDictionary == request as NSDictionary)
    // the line `carrier config` reads, and the fields the socket's request carries after its id
    let line = String(decoding: change.request, as: UTF8.self)
    #expect(line.filter { $0 == "\n" }.count == 1 && line.hasSuffix("\n"))
    #expect(try object(change.request) == request as NSDictionary)
    #expect(try object(Data("{\"id\":1,\"cmd\":\"\(change.cmd)\"\(change.fields)}".utf8)) == (request.merging(["id": 1]) { $1 }) as NSDictionary)
}

@Test(arguments: changes.map(\.name)) func theSocketGetsTheRequestWhenTheHelloListsConfigAndItsReplyOrRefusalIsRead(name: String) async throws {
    let change = try #require(changes.first { $0.name == name }?.change)
    let (request, reply) = try golden(name)
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
    let runner = FakeRunner(output: "", status: 0)
    let host = SocketChatHost(socketPath: { server.path }, configLauncher: CarrierConfigLauncher(runner: runner) { launched })
    if let refused = refusal(of: reply) {
        await #expect(throws: ControlError.remote(refused)) { _ = try await host.changeProjects(change) }
        #expect(refused.code != nil && refused.params["path"] != nil)
    } else {
        let changed = try await host.changeProjects(change)
        let data = try #require(reply["data"] as? [String: Any])
        #expect(changed.added == data["added"] as? Bool && changed.removed == data["removed"] as? String)
        let saved = data["saved"] as? [String: Any]
        #expect(changed.saved?.path == saved?["path"] as? String && changed.saved?.projectsFolder == saved?["projectsFolder"] as? String)
    }
    let line = try #require(asked.all.first)
    var sent = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(sent.removeValue(forKey: "id") != nil)
    #expect(sent as NSDictionary == request as NSDictionary)
    #expect(runner.ran.isEmpty)
}

@Test(arguments: changes.map(\.name)) func aHostThatDoesNotListConfigIsNotAskedAndCarrierConfigGetsTheRequestOnStandardInput(name: String) async throws {
    let change = try #require(changes.first { $0.name == name }?.change)
    let (request, reply) = try golden(name)
    var asked = false
    let older = TestServer { connection in
        connection.send(hello("\"projects\""))
        asked = connection.readRequestId() != nil
    }
    defer { older.stop() }
    let printed = String(decoding: try JSONSerialization.data(withJSONObject: reply.filter { $0.key != "id" }), as: UTF8.self) + "\n"
    let runner = FakeRunner(output: printed, status: refusal(of: reply) == nil ? 0 : 1)
    let host = SocketChatHost(socketPath: { older.path }, configLauncher: CarrierConfigLauncher(runner: runner) { launched })
    if let refused = refusal(of: reply) {
        await #expect(throws: ControlError.remote(refused)) { _ = try await host.changeProjects(change) }
    } else {
        let changed = try await host.changeProjects(change)
        #expect(changed.added == (reply["data"] as? [String: Any])?["added"] as? Bool)
    }
    #expect(asked == false)
    let command = try #require(runner.ran.first)
    #expect(runner.ran.count == 1 && command.program == launched.program && command.arguments == ["config"] && command.environment == launched.environment)
    let input = try #require(command.input)
    #expect(try object(input) == request as NSDictionary)
}

@Test func withNoHostAndNoCarrierToRunTheRequestIsRefusedAndNothingIsSent() async throws {
    let none = { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }
    await #expect(throws: ControlError.remote(.hostLacks("addProject"))) { _ = try await SocketChatHost(socketPath: none).changeProjects(.add(folder: "/a")) }
    await #expect(throws: ControlError.remote(.carrierNotFound)) {
        _ = try await SocketChatHost(socketPath: none, configLauncher: CarrierConfigLauncher(runner: FakeRunner(output: "", status: 0)) { nil }).changeProjects(.add(folder: "/a"))
    }
}
