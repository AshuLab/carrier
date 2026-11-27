import Foundation
import Testing
@testable import CarrierCore

// `setWatchedRepos`, `editBehavior`, the role requests and the engine's `config` capability (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6): each request is what its golden file says
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

/// What the Behavior page builds for the golden: a poll every 2.5 minutes, debug logs, the default window and limits except 8 reviews, 4 lead rounds and no limit on the run time.
func goldenBehavior() -> EngineConfig {
    var config = EngineConfig()
    config.pollIntervalMinutes = 2.5
    config.logLevel = "debug"
    config.maxReviews = 8
    config.maxLeadRounds = 4
    config.maxExecutionHours = nil
    return config
}

/// What the Roles page builds for the goldens of the role requests.
let goldenRoleChanges: [(String, EngineConfigChange)] = [
    ("engine-edit-role.json", .role(.reviewer, [.bot("nova"), .provider("codex"), .model("gpt-5"), .effort(nil)])),
    ("engine-edit-repo-role.json", .repoRole(repo: "acme/web", role: .reviewer, fields: RoleFields(profile: "author-bot", model: "qwen3-coder", effort: "high", persona: RolePersona(name: "Rex")))),
    ("engine-edit-persona.json", .persona(role: .author, name: "Ada", prompt: nil)),
    ("engine-edit-failover.json", .failover(role: .author, first: FailoverStep(provider: "codex", model: "gpt-5", effort: "high"), second: FailoverStep(provider: "agy"))),
    ("engine-set-lead-reviewer.json", .leadReviewer(goldenLead())),
    ("engine-set-lead-reviewer-off.json", .leadReviewer(nil)),
    ("engine-set-orchestrator-profile.json", .orchestratorProfile("author-bot")),
    ("engine-add-extra-reviewer.json", .addExtraReviewer(ExtraReviewerDraft(name: "Seguridad API", type: "security", identity: .bot("nova"), provider: "claude", model: "sonnet", effort: "high"))),
    ("engine-edit-extra-reviewer-role.json", .extraReviewerRole(key: "seguridad-api", name: "Seguridad del front", type: "frontend-security", [.bot("nova"), .provider("codex"), .model("gpt-5-codex"), .effort(nil)])),
    ("engine-edit-extra-reviewer-persona.json", .extraReviewerPersona(key: "seguridad-api", name: "Centinela", prompt: nil)),
    ("engine-edit-extra-reviewer-failover.json", .extraReviewerFailover(key: "seguridad-api", first: FailoverStep(provider: "agy", model: "gemini", effort: "low"), second: nil)),
    ("engine-remove-extra-reviewer.json", .removeExtraReviewer(key: "seguridad-api")),
    ("engine-set-repo-extra-reviewers.json", .repoExtraReviewers(repo: "acme/web", [
        RepoExtraReviewer(key: "seguridad-api", type: "security", name: "Seguridad API", profile: "author-bot", provider: "claude", model: "sonnet", effort: "high"),
        RepoExtraReviewer(key: "usabilidad", type: "ux", name: "Usabilidad", profile: "reviewer-bot", provider: "codex", model: "gpt-5"),
    ])),
    ("engine-set-repo-extra-reviewers-none.json", .repoExtraReviewers(repo: "acme/web", [])),
    ("engine-set-repo-extra-reviewers-global.json", .repoExtraReviewers(repo: "acme/web", nil)),
]

func goldenLead() -> LeadReviewerDraft {
    var draft = LeadReviewerDraft()
    [RoleChange.gh, .provider("claude"), .model("opus"), .effort("max")].forEach { draft.apply($0) }
    return draft
}

let goldenRepos = EngineConfigChange.watchedRepos(["acme/web", "AshuLab/carrier", "new/one"])

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

@Test func eachRequestTheAppBuildsEncodesAsItsGoldenSaysWithoutItsId() throws {
    for (name, change) in [("engine-set-watched-repos.json", goldenRepos), ("engine-edit-behavior.json", EngineConfigChange.behavior(goldenBehavior()))] + goldenRoleChanges {
        let (request, _) = try golden(name)
        #expect(try object(change.request) == request as NSDictionary, Comment(rawValue: name))
        // one line, which is what `carrier config` reads
        #expect(String(decoding: change.request, as: UTF8.self).filter { $0 == "\n" }.count == 1)
    }
}

@Test func theGoldenRepliesDecodeIntoWhatTheEngineDid() throws {
    for name in ["engine-set-watched-repos.json", "engine-edit-behavior.json"] + goldenRoleChanges.map(\.0) {
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
    #expect(changes == ["pollIntervalMinutes": 5, "logLevel": "info", "finishedWindowDays": 15, "limits": ["maxConcurrentEpics": 3, "maxReviews": 5, "maxLeadRounds": 3, "maxExecutionRetries": 3, "maxExecutionHours": 4, "githubCallTimeoutSeconds": 30]] as NSDictionary)
    var config = EngineConfig()
    config.pollIntervalMinutes = .nan
    #expect(EngineConfigChange.behavior(config).fields == "")
}

@Test func aPickOfTheRolesPageIsOneRoleRequestWithTheIdentityAsTheProfileMeansItAndNullForNoEffort() throws {
    let changes = try #require(try object(EngineConfigChange.role(.author, [.gh, .provider("codex"), .model(" gpt-5 "), .effort("low"), .effort(nil)]).request)["changes"] as? NSDictionary)
    #expect(changes == ["identity": ["kind": "gh"], "provider": "codex", "model": " gpt-5 ", "effort": NSNull()] as NSDictionary)
    #expect(try object(EngineConfigChange.role(.leadReviewer, [.bot("nova")]).request) == ["cmd": "editRole", "role": "leadReviewer", "changes": ["identity": ["kind": "forge", "agent": "nova"]]] as NSDictionary)
}

@Test func aRepoRoleSendsOnlyTheFieldsItSetsAndResetSendsNull() throws {
    let set = try object(EngineConfigChange.repoRole(repo: "a/b", role: .author, fields: RoleFields(model: "m", persona: RolePersona(prompt: "p"))).request)
    #expect(set == ["cmd": "editRepoRole", "repo": "a/b", "role": "author", "fields": ["model": "m", "persona": ["prompt": "p"]]] as NSDictionary)
    #expect(try object(EngineConfigChange.repoRole(repo: "a/b", role: .reviewer, fields: nil).request) == ["cmd": "editRepoRole", "repo": "a/b", "role": "reviewer", "fields": NSNull()] as NSDictionary)
}

@Test func aPersonaAndAFailoverSendNullForWhatIsTakenOutAndLeaveTheEffortOfAStepOutWhenItHasNone() throws {
    #expect(try object(EngineConfigChange.persona(role: .author, name: nil, prompt: nil).request) == ["cmd": "editPersona", "role": "author", "name": NSNull(), "prompt": NSNull()] as NSDictionary)
    #expect(try object(EngineConfigChange.failover(role: .reviewer, first: FailoverStep(provider: "codex"), second: nil).request) == ["cmd": "editFailover", "role": "reviewer", "first": ["provider": "codex"], "second": NSNull()] as NSDictionary)
}

@Test func theLeadReviewerDraftIsSentAsItStandsAndAnIncompleteOneIsLeftToTheEngineToRefuse() throws {
    var draft = LeadReviewerDraft()
    draft.apply(.provider("codex"))
    #expect(try object(EngineConfigChange.leadReviewer(draft).request) == ["cmd": "setLeadReviewer", "draft": ["provider": "codex", "model": ""]] as NSDictionary)
    #expect(try object(EngineConfigChange.orchestratorProfile(nil).request) == ["cmd": "setOrchestratorProfile", "name": NSNull()] as NSDictionary)
}

@Test func aRepoListOfExtraReviewersIsSentWholeInItsOrderAndWithoutAnEffortItDoesNotHave() throws {
    let list = [
        RepoExtraReviewer(key: "zeta", type: "a", name: "Z", profile: "p", provider: "claude", model: "m"),
        RepoExtraReviewer(key: "alfa", type: "b", name: "A", profile: "p", provider: "codex", model: "n", effort: "low"),
    ]
    let line = String(decoding: EngineConfigChange.repoExtraReviewers(repo: "a/b", list).request, as: UTF8.self)
    #expect(try #require(line.range(of: "\"zeta\"")).lowerBound < #require(line.range(of: "\"alfa\"")).lowerBound)
    #expect(try object(EngineConfigChange.repoExtraReviewers(repo: "a/b", list).request) == ["cmd": "setRepoExtraReviewers", "repo": "a/b", "reviewers": [
        "zeta": ["type": "a", "name": "Z", "profile": "p", "provider": "claude", "model": "m"],
        "alfa": ["type": "b", "name": "A", "profile": "p", "provider": "codex", "model": "n", "effort": "low"],
    ]] as NSDictionary)
}

@Test func anExtraReviewerWithoutAnEffortIsSentWithoutOne() throws {
    let draft = ExtraReviewerDraft(name: "Sec", type: "security", identity: .gh, provider: "claude", model: "opus")
    #expect(try object(EngineConfigChange.addExtraReviewer(draft).request) == ["cmd": "addExtraReviewer", "draft": ["name": "Sec", "type": "security", "identity": ["kind": "gh"], "provider": "claude", "model": "opus"]] as NSDictionary)
}

@MainActor @Test func theQueueSendsOneChangeAtATimeInTheOrderItWasAskedEvenWhenAnEarlierOneAnswersLast() async {
    final class Slow: @unchecked Sendable {
        let lock = NSLock()
        var order: [String] = []
        func send(_ change: EngineConfigChange) async throws -> EngineConfigReply {
            lock.withLock { order.append("start \(change.command)") }
            if case .persona = change { try? await Task.sleep(for: .milliseconds(60)) }
            lock.withLock { order.append("end \(change.command)") }
            return EngineConfigReply(engine: .applied)
        }
    }
    let engine = Slow()
    let queue = EngineConfigQueue()
    let status = ReloadStatus(reload: { .nobody })
    // asked one after the other on the main actor, so the first is queued before the second
    let first = Task { @MainActor in await queue.save(.persona(role: .author, name: "Ada", prompt: nil), send: engine.send, status: status) }
    let second = Task { @MainActor in await queue.save(.orchestratorProfile(nil), send: engine.send, status: status) }
    let saved = await [first.value, second.value]
    #expect(saved == [.saved, .saved])
    #expect(engine.order == ["start editPersona", "end editPersona", "start setOrchestratorProfile", "end setOrchestratorProfile"])
}

@MainActor @Test func aChangeBuiltInTheQueueStartsFromWhatTheOnesBeforeItLeft() async {
    // the file, as the engine leaves it: each change adds its name to the list, so a change built from a list read earlier would overwrite the one before it
    final class File: @unchecked Sendable {
        let lock = NSLock()
        var names: [String] = []
        func send(_ change: EngineConfigChange) async throws -> EngineConfigReply {
            if case .persona(_, let name?, _) = change { try? await Task.sleep(for: .milliseconds(40)); lock.withLock { names.append(name) } }
            return EngineConfigReply(engine: .applied)
        }
        var read: [String] { lock.withLock { names } }
    }
    let file = File()
    let queue = EngineConfigQueue()
    let status = ReloadStatus(reload: { .nobody })
    var built: [[String]] = []
    // the second is asked while the first is still in flight; it is built only when the first has been written
    let first = Task { @MainActor in await queue.save(building: { built.append(file.read); return .persona(role: .author, name: "a", prompt: nil) }, send: file.send, status: status) }
    let second = Task { @MainActor in await queue.save(building: { built.append(file.read); return .persona(role: .author, name: "b", prompt: nil) }, send: file.send, status: status) }
    let nothing = Task { @MainActor in await queue.save(building: { nil }, send: file.send, status: status) }
    #expect(await [first.value, second.value, nothing.value] == [.saved, .saved, nil])
    #expect(built == [[], ["a"]] && file.read == ["a", "b"])
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
    #expect(await saveEngineConfig(.behavior(EngineConfig()), send: engine.send, status: status, bundle: english.bundle, locale: english.locale) == .refused("There is a problem in limits.maxReviews"))
    engine.failure = ControlError.timeout
    #expect(await saveEngineConfig(.behavior(EngineConfig()), send: engine.send, status: status).problem != nil)
    #expect(status.outcome == .nobody)
}

@Test func aRoleRequestGoesToTheSocketAsItsGoldenSaysAndToCarrierConfigWithoutAnIdWhenTheEngineIsOlder() async throws {
    let (request, reply) = try golden("engine-edit-role.json")
    let change = try #require(goldenRoleChanges.first { $0.0 == "engine-edit-role.json" }?.1)
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
    #expect(try await EngineConfigSender(socketPath: { server.path }, launcher: launcher(runner)).send(change).outcome == .applied && runner.ran.isEmpty)
    let line = try #require(asked.all.first)
    var sent = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(sent.removeValue(forKey: "id") != nil && sent as NSDictionary == request as NSDictionary)

    let older = TestServer { $0.send(hello("\"reload\"")) }
    defer { older.stop() }
    let output = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self) + "\n"
    let runner2 = FakeRunner(.success(ProcessResult(output: output, status: 0)))
    #expect(try await EngineConfigSender(socketPath: { older.path }, launcher: launcher(runner2)).send(change).outcome == .applied)
    let input = try #require(runner2.ran.first?.input)
    #expect(try object(input) == request as NSDictionary)
}

@MainActor @Test func aRoleRefusalOfTheEngineIsItsWordsAndTheFileWasNotChanged() async {
    let status = ReloadStatus(reload: { .nobody })
    let engine = FakeEngineConfig()
    engine.failure = ControlError.remote(Refusal(code: "config.problem", params: ["path": "agents.author.model", "problem": "empty"], text: "The model cannot be empty."))
    #expect(await saveEngineConfig(.role(.author, [.model(" ")]), send: engine.send, status: status, bundle: english.bundle, locale: english.locale) == .refused("There is a problem in agents.author.model"))
    #expect(status.outcome == nil && engine.sent == [.role(.author, [.model(" ")])])
}
