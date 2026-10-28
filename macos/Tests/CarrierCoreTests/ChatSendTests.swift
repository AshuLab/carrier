import Foundation
import Testing
@testable import CarrierCore

// The box of a conversation, driven by a fake chat host: send, resume before send, the queue, Stop and the refusals shown.

private let session = "5d1f7c3a-0b6e-4a52-9a1d-3c7e8b2f4a01"

private func listed(live: Bool) -> ChatSession {
    let json = """
    {"id":"\(session)","agent":"claude","harness":"claude","folder":"/w","state":"idle","createdAt":0,"lastActiveAt":0,"archived":false,"live":\(live)}
    """
    return try! JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
}

private final class FakeChat: ChatHost, @unchecked Sendable {
    var live = true
    var state: ChatSession.State = .idle
    var calls: [String] = []
    var refuse: [String: Error] = [:]
    var events: [ChatEvent] = []
    var pending: Set<String> = []

    func agents() async throws -> [ChatAgent] { [] }
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [listed(live: live)] }
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents {
        let page = events.filter { $0.id > after }
        return ChatEvents(events: page, cursor: page.last?.id ?? after, state: state, pending: pending)
    }
    func resume(_ id: String) async throws {
        calls.append("resume")
        if let error = refuse["resume"] { throw error }
        live = true
    }
    func send(_ id: String, _ text: String) async throws {
        calls.append("send \(text)")
        if let error = refuse["send"] { throw error }
        state = .working
    }
    func interrupt(_ id: String) async throws {
        calls.append("interrupt")
        if let error = refuse["interrupt"] { throw error }
        state = .idle
    }
    func answer(_ id: String, approval: String, choice: String) async throws {
        calls.append("answer \(approval) \(choice)")
        if let error = refuse["answer"] { throw error }
        pending.remove(approval)
        events.append(ChatEvent(id: events.count + 1, at: 0, kind: "approval_answered", approvalId: approval, choiceId: choice))
        state = .working
    }
    func setOption(_ id: String, option: String, value: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { [] }
    func cloneRepo(_ repo: String) async throws -> ClonedRepo { throw ControlError.closed }
    func createProject(_ name: String) async throws -> String { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
}

@MainActor private func model(_ host: FakeChat, log: @escaping (String) -> Void = { _ in }) -> ConversationModel {
    ConversationModel(host: host, sessionId: session, log: log)
}

@MainActor @Test func enterSendsTheTrimmedDraftAndEmptiesTheBox() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "  hello\nthere \n"
    await chat.submit()
    #expect(host.calls == ["send hello\nthere"] && chat.draft == "" && chat.busy && chat.refusal == nil)
    chat.draft = "   "
    await chat.submit()
    #expect(host.calls.count == 1)
}

@MainActor @Test func aClosedSessionIsResumedBeforeTheMessageIsSent() async {
    let host = FakeChat()
    host.live = false
    let chat = model(host)
    chat.draft = "pick up"
    await chat.submit()
    #expect(host.calls == ["resume", "send pick up"])
    // a live one is not resumed
    chat.draft = "again"
    host.state = .idle
    await chat.poll()
    await chat.submit()
    #expect(host.calls == ["resume", "send pick up", "send again"])
}

@MainActor @Test func aRefusedResumeIsShownAndTheMessageIsNotSentAndStaysInTheBox() async {
    let host = FakeChat()
    host.live = false
    host.refuse["resume"] = ControlError.remote("The agent's folder is gone")
    var logged: [String] = []
    let chat = model(host, log: { logged.append($0) })
    chat.draft = "hi"
    await chat.submit()
    #expect(host.calls == ["resume"] && chat.refusal == "The agent's folder is gone" && chat.draft == "hi" && logged.isEmpty)
}

@MainActor @Test func aRefusedSendShowsTheReasonAndKeepsTheText() async {
    let host = FakeChat()
    host.refuse["send"] = ControlError.remote("That message has 70000 characters; the most a message can have is 64000")
    let chat = model(host)
    chat.draft = "too long"
    await chat.submit()
    #expect(chat.refusal?.hasPrefix("That message has 70000") == true && chat.draft == "too long" && chat.busy == false)
    // the next send that works clears it
    host.refuse["send"] = nil
    await chat.submit()
    #expect(chat.refusal == nil && chat.draft == "")
}

@MainActor @Test func aHostThatGoesAwayIsSaidAndLogged() async {
    let host = FakeChat()
    host.refuse["send"] = ControlError.closed
    var logged: [String] = []
    let chat = model(host, log: { logged.append($0) })
    chat.draft = "hi"
    await chat.submit()
    #expect(chat.refusal == "The chat host is not answering" && chat.draft == "hi" && logged.count == 1)
}

@MainActor @Test func whatIsTypedWhileTheAgentAnswersIsHeldAsOneMessageAndReplacedByTheNext() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "first"
    await chat.submit()
    #expect(chat.busy)
    chat.draft = "second"
    await chat.submit()
    #expect(chat.queued == "second" && chat.draft == "")
    chat.draft = "third"
    await chat.submit()
    #expect(chat.queued == "third" && host.calls == ["send first"])
}

@MainActor @Test func theQueuedMessageIsSentWhenTheTurnEndsAndNotBefore() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "first"
    await chat.submit()
    chat.draft = "next"
    await chat.submit()
    await chat.poll()
    #expect(host.calls == ["send first"] && chat.queued == "next")
    host.state = .idle
    await chat.poll()
    #expect(host.calls == ["send first", "send next"] && chat.queued == nil && chat.busy)
}

@MainActor @Test func aQueuedMessageCanBeCancelled() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "first"
    await chat.submit()
    chat.draft = "never"
    await chat.submit()
    chat.cancelQueued()
    host.state = .idle
    await chat.poll()
    #expect(chat.queued == nil && host.calls == ["send first"])
}

@MainActor @Test func aQueuedMessageTheHostRefusesComesBackToTheBoxWithTheReason() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "first"
    await chat.submit()
    chat.draft = "next"
    await chat.submit()
    host.state = .idle
    host.refuse["send"] = ControlError.remote("This session is closed")
    await chat.poll()
    #expect(chat.queued == nil && chat.draft == "next" && chat.refusal == "This session is closed")
}

@MainActor @Test func aWaitingForApprovalSessionIsBusyToo() async {
    let host = FakeChat()
    host.state = .waitingApproval
    let chat = model(host)
    await chat.poll()
    chat.draft = "hold on"
    await chat.submit()
    #expect(chat.busy && chat.queued == "hold on" && host.calls.isEmpty)
}

@MainActor @Test func stopInterruptsAndTheQueuedMessageGoesOnceTheAgentIsIdle() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "first"
    await chat.submit()
    chat.draft = "instead"
    await chat.submit()
    await chat.stop()
    #expect(host.calls == ["send first", "interrupt"] && chat.refusal == nil)
    await chat.poll()
    #expect(host.calls == ["send first", "interrupt", "send instead"])
}

@MainActor @Test func aRefusedStopIsShown() async {
    let host = FakeChat()
    host.refuse["interrupt"] = ControlError.remote("This session is closed")
    let chat = model(host)
    await chat.stop()
    #expect(chat.refusal == "This session is closed")
}

@MainActor @Test func aSecondMessageRightAfterASendIsQueuedWithoutWaitingForAPoll() async {
    let host = FakeChat()
    let chat = model(host)
    chat.draft = "go"
    await chat.submit()
    chat.draft = "also"
    await chat.submit()
    #expect(chat.queued == "also" && host.calls == ["send go"])
}

// MARK: approvals

private let asked = ChatEvent(
    id: 1, at: 0, kind: "approval", tool: "Bash", arg: "pnpm test webhook", approvalId: "p",
    choices: [.init(id: "allow", label: "Allow", allow: true), .init(id: "deny", label: "Decline", allow: false)]
)

@MainActor @Test func anApprovalPendingWhenTheSessionOpensIsACardAndChoosingItSendsTheAnswerAndTurnsItIntoALine() async {
    let host = FakeChat()
    host.events = [asked]
    host.pending = ["p"]
    host.state = .waitingApproval
    let chat = model(host)
    await chat.poll()
    guard case .approval(_, let card)? = chat.rows.last else {
        Issue.record("not a card")
        return
    }
    #expect(card.approvalId == "p" && chat.busy)
    await chat.answer("p", choice: "deny")
    #expect(host.calls == ["answer p deny"] && chat.refusal == nil)
    #expect(chat.rows == [.decided(id: "e1", text: "Declined Bash pnpm test webhook · Decline · by you", allow: false)])
}

@MainActor @Test func aRefusedAnswerIsShownInWordsAndTheCardStaysUntilTheHostSaysOtherwise() async {
    let host = FakeChat()
    host.events = [asked]
    host.pending = ["p"]
    let chat = model(host)
    await chat.poll()
    host.refuse["answer"] = ControlError.remote("That approval is not pending: it is unknown or was already answered")
    await chat.answer("p", choice: "allow")
    #expect(chat.refusal == "That approval is not pending: it is unknown or was already answered")
    guard case .approval? = chat.rows.last else {
        Issue.record("the card went")
        return
    }
    // a later answer that works clears the words
    host.refuse["answer"] = nil
    await chat.answer("p", choice: "allow")
    #expect(chat.refusal == nil)
}

@MainActor @Test func anApprovalThatStopsBeingPendingWithoutAnAnswerLeavesTheCardOnTheNextPoll() async {
    let host = FakeChat()
    host.events = [asked]
    host.pending = ["p"]
    let chat = model(host)
    await chat.poll()
    host.pending = []
    await chat.poll()
    #expect(chat.rows == [.line(id: "e1", text: "Bash pnpm test webhook · no longer waiting for an answer")])
}

// MARK: the real client

@Test func theClientSendsTheTextInsideAJSONStringAndResumesAndInterruptsByTheSessionId() async throws {
    var lines: [String] = []
    let server = TestServer { connection in
        connection.send("{\"event\":\"hello\",\"protocol\":1,\"pid\":1,\"startedAt\":0,\"version\":\"x\",\"capabilities\":[\"resume\",\"send\",\"interrupt\",\"answer\"]}\n")
        guard let line = connection.readLine(), let id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int else { return }
        lines.append(line)
        connection.send("{\"id\":\(id),\"ok\":true,\"data\":{}}\n")
    }
    defer { server.stop() }
    let host = SocketChatHost(socketPath: { server.path })
    try await host.send(session, "say \"hi\"\n\"},\"cmd\":\"stop")
    let sent = try #require(lines.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
    #expect(sent["cmd"] as? String == "send" && sent["sessionId"] as? String == session && sent["text"] as? String == "say \"hi\"\n\"},\"cmd\":\"stop")
    try await host.resume(session)
    try await host.interrupt(session)
    try await host.answer(session, approval: "a\"1", choice: "allow\n")
    let all = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    #expect(all.map { $0["cmd"] as? String } == ["send", "resume", "interrupt", "answer"])
    #expect(all[3]["sessionId"] as? String == session && all[3]["approvalId"] as? String == "a\"1" && all[3]["choiceId"] as? String == "allow\n")
    await #expect(throws: ControlError.remote("not a valid session id")) { try await host.send("../x", "hi") }
}
