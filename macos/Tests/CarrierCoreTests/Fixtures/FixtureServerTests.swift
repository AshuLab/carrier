import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures.path

private func golden(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: fixtures + "/" + name))
}

/// Same JSON value, whatever the key order or spacing.
private func sameJSON(_ a: Data, _ b: Data) throws -> Bool {
    let (x, y) = (try JSONSerialization.jsonObject(with: a), try JSONSerialization.jsonObject(with: b))
    return (x as AnyObject).isEqual(y)
}

@Test func answersEachRequestFromItsGoldenFileOverARealSocket() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.socketPath))
    let hello = try client.hello()
    #expect(hello.capabilities == [.sessions, .events, .epic, .files, .fileDiff, .availableRepos, .availableReposPaged, .resumeEpic, .resumeFromStage, .resumeReviewerOptions, .recoverEpic, .reload, .config, .extraReviewers])
    let repo = ",\"repo\":\"AshuLab/web\",\"issue\":5"
    let id = ",\"executionId\":\"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c\""
    #expect(try sameJSON(client.request("snapshot"), golden("snapshot.json")))
    #expect(try sameJSON(client.request("sessions", fields: repo), golden("reply-sessions.json")))
    let sessions = try JSONDecoder().decode(SessionsReply.self, from: client.request("sessions", fields: repo))
    #expect(sessions.sessions.compactMap(\.failure?.kind) == ["usage_limit", "killed"])
    #expect(try sameJSON(client.request("events", fields: id + ",\"limit\":50"), golden("reply-events.json")))
    #expect(try sameJSON(client.request("epic", fields: repo), golden("reply-epic.json")))
    #expect(try sameJSON(client.request("files", fields: repo), golden("reply-files.json")))
    let diff = try JSONSerialization.jsonObject(with: golden("reply-filediff.json")) as? [Any]
    let first = try JSONSerialization.data(withJSONObject: try #require(diff?.first))
    #expect(try sameJSON(client.request("fileDiff", fields: repo + ",\"section\":\"slice-121\",\"path\":\"src/a.ts\""), first))
}

@Test func theFixtureChatHostAnswersProvidersFromItsGoldenFile() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    #expect(try client.hello().capabilities.contains(.providers))
    #expect(try sameJSON(client.request("providers"), golden("chat-providers.json")))
}

@Test func anAddInTheFixtureHomeTakesTheFoundNotAddedRowAway() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    _ = try client.hello()
    _ = fixtureProvidersChange(["cmd": "setAccounts", "accounts": [["name": "agy", "harness": "agy"]]], home: server.home)
    let reply = try JSONDecoder().decode(HostProviders.self, from: client.request("providers"))
    #expect(reply.unadded.isEmpty && reply.accounts.map(\.name) == ["claude", "claude-work", "codex", "agy"])
    #expect(reply.accounts.last?.harness == "agy" && reply.accounts.last?.found == true)
}

@Test func theFixtureChatHostAnswersUsageFromItsGoldenFile() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.chatSocketPath))
    let capabilities = try client.hello().capabilities
    #expect(capabilities.contains(.usage) && capabilities.contains(.usageOverride))
    #expect(try sameJSON(client.request("usage"), golden("chat-usage.json")))
    _ = try client.request("usageOverride", fields: ",\"model\":\"m\",\"action\":\"clear\"")
}

@Test func answersAnUnknownRequestWithAnError() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let client = try #require(ControlClient.connect(path: server.socketPath))
    _ = try client.hello()
    #expect(throws: ControlError.remote(Refusal(code: "request.invalid", text: "unknown request"))) { try client.request("selfDestruct") }
    // the connection is still good afterwards
    #expect(try client.request("pause") == Data("null".utf8))
}

@Test func theMonitorShowsTheFixtureAsRunning() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    var states: [ConnectionState] = []
    ControlMonitor(socketPath: { server.socketPath }, wait: { _ in false }, log: { _ in }, onChange: { states.append($0) }).run()
    let snapshot = try decodeSnapshot(golden("snapshot.json"))
    #expect(states == [.running(snapshot)])
    #expect(states[0].menuLine(bundle: english.bundle, locale: english.locale) == "Carrier running · \(snapshot.epics.count) \(snapshot.epics.count == 1 ? "epic" : "epics") · \(snapshot.slots.busy)/\(snapshot.slots.total) slots")
}

@Test func pointingCarrierHomeAtTheFixtureFindsItsSocket() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    #expect(controlSocketPath(environment: ["CARRIER_HOME": server.home], home: "/nonexistent") == server.socketPath)
}

@Test func stopRemovesTheSocketAndTheTemporaryHome() throws {
    let server = try FixtureServer(fixtures: fixtures)
    #expect(FileManager.default.fileExists(atPath: server.socketPath))
    server.stop()
    #expect(FileManager.default.fileExists(atPath: server.home) == false)
}

@Test func missingFixturesAreAnErrorAndLeaveNothingBehind() {
    #expect(throws: FixtureError.self) { try FixtureServer(fixtures: "/nonexistent") }
}

@Test func theFixtureChatHostSwitchesAnIdleSessionAndRefusesTheRestInWords() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let sessions = try await host.list(archived: false)
    let idle = try #require(sessions.first { $0.state == .idle && $0.agent == "claude" })
    let working = try #require(sessions.first { $0.state == .working })

    let switched = try await host.switchAgent(idle.id, to: "codex")
    #expect(switched.session == AgentSwitch.Session(id: idle.id, agent: "codex", harness: "codex", state: .idle))
    #expect(try await host.list(archived: false).first { $0.id == idle.id }?.agent == "codex")
    let notice = try #require(try await host.events(idle.id, after: 0, limit: 200).events.last)
    #expect(notice.kind == "notice" && notice.switched == ChatEvent.Switched(from: "claude", to: "codex"))

    await #expect(throws: ControlError.remote(Refusal(code: "session.switchAgent.same", params: ["agent": "codex"], text: "This session already has the agent \"codex\""))) { try await host.switchAgent(idle.id, to: "codex") }
    await #expect(throws: ControlError.remote(Refusal(code: "agent.unknown", params: ["agent": "ghost"], text: "There is no chat agent named \"ghost\""))) { try await host.switchAgent(idle.id, to: "ghost") }
    await #expect(throws: ControlError.remote(Refusal(code: "agent.notFound", params: ["agent": "claude-beta"], text: "The agent \"claude-beta\" is not found on this machine"))) { try await host.switchAgent(idle.id, to: "claude-beta") }
    await #expect(throws: ControlError.remote(Refusal(code: "session.switchAgent.busy", params: ["state": "working"], text: "This session is working; interrupt it or wait, then switch its agent"))) { try await host.switchAgent(working.id, to: "codex") }
}

@Test func theFixtureHomeCarriesProjectsThatTheListShowsWithTheirRemotes() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let rows = projectRows(try ProjectsFile(folder: server.home).read())
    #expect(rows.count == 8)
    #expect(rows.first?.line(bundle: english.bundle, locale: english.locale) == "AshuLab/carrier" && rows.first?.pinned == true && rows.first?.tags == ["swift", "macos"])
    #expect(rows.first?.tile == ProjectTile(name: "carrier", color: .named(.teal), content: .mark(.bolt)))
    #expect(rows[1].name.count > 60 && rows[1].repo?.hasSuffix("/" + rows[1].path.split(separator: "/").last!) == true)
    #expect(rows[1].tags.count >= 8)
    // a folder that is not a repository shows its path, and so does one that is not there (with a missing icon copy)
    #expect(rows[2].line(bundle: english.bundle, locale: english.locale) == rows[2].path && rows[2].iconColor == .orange && rows[2].tags.count >= 4 && rows[3].line(bundle: english.bundle, locale: english.locale) == "/Users/demo/gone")
    #expect(rows[3].iconImage == "missing.png" && ProjectIconStore(folder: server.home).existingURL(for: rows[3].iconImage) == nil)
    #expect(rows[4].name == "studio" && ProjectIconStore(folder: server.home).existingURL(for: rows[4].iconImage) != nil)
    // the sessions' folders and the epic repository `acme/web` show their projects' identities
    #expect(projectIdentity(path: "/Users/dev/carrier", in: rows).tile == ProjectTile(name: "Carrier app", color: .named(.red), content: .mark(.star)))
    #expect(projectIdentity(path: "/Users/dev/agent-forge", in: rows).tile.image == rows[4].iconImage)
    #expect(projectIdentity(path: "/Users/dev/web", in: rows).tile.image == nil && projectIdentity(repo: "acme/web", in: rows)?.tile.image == rows[4].iconImage)
}

@Test func theFixtureChatHostAnswersTheWorktreesOfAProjectByItsFolderName() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let listed = try await host.projectWorktrees(server.home + "/projects/carrier")
    #expect(listed.main == .init(path: server.home + "/projects/carrier", branch: "main", state: .notPushed))
    #expect(listed.worktrees.count == 6 && listed.worktrees.contains { $0.session == nil })
    // the golden file draws every activity and every integration, with a pull request on three of them
    #expect(listed.worktrees.compactMap(\.activity) == [.sessionOpen, .uncommitted])
    #expect(Set(listed.worktrees.map(\.integration)) == [.merged, .inMain, .notPushed, .prOpen, .prClosed, .pushed])
    #expect(listed.worktrees.compactMap(\.pullRequest?.number) == [1496, 1495, 1480])
    // a project the golden file does not list has its main clone and nothing else
    #expect(try await host.projectWorktrees(server.home + "/projects/notes") == .init(main: .init(path: server.home + "/projects/notes", branch: "main", state: .clean), worktrees: []))
}

@Test func theFixtureChatHostAnswersTheDiskOfAProjectByItsFolderNameAndNeverMeasuredForTheRest() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let carrier = server.home + "/projects/carrier"
    let reply = try await host.projectDisk([carrier, server.home + "/projects/studio"], refresh: .stale)
    #expect(reply.measuring.isEmpty)
    // the golden's "main" is the folder asked for, and the parts add up to the total
    #expect(reply.projects[0].bytes == 6_420_000_000 && reply.projects[0].parts[carrier] == 1_830_000_000 && reply.projects[0].parts.count == 6)
    #expect(reply.projects[0].parts.values.reduce(0, +) == reply.projects[0].bytes)
    #expect(reply.projects[1] == .init(folder: server.home + "/projects/studio", bytes: nil))
}

@Test func theFixtureChatHostRemovesAWorktreeAsTheHostDoesAndCleansUpTheMergedOnes() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let project = server.home + "/projects/carrier"
    let worktree = { (name: String) in "/Users/dev/.carrier/chat/worktrees/AshuLab/carrier/" + name }
    // an open session and uncommitted changes are refused with the host's words, and nothing is listed away
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.sessionOpen", text: "Its session is open"))) { try await host.removeProjectWorktree(project, path: worktree("kerrigan")) }
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.uncommitted", text: "It has uncommitted changes"))) { try await host.removeProjectWorktree(project, path: worktree("zeratul")) }
    await #expect(throws: ControlError.remote(Refusal(code: "worktree.unknown", text: "That is not a worktree of this project"))) { try await host.removeProjectWorktree(project, path: "/nowhere") }
    #expect(try await host.projectWorktrees(project).worktrees.count == 6)

    try await host.removeProjectWorktree(project, path: worktree("tassadar"))
    #expect(try await host.projectWorktrees(project).worktrees.map(\.path).contains(worktree("tassadar")) == false)

    let preview = try await host.cleanProjectWorktrees(project, run: false)
    #expect(preview.removed.map(\.path) == [worktree("raynor")] && preview.skipped.map(\.path) == [worktree("zeratul")])
    #expect(try await host.projectWorktrees(project).worktrees.count == 5) // a preview lists nothing away
    #expect(try await host.cleanProjectWorktrees(project, run: true) == preview)
    #expect(try await host.projectWorktrees(project).worktrees.count == 4)
    #expect(try await host.cleanProjectWorktrees(project, run: false).removed.isEmpty)
}

@Test func theFixtureChatHostWritesANewTitleAndRefusesInWordsWhereTheListSaysSo() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let sessions = try await host.list(archived: false)
    let fixable = try #require(sessions.first { $0.title == "Fix the flaky login test" })
    #expect(try await host.regenerateTitle(fixable.id) == "Regenerated title")
    #expect(try await host.list(archived: false).first { $0.id == fixable.id }?.title == "Regenerated title")

    let refused = try #require(sessions.first { $0.title == "Explore the pricing page layout" })
    await #expect(throws: ControlError.remote(Refusal(code: "title.noGenerator", text: "Could not write a title: no text generator is chosen; choose one in Providers"))) { try await host.regenerateTitle(refused.id) }
    #expect(try await host.list(archived: false).first { $0.id == refused.id }?.title == "Explore the pricing page layout")
}

@Test func theFixtureChatHostRegeneratesEarlierTitlesWhenAGeneratorIsChosen() async throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    await #expect(throws: ControlError.remote(Refusal(code: "title.noGenerator", text: "Could not write titles: no text generator is chosen; choose one in Providers"))) { _ = try await host.regenerateTitles() }

    _ = fixtureProvidersChange(["cmd": "setTextGenerator", "choice": ["server": "ollama", "model": "qwen3:8b"]], home: server.home)
    let started = try await host.regenerateTitles()
    #expect(started > 0)
    #expect(try await host.regenerateTitles() == 0)
    let fixable = try #require(try await host.list(archived: false).first { $0.id == "f6a7b8c9-5d4e-4f10-8b3c-4d5e6f7a8b06" })
    #expect(fixable.title == "Regenerated title")
}

@Test func theFixtureChatHostWritesItsChatJSONForEditChatSettingsAndRefusesWhatNodeRefuses() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    #expect(try await host.capabilities().contains(.config))
    let file = CarrierPlaces(folder: server.home).chatConfig
    func written() throws -> NSDictionary { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: file))) as? NSDictionary) }

    // the golden request: the other keys stay, a null removes a key
    try Data(#"{"agents":{"a":{"account":"claude"}},"idleCloseMinutes":30,"worktreeStart":"remote"}"#.utf8).write(to: URL(fileURLWithPath: file))
    let changes = ChatSettingChanges(["archiveAfterDays": .days(7), "deleteAfterDays": .text("never"), "worktreeStart": .text("local"), "idleCloseMinutes": .remove])
    let saved = try await host.editChatSettings(changes)
    #expect(saved.saved == ["archiveAfterDays": 7, "deleteAfterDays": "never", "worktreeStart": "local"])
    #expect(try written() == ["agents": ["a": ["account": "claude"]], "archiveAfterDays": 7, "deleteAfterDays": "never", "worktreeStart": "local"])

    // a value the schema refuses is refused with the key path and kind, and the file is left as it was
    let before = try Data(contentsOf: URL(fileURLWithPath: file))
    for (changes, path, problem) in [
        (ChatSettingChanges(["idleCloseMinutes": .days(15)]), "idleCloseMinutes", "invalid_union"),
        (ChatSettingChanges(["deleteAfterDays": .days(5)]), "deleteAfterDays", "custom"),
        (ChatSettingChanges(["archiveAfterDays": .days(0)]), "archiveAfterDays", "too_small"),
        (ChatSettingChanges(["worktreeStart": .text("origin")]), "worktreeStart", "invalid_value"),
    ] {
        do {
            _ = try await host.editChatSettings(changes)
            Issue.record("\(path) was saved")
        } catch ControlError.remote(let refusal) {
            #expect(refusal.code == "config.problem" && refusal.params == ["path": .string(path), "problem": .string(problem)], Comment(rawValue: path))
        }
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: file)) == before)

    // a file that does not exist is made, and one that is not a JSON object is refused and left alone
    try FileManager.default.removeItem(atPath: file)
    _ = try await host.editChatSettings(.idleClose(.oneHour))
    #expect(try written() == ["idleCloseMinutes": 60])
    try Data("[1]".utf8).write(to: URL(fileURLWithPath: file))
    do {
        _ = try await host.editChatSettings(.idleClose(.oneHour))
        Issue.record("a file that is not an object was written")
    } catch ControlError.remote(let refusal) {
        #expect(refusal.code == "config.problem" && refusal.params["problem"] == .string("notAnObject"))
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: file)) == Data("[1]".utf8))
}

@Test func theFixtureEngineAnswersSetWatchedReposAndEditBehaviorLikeTheRealEngineAgainstItsScratchFolder() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let file = CarrierPlaces(folder: server.home).engineConfig
    func written() throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: file))) as? [String: Any]) }
    let sender = EngineConfigSender(socketPath: { server.socketPath })

    // the golden request of the Watching page: a repo that stays keeps its fields, a new one is only its name, every other key stays
    let kept = try written()["repos"] as? [[String: Any]]
    let acmeApi = try #require(kept?.first { $0["name"] as? String == "acme/api" })
    let answer = try await sender.send(.watchedRepos(["acme/api", "new/one"]))
    #expect(answer.outcome == .applied)
    let repos = try #require(written()["repos"] as? [[String: Any]])
    #expect(repos.count == 2 && (repos[0] as NSDictionary) == (acmeApi as NSDictionary) && (repos[1] as NSDictionary) == ["name": "new/one"] as NSDictionary)
    #expect(try written()["agents"] != nil && written()["profiles"] != nil && written()["failover"] != nil)

    // the Behavior page: a value off the default is written, one on it is taken out, and an emptied limits goes
    var config = EngineConfig()
    config.logLevel = "debug"
    config.maxReviews = 8
    config.maxLeadRounds = 2
    config.maxExecutionHours = nil
    #expect(try await sender.send(.behavior(config)).outcome == .applied)
    #expect(try EngineConfig(json: Data(contentsOf: URL(fileURLWithPath: file))) == config)
    #expect(try (written()["limits"] as? [String: Any])?.keys.sorted() == ["maxExecutionHours", "maxLeadRounds", "maxReviews"] && written()["pollIntervalMinutes"] == nil)
    #expect(try await sender.send(.behavior(EngineConfig())).outcome == .applied)
    #expect(try written()["limits"] == nil && written()["logLevel"] == nil)

    // what Node refuses is refused with its words, a code and the key path and kind, and the file is left as it was
    let before = try Data(contentsOf: URL(fileURLWithPath: file))
    for (change, path, problem) in [
        (EngineConfigChange.watchedRepos(["a/b", "nope"]), "repos[1]", "notARepo"),
        (.watchedRepos(["a/b", "A/B"]), "repos[1]", "alreadyWatched"),
        (.watchedRepos(["a/web", "b/web"]), "repos[1]", "sameFolderName"),
    ] {
        do {
            _ = try await sender.send(change)
            Issue.record("\(path) was saved")
        } catch ControlError.remote(let refusal) {
            #expect(refusal.code == "config.problem" && refusal.params == ["path": .string(path), "problem": .string(problem)], Comment(rawValue: path))
        }
    }
    for (key, path) in [("maxReviews", "limits.maxReviews"), ("maxLeadRounds", "limits.maxLeadRounds")] {
        var bad = EngineConfig()
        if key == "maxReviews" { bad.maxReviews = 0 } else { bad.maxLeadRounds = 0 }
        do {
            _ = try await sender.send(.behavior(bad))
            Issue.record("a value the engine refuses was saved")
        } catch ControlError.remote(let refusal) {
            #expect(refusal.code == "config.problem" && refusal.params["path"] == .string(path) && refusal.text == "Must be 1 or more")
        }
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: file)) == before)
}

/// The fixture engine's `engine.json`, read again after each request, and a sender to its socket.
private struct ScratchEngine {
    let server: FixtureServer
    let file: String
    let sender: EngineConfigSender

    init() throws {
        server = try FixtureServer(fixtures: testPaths().fixtures.path)
        file = CarrierPlaces(folder: server.home).engineConfig
        let path = server.socketPath
        sender = EngineConfigSender(socketPath: { path })
    }

    func written() throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: file))) as? [String: Any]) }
    func role(_ name: String) throws -> [String: Any] { try #require((written()["agents"] as? [String: Any])?[name] as? [String: Any]) }

    func steps(_ role: String) throws -> [NSDictionary]? {
        try (((written()["failover"] as? [String: Any])?["roles"]) as? [String: Any])?[role].flatMap { $0 as? [[String: Any]] }?.map { $0 as NSDictionary }
    }

    func refusal(_ change: EngineConfigChange) async throws -> Refusal {
        do { _ = try await sender.send(change) } catch ControlError.remote(let refusal) { return refusal }
        throw FixtureError.socket("\(change) was not refused")
    }
}

@Test func theFixtureEngineChangesARoleItsPersonaAndItsFailoverLikeTheRealEngineAgainstItsScratchFolder() async throws {
    let engine = try ScratchEngine()
    defer { engine.server.stop() }
    // identity, provider, model and effort of a role in one request; a bot of the registry gets the profile that means it, and the failover step the role now runs on goes
    #expect(try await engine.sender.send(.role(.author, [.bot("acme-spare"), .provider("codex"), .model(" gpt-5 "), .effort(nil)])).outcome == .applied)
    #expect(try engine.role("author") as NSDictionary == ["profile": "acme-spare", "provider": "codex", "model": "gpt-5"] as NSDictionary)
    #expect(try engine.steps("author") == [["provider": "claude-work"]])
    #expect(try (engine.written()["profiles"] as? [String: Any])?["acme-spare"] != nil && engine.written()["repos"] != nil)
    #expect(try await engine.sender.send(.role(.author, [.gh])).outcome == .applied)
    #expect(try engine.role("author")["profile"] as? String == "gh")
    #expect(try await engine.sender.send(.persona(role: .reviewer, name: "Ada", prompt: "Be brief.")).outcome == .applied)
    #expect(try (engine.role("reviewer")["persona"] as? [String: Any]) as NSDictionary? == ["name": "Ada", "prompt": "Be brief."] as NSDictionary)
    #expect(try await engine.sender.send(.persona(role: .reviewer, name: nil, prompt: nil)).outcome == .applied)
    #expect(try engine.role("reviewer")["persona"] == nil)
    #expect(try await engine.sender.send(.failover(role: .reviewer, first: FailoverStep(provider: "codex", model: "gpt-5-mini", effort: "low"), second: nil)).outcome == .applied)
    #expect(try engine.steps("reviewer") == [["provider": "codex", "model": "gpt-5-mini", "effort": "low"]])
    #expect(try await engine.sender.send(.failover(role: .reviewer, first: nil, second: nil)).outcome == .applied)
    #expect(try engine.steps("reviewer") == nil)

    // what the real engine refuses is refused with its words and a code, and the file is left as it was
    let before = try Data(contentsOf: URL(fileURLWithPath: engine.file))
    for (change, words) in [
        (EngineConfigChange.role(.author, [.bot("ghost")]), "“ghost” is not in Agent Forge’s list. Pick another one."),
        (.role(.author, [.provider("nope")]), "Provider “nope” is not an account of providers.json. Pick another one."),
        (.role(.author, [.model("  ")]), "The model cannot be empty."),
        (.persona(role: .author, name: String(repeating: "x", count: 41), prompt: nil), "The persona’s name is one line of up to 40 characters."),
        (.failover(role: .author, first: nil, second: FailoverStep(provider: "codex")), "Then needs a First step."),
        (.failover(role: .author, first: FailoverStep(provider: "codex", model: "gpt-5"), second: nil), "First is the role’s own provider and model, so it would move nowhere."),
    ] {
        let refusal = try await engine.refusal(change)
        #expect(refusal.code == "config.problem" && refusal.text == words, Comment(rawValue: words))
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: engine.file)) == before)
}

@Test func theFixtureEngineTurnsTheLeadReviewerOffAndOnOnlyWithAWholeDraft() async throws {
    let engine = try ScratchEngine()
    defer { engine.server.stop() }
    #expect(try await engine.sender.send(.leadReviewer(nil)).outcome == .applied)
    #expect(try engine.written()["agents"] != nil && (engine.written()["agents"] as? [String: Any])?["leadReviewer"] == nil)
    var draft = LeadReviewerDraft()
    [RoleChange.bot("acme-lead"), .provider("claude"), .model("claude-opus-5")].forEach { draft.apply($0) }
    var incomplete = LeadReviewerDraft()
    incomplete.apply(.provider("claude"))
    #expect(try await engine.refusal(.leadReviewer(incomplete)).text.hasPrefix("The lead reviewer needs "))
    #expect(try await engine.sender.send(.leadReviewer(draft)).outcome == .applied)
    #expect(try engine.role("leadReviewer") as NSDictionary == ["profile": "acme-lead", "provider": "claude", "model": "claude-opus-5"] as NSDictionary)
}

@Test func theFixtureEngineSetsAndTakesOutTheOrchestratorProfile() async throws {
    let engine = try ScratchEngine()
    defer { engine.server.stop() }
    #expect(try await engine.sender.send(.orchestratorProfile("acme-lead")).outcome == .applied)
    #expect(try engine.written()["orchestratorProfile"] as? String == "acme-lead")
    #expect(try await engine.sender.send(.orchestratorProfile(nil)).outcome == .applied)
    #expect(try engine.written()["orchestratorProfile"] == nil && engine.written()["repos"] != nil)
}

@Test func theFixtureEngineSetsARepoRoleFromTheFieldsThatAreSetAndResetTakesItOut() async throws {
    let engine = try ScratchEngine()
    defer { engine.server.stop() }
    // the fields that are set, and Reset takes the entry out (the repo's own list of reviewers stays: it is not a role's field)
    func repoAgents() throws -> [String: Any]? { try (engine.written()["repos"] as? [[String: Any]])?.first { $0["name"] as? String == "acme/web" }?["agents"] as? [String: Any] }
    #expect(try await engine.sender.send(.repoRole(repo: "acme/web", role: .reviewer, fields: RoleFields(model: "qwen", persona: RolePersona(name: "Rex")))).outcome == .applied)
    #expect(try repoAgents()?["reviewer"] as? NSDictionary == ["model": "qwen", "persona": ["name": "Rex"]] as NSDictionary)
    #expect(try await engine.sender.send(.repoRole(repo: "acme/web", role: .reviewer, fields: nil)).outcome == .applied)
    #expect(try repoAgents()?["reviewer"] == nil && repoAgents()?["extraReviewers"] != nil)
    #expect(try await engine.refusal(.repoRole(repo: "x/y", role: .author, fields: nil)).text == "x/y is no longer in the config file.")
    #expect(try await engine.refusal(.repoRole(repo: "acme/web", role: .author, fields: RoleFields(profile: "ghost"))).text == "Identity “ghost” is not declared in profiles. Pick another one.")
}

@Test func theFixtureChatHostAnswersTheFiveProvidersRequestsLikeTheRealOneWithTheEnginesAnswer() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let file = ProvidersFile(folder: server.home)
    func accounts() throws -> [String] {
        let data = try #require(try file.read())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (json["providers"] as? [String: Any] ?? [:]).keys.sorted()
    }
    func refusal(_ request: ProvidersRequest) async throws -> Refusal {
        do { _ = try await host.changeProviders(request) } catch ControlError.remote(let refusal) { return refusal }
        throw FixtureError.socket("\(request) was not refused")
    }

    // set the detected accounts, add, edit: written to the scratch folder, with the engine's answer
    #expect(try await host.changeProviders(.setAccounts([DetectedAccount(name: "agy", harness: "agy")])).outcome == .applied)
    #expect(try await host.changeProviders(.addAccount(name: "spare", harness: "codex", configDir: "")).outcome == .applied)
    var draft = AccountDraft()
    draft.displayName = "Spare"
    #expect(try await host.changeProviders(.editAccount(name: "spare", draft: draft)).outcome == .applied)
    #expect(try accounts() == ["agy", "claude", "claude-work", "codex", "spare"])
    #expect(try accountDraft(named: "spare", in: file.read())?.displayName == "Spare")
    // and the page sees them
    #expect(try await host.providers().accounts.first { $0.name == "spare" }?.displayName == "Spare")

    // the refusals of the real host, with their codes
    #expect(try await refusal(.addAccount(name: "spare", harness: "codex", configDir: "")).has("account.taken"))
    #expect(try await refusal(.editAccount(name: "ghost", draft: draft)).has("account.missing"))
    #expect(try await refusal(.removeAccount(name: "ghost")).has("account.missing"))
    let inUse = try await refusal(.removeAccount(name: "claude-work"))
    #expect(inUse.has("account.inUse") && inUse.text.hasPrefix("claude-work is used by ") && inUse.text.contains("Chat agent work") && inUse.text.hasSuffix(", so it stays. Point those at another account first."))
    #expect(try await host.changeProviders(.removeAccount(name: "spare")).outcome == .applied)
    #expect(try accounts() == ["agy", "claude", "claude-work", "codex"])

    // the text generator: chosen, then cleared, and a server that is not one is refused
    #expect(try await host.changeProviders(.setTextGenerator(TextGeneratorChoice(server: "ollama", model: "qwen3:8b"))).outcome == .applied)
    #expect(try await host.providers().textGenerator == HostProviders.TextGenerator(name: "ollama", kind: "ollama", model: "qwen3:8b"))
    #expect(try await host.changeProviders(.setTextGenerator(nil)).outcome == .applied)
    #expect(try await host.providers().textGenerator == nil)
    #expect(try await refusal(.setTextGenerator(TextGeneratorChoice(server: "openai", model: "m"))).has("config.problem"))
}

@MainActor @Test func theProvidersStoreChangesTheFixtureFolderThroughTheHostAndShowsWhyItWasRefused() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let file = ProvidersFile(folder: server.home)
    let store = ProvidersStore(host: SocketChatHost(socketPath: { server.chatSocketPath }), file: { file }, log: { _ in }, status: ReloadStatus(), bundle: english.bundle, locale: english.locale)
    await store.load()
    #expect(await store.addAccount(name: "claude-two", harness: "claude", configDir: "~/.claude-two"))
    await store.settled()
    #expect(store.editProblem == nil && store.editNote == nil)
    #expect(try accountDraft(named: "claude-two", in: file.read())?.configDir == "~/.claude-two")
    #expect(await store.remove(name: "claude") == false)
    #expect(store.editProblem?.hasPrefix("claude is used by ") == true && store.editProblem?.contains("Chat agent claude") == true)
    #expect(await store.remove(name: "claude-two"))
    #expect(try accountDraft(named: "claude-two", in: file.read()) == nil)
}

@Test func theFixtureChatHostAnswersTheNineProjectRequestsLikeTheRealOneAndWritesItsScratchFolder() async throws {
    let server = try FixtureServer(fixtures: testPaths().fixtures.path)
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.chatSocketPath })
    let file = ProjectsFile(folder: server.home)
    let first = try #require(try file.read().first)
    let folder = server.home + "/elsewhere"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    func entry(_ path: String) throws -> ProjectEntry { try #require(try file.read().first { $0.path == path }) }

    // added, then already one however the folder is written
    let added = try await host.changeProjects(.add(folder: folder))
    let made = try entry(folder)
    #expect(added.added == true && added.saved?.path == folder && made.origin == "added" && made.name == "elsewhere")
    let again = try await host.changeProjects(.add(folder: folder))
    #expect(again.added == false)

    // the keys of the entry the person wrote stay, a null takes one out
    _ = try await host.changeProjects(.edit(path: folder, key: "name", value: .text("Else")))
    _ = try await host.changeProjects(.edit(path: folder, key: "pinned", value: .flag(true)))
    _ = try await host.changeProjects(.editTags(path: folder, add: ["B", " a "], remove: []))
    _ = try await host.changeProjects(.editIcon(path: folder, changes: ["color": .text("teal"), "mark": .text("bolt")]))
    _ = try await host.changeProjects(.editDefaults(path: folder, changes: ["agent": .text("claude"), "access": .map(["mode": "plan"])]))
    _ = try await host.changeProjects(.setActions(path: folder, actions: [ProjectAction(name: "Setup", command: "make", when: .afterClone)]))
    var written = try entry(folder)
    #expect(written.name == "Else" && written.pinned && written.tags == ["b", "a"] && written.iconColor == "teal" && written.iconMark == "bolt")
    #expect(written.defaults.agent == "claude" && written.defaults.access == ["mode": "plan"] && written.actions.map(\.name) == ["Setup"])
    _ = try await host.changeProjects(.edit(path: folder, key: "pinned", value: .remove))
    _ = try await host.changeProjects(.editTags(path: folder, add: [], remove: ["a", "B"]))
    _ = try await host.changeProjects(.editIcon(path: folder, changes: ["color": .remove, "mark": .remove]))
    _ = try await host.changeProjects(.setActions(path: folder, actions: []))
    written = try entry(folder)
    #expect(written.pinned == false && written.tags.isEmpty && written.json["icon"] == nil && written.json["actions"] == nil && written.defaults.agent == "claude")

    // moved, then removed
    let moved = folder + "-moved"
    let movedTo = try await host.changeProjects(.move(path: folder, folder: moved))
    #expect(movedTo.saved?.path == moved)
    let removed = try await host.changeProjects(.remove(path: moved))
    #expect(removed.removed == moved)
    let left = try file.read().map(\.path)
    #expect(left.first == first.path && left.contains(moved) == false && left.contains(folder) == false)

    // refused with a code and the file left as it was
    let before = try Data(contentsOf: file.url)
    for (change, code) in [(ProjectsChange.remove(path: "/nowhere"), "project.missing"), (.edit(path: "/nowhere", key: "name", value: .text("x")), "project.missing"), (.move(path: first.path, folder: "relative"), "config.problem")] {
        do {
            _ = try await host.changeProjects(change)
            Issue.record("\(change.cmd) was saved")
        } catch ControlError.remote(let refusal) {
            #expect(refusal.code == code, Comment(rawValue: change.cmd))
        }
    }
    #expect(try Data(contentsOf: file.url) == before)

    // the projects folder goes to chat.json, and Carrier's own folders are refused with the old one left
    let chat = URL(fileURLWithPath: CarrierPlaces(folder: server.home).chatConfig)
    let chatBefore = try Data(contentsOf: chat)
    let set = try await host.changeProjects(.setFolder("/Users/demo/code"))
    #expect(set.saved?.projectsFolder == "/Users/demo/code")
    let after = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: chat)) as? [String: Any])
    let kept = try #require(JSONSerialization.jsonObject(with: chatBefore) as? [String: Any])
    #expect(after["projectsFolder"] as? String == "/Users/demo/code" && after.count == kept.count + (kept["projectsFolder"] == nil ? 1 : 0))
    do {
        _ = try await host.changeProjects(.setFolder(server.home + "/engine/x"))
        Issue.record("a folder inside engine was saved")
    } catch ControlError.remote(let refusal) {
        #expect(refusal.code == "folder.insideCarrier")
    }
}
