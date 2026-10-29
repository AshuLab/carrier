import Foundation
import Observation

// An open session's conversation (docs/specs/sessions-in-the-app.md, "The conversation"): the events of the host's `events` reply,
// the feed of rows they make (a pure function) and the model that polls by cursor and keeps the feed current.

/// One of the provider's choices on an approval.
public struct ChatChoice: Codable, Equatable {
    public let id: String
    public let label: String
    public let allow: Bool

    public init(id: String, label: String, allow: Bool) {
        self.id = id
        self.label = label
        self.allow = allow
    }
}

/// An event of the conversation as the host stores it (docs/specs/chat-host.md, Decisions): `kind` says which of the fields are there.
public struct ChatEvent: Codable, Equatable {
    public let id: Int
    /// Milliseconds since the epoch.
    public let at: Int
    public let kind: String
    public var text: String?
    public var callId: String?
    public var tool: String?
    public var arg: String?
    public var output: [String]?
    public var status: String?
    public var approvalId: String?
    public var choices: [ChatChoice]?
    public var choiceId: String?
    public var outcome: String?
    public var model: String?
    /// As the provider reported it: its keys differ (`input_tokens` or `inputTokens`), and any of them can be missing.
    public var usage: [String: Double]?

    public init(
        id: Int, at: Int, kind: String, text: String? = nil, callId: String? = nil, tool: String? = nil, arg: String? = nil, output: [String]? = nil,
        status: String? = nil, approvalId: String? = nil, choices: [ChatChoice]? = nil, choiceId: String? = nil, outcome: String? = nil,
        model: String? = nil, usage: [String: Double]? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.text = text
        self.callId = callId
        self.tool = tool
        self.arg = arg
        self.output = output
        self.status = status
        self.approvalId = approvalId
        self.choices = choices
        self.choiceId = choiceId
        self.outcome = outcome
        self.model = model
        self.usage = usage
    }
}

/// The reply of `events`: the page after the cursor, the cursor to ask from next and the text of the message being written.
/// The session's state (from its summary) comes with it, as the model needs to know whether the agent is answering; so do the ids
/// of the approvals still pending (the ones the person can answer) and the options, which the slice that draws them reads.
public struct ChatEvents: Decodable, Equatable {
    public let events: [ChatEvent]
    public let cursor: Int
    public let streaming: String
    public let state: ChatSession.State?
    public let pending: Set<String>
    /// What the provider offers for this session, with the current values; empty for a closed session.
    public let options: [ChatOption]

    public init(
        events: [ChatEvent], cursor: Int, streaming: String = "", state: ChatSession.State? = nil, pending: Set<String> = [], options: [ChatOption] = []
    ) {
        self.events = events
        self.cursor = cursor
        self.streaming = streaming
        self.state = state
        self.pending = pending
        self.options = options
    }

    private enum CodingKeys: String, CodingKey { case events, cursor, streaming, session, approvals, options }
    private struct Summary: Decodable { let state: ChatSession.State }
    private struct Approval: Decodable { let approvalId: String }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        events = try values.decode([ChatEvent].self, forKey: .events)
        cursor = try values.decode(Int.self, forKey: .cursor)
        streaming = try values.decode(String.self, forKey: .streaming)
        state = try values.decodeIfPresent(Summary.self, forKey: .session)?.state
        pending = Set(try values.decodeIfPresent([Approval].self, forKey: .approvals)?.map(\.approvalId) ?? [])
        options = try values.decodeIfPresent([ChatOption].self, forKey: .options) ?? []
    }
}

/// A row of the feed.
public enum FeedRow: Equatable, Identifiable {
    /// What the person wrote: a bubble on the right.
    case user(id: String, text: String)
    /// What the agent wrote, as markdown; `inProgress` is the text still being written, which is not stored yet.
    case agent(id: String, text: String, inProgress: Bool)
    /// The line that closes a turn: the model, how long it took and the usage the provider reported.
    case turnEnd(id: String, text: String)
    /// A run of tool calls: one row that opens to its calls.
    case tools(id: String, ToolGroup)
    /// An approval waiting for the person: a card with the provider's choices.
    case approval(id: String, ApprovalCard)
    /// An approval that was answered: one line, green when the choice allowed and red when it did not.
    case decided(id: String, text: String, allow: Bool)
    /// An approval that is not waiting any more and was not answered (its turn ended): one plain line.
    case line(id: String, text: String)
    /// An error event: the provider's text, in the banner of a failed turn.
    case error(id: String, text: String)
    /// A turn the person stopped: the mark with Continue.
    case stopped(id: String)

    public var id: String {
        switch self {
        case .user(let id, _), .agent(let id, _, _), .turnEnd(let id, _), .tools(let id, _), .approval(let id, _), .decided(let id, _, _),
            .line(let id, _), .error(let id, _), .stopped(let id): id
        }
    }
}

/// The row of the mark or banner that offers a way out (Continue, Try again): the last stopped or failed turn, and only while the
/// person has not written since. Earlier ones are only a record.
public func openOutcome(_ rows: [FeedRow]) -> String? {
    for row in rows.reversed() {
        switch row {
        case .user: return nil
        case .error(let id, _), .stopped(let id): return id
        default: continue
        }
    }
    return nil
}

/// A banner over the feed or the box: what the provider said (or the host's reason), and the hint under it when there is one.
public struct FailureBanner: Equatable {
    public let title: String
    public let detail: String
    public let hint: String?
}

private func capitalized(_ agent: String) -> String { agent.isEmpty ? "The agent" : agent.prefix(1).uppercased() + agent.dropFirst() }

/// The banner of a turn that failed: "<Agent> couldn't continue" and the error's text.
public func failedTurnBanner(agent: String, error: String) -> FailureBanner {
    FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: error, hint: nil)
}

/// The banner of a refusal from `open`, `resume` or `send`: the host's own sentence, and for a provider that is not signed in the
/// line that says where to sign in.
public func refusalBanner(agent: String, reason: String) -> FailureBanner {
    if let hint = signInLine(refusal: reason) { return FailureBanner(title: "\(capitalized(agent)) isn't signed in", detail: reason, hint: hint) }
    return FailureBanner(title: "\(capitalized(agent)) couldn't continue", detail: reason, hint: nil)
}

/// Above the box of a session that is not live: sending to it resumes it.
public let closedSessionNotice = "This session is closed. Send a message and it picks up where it left off."

/// The line under a refusal when the provider is not signed in, nil for any other. The adapters say "<Agent> is not logged in; run … once to log in".
public func signInLine(refusal reason: String) -> String? {
    reason.localizedCaseInsensitiveContains("is not logged in") ? "Sign in from a terminal; Carrier never asks for your password" : nil
}

/// An approval as the card draws it: the question, the tool and its argument, and the provider's choices in its own order.
public struct ApprovalCard: Equatable {
    public let approvalId: String
    public let question: String
    public let tool: String
    public let arg: String?
    public let choices: [ChatChoice]
}

/// The rows the events make, in order, and then the message in progress when `streaming` has text. Consecutive calls are one row
/// at the place where the first started, each completed by its end (a turn that ends first stops the calls still going); an
/// approval is one row at the place where it was asked: a card while its id is in `pending` (what the host still waits for),
/// a line once answered, and a plain line when it is neither (the turn ended without it).
/// Anything else the host may add is not drawn.
public func chatFeed(_ events: [ChatEvent], streaming: String = "", pending: Set<String> = []) -> [FeedRow] {
    var rows: [FeedRow] = []
    // where each call still going is: its row and its place in it
    var going: [String: (row: Int, call: Int)] = [:]
    var asked: [String: (row: Int, event: ChatEvent)] = [:]
    var turnStart: Int?
    for event in events {
        let id = "e\(event.id)"
        switch event.kind {
        case "user":
            turnStart = event.at
            rows.append(.user(id: id, text: event.text ?? ""))
        case "assistant":
            rows.append(.agent(id: id, text: event.text ?? "", inProgress: false))
        case "tool_start":
            let call = ToolCall(start: event)
            going[call.id] = place(call, in: &rows, id: id)
        case "tool_end":
            if let call = event.callId, let spot = going.removeValue(forKey: call), case .tools(let group, var calls) = rows[spot.row] {
                calls.calls[spot.call].finish(event)
                rows[spot.row] = .tools(id: group, calls)
            } else {
                _ = place(ToolCall(orphanEnd: event), in: &rows, id: id)
            }
        case "approval":
            if let approval = event.approvalId { asked[approval] = (rows.count, event) }
            if let approval = event.approvalId, pending.contains(approval) {
                let tool = event.tool ?? "the tool"
                rows.append(.approval(id: id, ApprovalCard(approvalId: approval, question: "Allow \(tool)?", tool: tool, arg: event.arg, choices: event.choices ?? [])))
            } else {
                rows.append(.line(id: id, text: "\(what(event)) · no longer waiting for an answer"))
            }
        case "approval_answered":
            guard let approval = event.approvalId, let question = asked[approval] else { continue }
            rows[question.row] = decided(question.event, choice: event.choiceId, id: rows[question.row].id)
        case "turn_end":
            for spot in going.values {
                guard case .tools(let group, var calls) = rows[spot.row] else { continue }
                calls.calls[spot.call].stop()
                rows[spot.row] = .tools(id: group, calls)
            }
            going = [:]
            if let text = closingLine(event, turnStart: turnStart) { rows.append(.turnEnd(id: id, text: text)) }
            if event.outcome == "interrupted" { rows.append(.stopped(id: "\(id)-stopped")) }
            turnStart = nil
        case "error":
            rows.append(.error(id: id, text: event.text ?? "Something went wrong"))
        default:
            continue
        }
    }
    if streaming.isEmpty == false { rows.append(.agent(id: "streaming", text: streaming, inProgress: true)) }
    return rows
}

/// Puts a call at the end of the run the last row is, or opens a row for it.
private func place(_ call: ToolCall, in rows: inout [FeedRow], id: String) -> (row: Int, call: Int) {
    if case .tools(let group, var run)? = rows.last {
        run.calls.append(call)
        rows[rows.count - 1] = .tools(id: group, run)
        return (rows.count - 1, run.calls.count - 1)
    }
    rows.append(.tools(id: id, ToolGroup(calls: [call])))
    return (rows.count - 1, 0)
}

private func what(_ approval: ChatEvent) -> String { [approval.tool, approval.arg].compactMap { $0 }.joined(separator: " ") }

/// "Allowed pnpm test · Allow once · by you": the verb is from whether the chosen choice allows, the label is the provider's own.
private func decided(_ approval: ChatEvent, choice: String?, id: String) -> FeedRow {
    guard let chosen = approval.choices?.first(where: { $0.id == choice }) else {
        return .decided(id: id, text: "Answered \(what(approval)) · by you", allow: false)
    }
    return .decided(id: id, text: "\(chosen.allow ? "Allowed" : "Declined") \(what(approval)) · \(chosen.label) · by you", allow: chosen.allow)
}

/// "claude-sonnet-5-5 · 12s · 1.8k in · 436 out": each part only when the host or the provider gave it.
private func closingLine(_ end: ChatEvent, turnStart: Int?) -> String? {
    func tokens(_ keys: String...) -> String? {
        guard let count = keys.lazy.compactMap({ end.usage?[$0] }).first else { return nil }
        return count < 1000 ? "\(Int(count))" : String(format: "%.1fk", count / 1000)
    }
    let parts = [
        end.model, turnStart.map { formatDuration(end.at - $0) },
        tokens("input_tokens", "inputTokens").map { "\($0) in" }, tokens("output_tokens", "outputTokens").map { "\($0) out" },
    ]
    let line = parts.compactMap { $0 }.joined(separator: " · ")
    return line.isEmpty ? nil : line
}

/// The conversation of one open session: polls `events` by cursor while `run()` is running (the view runs it in a task that ends
/// when the person leaves the session), in pages of at most `ConversationModel.page`, and keeps the feed.
@MainActor @Observable public final class ConversationModel {
    public static let page = 200
    public static let intervalMilliseconds = 250
    public static let interval = Duration.milliseconds(intervalMilliseconds)

    public let sessionId: String
    public private(set) var rows: [FeedRow] = []
    /// Whether the first answer has arrived: until it does the view is loading, not empty.
    public private(set) var loaded = false
    /// Why the last poll failed, nil when it worked; the polling goes on, as the host may come back.
    public private(set) var failure: String?
    /// The `after` of the next request.
    public private(set) var cursor = 0
    /// What is typed in the box.
    public var draft = ""
    /// Whether the agent is answering (or waiting for an approval): the host refuses a message then, so the box queues it and the send button is Stop.
    public private(set) var busy = false
    /// The message typed while the agent answered: one at a time, sent when the turn ends.
    public private(set) var queued: String?
    /// The session's agent, as the host's list names it; empty until the first answer.
    public private(set) var agent = ""
    /// Whether the session's agent process runs; a session that is not live shows the closed notice and resumes when a message is sent.
    public private(set) var live = true
    /// Whether the session is in the archive: its transcript is read only and the box gives way to a notice with Resume.
    public private(set) var archived = false
    /// The message whose send or resume the host refused, for the banner's Try again; nil with no refusal or when it was not a send.
    public private(set) var refusedText: String?
    /// Why the last send, resume, stop or answer was refused, said under the box; nil when it worked.
    public private(set) var refusal: String?
    /// What the provider offers and the values it runs with, as the last `events` reply said: the pill follows this, never a request.
    public private(set) var options: [ChatOption] = []
    /// Why the last change of an option was refused, said in the panel; nil when it worked.
    public private(set) var optionRefusal: String?
    /// Counts the sends, so a poll that began before one does not tell the model the agent is idle when it is not.
    @ObservationIgnored private var sends = 0

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private var events: [ChatEvent] = []
    @ObservationIgnored private var streaming = ""
    /// The approvals the host still waits for, from the last reply.
    @ObservationIgnored private var pending: Set<String> = []
    /// The person's last message, which Try again sends again.
    @ObservationIgnored private var lastUserText: String?

    public init(
        host: ChatHost, sessionId: String, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.host = host
        self.sessionId = sessionId
        self.sleep = sleep
        self.log = log
    }

    /// Polls until the task is cancelled or `sleep` throws.
    public func run() async {
        repeat { await poll() } while (try? await sleep(Self.interval)) != nil
    }

    /// One round: reads pages until one is not full, then rebuilds the feed when something changed.
    public func poll() async {
        var changed = loaded == false
        let sendsBefore = sends
        do {
            var reply: ChatEvents
            repeat {
                reply = try await host.events(sessionId, after: cursor, limit: Self.page)
                // kept as each page comes, so a later page that fails does not lose the cursor's progress
                events += reply.events
                if let last = reply.events.last(where: { $0.kind == "user" }) { lastUserText = last.text }
                cursor = reply.cursor
                changed = changed || reply.events.isEmpty == false
            } while reply.events.count >= Self.page
            if let session = try await host.list(archived: false).first(where: { $0.id == sessionId }) {
                agent = session.agent
                live = session.live
                archived = false
            } else if let session = try await host.list(archived: true).first(where: { $0.id == sessionId }) {
                agent = session.agent
                live = false
                archived = true
            } else {
                live = false
                archived = false
            }
            changed = changed || reply.streaming != streaming
            streaming = reply.streaming
            changed = changed || reply.pending != pending
            pending = reply.pending
            loaded = true
            failure = nil
            options = reply.options
            if sends == sendsBefore, let state = reply.state { busy = state != .idle }
        } catch {
            let message = Self.words(error)
            if failure != message { log("session \(sessionId): \(message)") }
            failure = message
        }
        if changed { rows = chatFeed(events, streaming: streaming, pending: pending) }
        if busy == false, let next = queued {
            queued = nil
            await deliver(next)
        }
    }

    /// Enter or the send button: sends what is typed, or holds it as the queued message when the agent is answering (replacing
    /// the one that was held).
    public func submit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        if busy {
            queued = text
            draft = ""
            clearRefusal()
        } else {
            await deliver(text)
        }
    }

    /// A button of an approval card: passes the choice to the host and polls, so the card becomes the line once the host recorded the
    /// answer. A refusal (not pending any more, not one of the choices) is shown in words; the next poll draws what the host says.
    public func answer(_ approvalId: String, choice: String) async {
        do {
            try await host.answer(sessionId, approval: approvalId, choice: choice)
        } catch {
            refusedText = nil
            refusal = report(error, "answer the approval")
            return
        }
        clearRefusal()
        await poll()
    }

    /// Chooses a value in the options panel: asks the host and reads the session again, so the pill shows what the host says. A
    /// refusal is kept in words for the panel and nothing changes here.
    public func setOption(_ option: String, _ value: String) async {
        do {
            try await host.setOption(sessionId, option: option, value: value)
        } catch {
            optionRefusal = report(error, "change the option")
            return
        }
        optionRefusal = nil
        await poll()
    }

    /// Continue on the mark of a stopped turn.
    public func continueTurn() async { await deliver("Continue", refill: false) }

    /// Try again on a banner: the refused message again, or the person's last message when the turn failed.
    public func retry() async {
        if let text = refusedText ?? lastUserText { await deliver(text, refill: false) }
    }

    /// A first message whose send failed after the draft opened the session: the banner says why and Try again sends it.
    public func showRefusal(of text: String, _ reason: String) {
        refusal = reason
        refusedText = text
    }

    /// Drops the queued message.
    public func cancelQueued() { queued = nil }

    /// The Stop button: ends the turn; the queued message, if any, goes when the poll sees the agent idle.
    public func stop() async {
        do {
            try await host.interrupt(sessionId)
            clearRefusal()
        } catch {
            refusedText = nil
            refusal = report(error, "stop the turn")
        }
    }

    /// Sends the text, resuming the session first when the host's list says it is not live. A refusal is shown and the text goes back
    /// to the box when it came from there or from the queue (`refill`); on success the box is emptied unless the person has typed something else.
    private func deliver(_ text: String, refill: Bool = true) async {
        sends += 1
        // the box empties on Enter and not when the host has answered; a refusal puts the text back
        if refill, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        do {
            if try await host.list(archived: false).first(where: { $0.id == sessionId })?.live != true { try await host.resume(sessionId) }
            try await host.send(sessionId, text)
        } catch {
            refusal = report(error, "send the message")
            refusedText = text
            if refill, draft.isEmpty { draft = text }
            return
        }
        clearRefusal()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        sends += 1
        busy = true
        await poll()
    }

    private func clearRefusal() {
        refusal = nil
        refusedText = nil
    }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = Self.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("session \(sessionId): could not \(doing): \(message)")
        return message
    }

    nonisolated static func words(_ error: Error) -> String {
        switch error {
        case ControlError.closed: "The chat host is not answering"
        case ControlError.remote(let reason): reason
        default: "The chat host sent something that was not understood"
        }
    }
}
