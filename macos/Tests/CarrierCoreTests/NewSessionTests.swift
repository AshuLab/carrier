import Foundation
import Testing
@testable import CarrierCore

// The draft of a new session, driven by a fake chat host: the recent folders, the agent chip's availability, open then send,
// a refused open, a failed send and the sentence's text.

private let opened = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"

private func session(_ id: String, folder: String, base: String? = nil, at: Int, archived: Bool = false) -> ChatSession {
    let workspace = base.map { ",\"workspace\":{\"base\":\"\($0)\",\"branch\":\"carrier/x\"}" } ?? ""
    let json = """
    {"id":"\(id)","agent":"claude","harness":"claude","folder":"\(folder)","state":"idle","createdAt":0,"lastActiveAt":\(at),"archived":\(archived),"live":true\(workspace)}
    """
    return try! JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

private final class FakeChat: ChatHost, @unchecked Sendable {
    var agents: [ChatAgent] = [ChatAgent(name: "codex", harness: "codex", found: false), ChatAgent(name: "claude", harness: "claude", found: true)]
    var active: [ChatSession] = []
    var archived: [ChatSession] = []
    var calls: [String] = []
    var refuse: [String: Error] = [:]

    func agents() async throws -> [ChatAgent] { agents }
    func list(archived wanted: Bool) async throws -> [ChatSession] { wanted ? archived : active }
    func open(agent: String, folder: String) async throws -> String {
        calls.append("open \(agent) \(folder)")
        if let error = refuse["open"] { throw error }
        return opened
    }
    func send(_ id: String, _ text: String) async throws {
        calls.append("send \(id) \(text)")
        if let error = refuse["send"] { throw error }
    }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after) }
    func resume(_ id: String) async throws {}
    func interrupt(_ id: String) async throws {}
}

@MainActor private func draft(_ host: FakeChat, hostStarts: Bool = true, log: @escaping (String) -> Void = { _ in }) async -> NewSessionModel {
    let model = NewSessionModel(host: host, ensureHost: { hostStarts }, log: log)
    await model.load()
    return model
}

@Test func recentFoldersAreTheDistinctBasesMostRecentFirstAtMostEight() {
    let sessions = [
        session("a", folder: "/w/api", at: 10),
        session("b", folder: "/w/web", at: 30),
        session("c", folder: "/w/carrier-wt/x", base: "/w/carrier", at: 20),
        session("d", folder: "/w/api", at: 40, archived: true),
        session("e", folder: "/w/carrier", at: 5),
    ]
    #expect(recentFolders(sessions) == [
        RecentFolder(name: "api", path: "/w/api"), RecentFolder(name: "web", path: "/w/web"), RecentFolder(name: "carrier", path: "/w/carrier"),
    ])
    let many = (0..<12).map { session("s\($0)", folder: "/w/p\($0)", at: $0) }
    #expect(recentFolders(many).count == 8 && recentFolders(many).first?.path == "/w/p11" && recentFolders(many).last?.path == "/w/p4")
}

@MainActor @Test func theDraftOffersTheRecentFoldersOfActiveAndArchivedSessions() async {
    let host = FakeChat()
    host.active = [session("a", folder: "/w/api", at: 10)]
    host.archived = [session("b", folder: "/w/web", at: 20, archived: true)]
    let model = await draft(host)
    #expect(model.recent.map(\.path) == ["/w/web", "/w/api"])
}

@MainActor @Test func anAgentWithNoBinaryIsListedDisabledAndNotInstalledAndTheFirstFoundOneIsChosen() async {
    let model = await draft(FakeChat())
    #expect(model.agents == [AgentChoice(name: "codex", available: false), AgentChoice(name: "claude", available: true)])
    #expect(model.agents.map(\.note) == ["not installed", nil])
    #expect(model.agent == "claude")
}

@MainActor @Test func theSentenceSaysWhereItWorksAndUntilThenToChooseAWorkspace() async {
    let model = await draft(FakeChat())
    #expect(model.sentence == "Work in Choose a workspace… on the base folder")
    model.choose(folder: "/w/api")
    #expect(model.sentence == "Work in api on the base folder")
}

@MainActor @Test func theBoxCannotSendWithoutAWorkspaceAnAgentAndAMessage() async {
    let host = FakeChat()
    let model = await draft(host)
    model.text = "hello"
    #expect(model.canSend == false)
    #expect(await model.send() == nil && host.calls.isEmpty)
    model.choose(folder: "/w/api")
    #expect(model.canSend)
    model.text = "  \n"
    #expect(model.canSend == false)
    model.text = "hello"
    model.agent = nil
    #expect(model.canSend == false)
}

@MainActor @Test func sendingOpensTheSessionWithTheAgentAndFolderAndThenSendsTheMessage() async {
    let host = FakeChat()
    let model = await draft(host)
    model.choose(folder: "/w/api")
    model.text = " fix the bug \n"
    let id = await model.send()
    #expect(id == opened)
    #expect(host.calls == ["open claude /w/api", "send \(opened) fix the bug"])
    #expect(model.text == "" && model.refusal == nil && model.sending == false && model.takeFailure(of: opened) == nil)
}

@MainActor @Test func aRefusedOpenIsSaidInTheDraftAndKeepsTheMessage() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.remote("claude is not logged in; run claude once to log in")
    let model = await draft(host)
    model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "claude is not logged in; run claude once to log in" && model.text == "hello")
    #expect(host.calls == ["open claude /w/api"])
    #expect(signInLine(refusal: model.refusal ?? "") != nil)
}

@MainActor @Test func aSendThatFailsAfterOpenStillSelectsTheSessionAndHandsOverTheFailure() async {
    let host = FakeChat()
    host.refuse["send"] = ControlError.remote("The message is too long")
    let model = await draft(host)
    model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == opened)
    #expect(model.refusal == nil)
    #expect(model.takeFailure(of: opened) == FailedFirstSend(text: "hello", reason: "The message is too long"))
    #expect(model.takeFailure(of: opened) == nil)
}

@MainActor @Test func aHostThatCannotStartStopsTheSendBeforeOpen() async {
    let host = FakeChat()
    let model = await draft(host, hostStarts: false)
    model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == hostNotRunning && host.calls.isEmpty && model.text == "hello")
}

@MainActor @Test func aHostThatGoesAwayIsLoggedAndSaidInWords() async {
    let host = FakeChat()
    host.refuse["open"] = ControlError.closed
    var logged: [String] = []
    let model = await draft(host, log: { logged.append($0) })
    model.choose(folder: "/w/api")
    model.text = "hello"
    #expect(await model.send() == nil)
    #expect(model.refusal == "The chat host is not answering" && logged.count == 1)
}

@MainActor @Test func aFailedFirstSendShowsInTheConversationWithTryAgain() async {
    let conversation = ConversationModel(host: FakeChat(), sessionId: opened)
    conversation.showRefusal(of: "hello", "The message is too long")
    #expect(conversation.refusal == "The message is too long" && conversation.refusedText == "hello")
}

@Test func theClientOpensWithTheAgentAndFolderInsideJSONStringsAndReadsTheNewId() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"open\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{\"session\":{\"id\":\"\(opened)\",\"agent\":\"claude\"},\"options\":[]}}\n")
    }
    defer { server.stop() }
    let id = try await SocketChatHost(socketPath: { server.path }).open(agent: "claude", folder: "/w/\"odd\"\n/dir")
    #expect(id == opened)
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    #expect(sent["cmd"] as? String == "open" && sent["agent"] as? String == "claude" && sent["folder"] as? String == "/w/\"odd\"\n/dir")
}
