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
    #expect(hello.capabilities == [.sessions, .events, .epic, .files, .fileDiff, .availableRepos, .availableReposPaged, .resumeEpic, .resumeFromStage, .resumeReviewerOptions, .recoverEpic, .reload])
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
    let file = ProvidersFile(folder: server.home)
    try file.write(applyingAccounts([(name: "agy", harness: "agy")], to: try file.read()))
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
    #expect(states[0].menuLine == "Carrier running · \(snapshot.epics.count) \(snapshot.epics.count == 1 ? "epic" : "epics") · \(snapshot.slots.busy)/\(snapshot.slots.total) slots")
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
    #expect(rows.first?.line == "AshuLab/carrier" && rows.first?.pinned == true && rows.first?.tags == ["swift", "macos"])
    #expect(rows.first?.tile == ProjectTile(name: "carrier", color: .named(.teal), content: .mark(.bolt)))
    #expect(rows[1].name.count > 60 && rows[1].repo?.hasSuffix("/" + rows[1].path.split(separator: "/").last!) == true)
    #expect(rows[1].tags.count >= 8)
    // a folder that is not a repository shows its path, and so does one that is not there (with a missing icon copy)
    #expect(rows[2].line == rows[2].path && rows[2].iconColor == .orange && rows[2].tags.count >= 4 && rows[3].line == "/Users/demo/gone")
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
    #expect(listed.worktrees.count == 5 && listed.worktrees.contains { $0.session == nil })
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
    #expect(try await host.projectWorktrees(project).worktrees.count == 5)

    try await host.removeProjectWorktree(project, path: worktree("tassadar"))
    #expect(try await host.projectWorktrees(project).worktrees.map(\.path).contains(worktree("tassadar")) == false)

    let preview = try await host.cleanProjectWorktrees(project, run: false)
    #expect(preview.removed.map(\.path) == [worktree("raynor")] && preview.skipped.map(\.path) == [worktree("zeratul")])
    #expect(try await host.projectWorktrees(project).worktrees.count == 4) // a preview lists nothing away
    #expect(try await host.cleanProjectWorktrees(project, run: true) == preview)
    #expect(try await host.projectWorktrees(project).worktrees.count == 3)
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

    let file = ProvidersFile(folder: server.home)
    try file.write(applyingTextGenerator((server: "ollama", model: "qwen3:8b"), to: try file.read()))
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
