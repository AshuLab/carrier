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
/// The session's state (from its summary) comes with it, as the model needs to know whether the agent is answering; the pending
/// approvals and the options come too, and the slices that draw them read them.
public struct ChatEvents: Decodable, Equatable {
    public let events: [ChatEvent]
    public let cursor: Int
    public let streaming: String
    public let state: ChatSession.State?

    public init(events: [ChatEvent], cursor: Int, streaming: String = "", state: ChatSession.State? = nil) {
        self.events = events
        self.cursor = cursor
        self.streaming = streaming
        self.state = state
    }

    private enum CodingKeys: String, CodingKey { case events, cursor, streaming, session }
    private struct Summary: Decodable { let state: ChatSession.State }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        events = try values.decode([ChatEvent].self, forKey: .events)
        cursor = try values.decode(Int.self, forKey: .cursor)
        streaming = try values.decode(String.self, forKey: .streaming)
        state = try values.decodeIfPresent(Summary.self, forKey: .session)?.state
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
    /// A tool call or an approval, for now as one plain line each.
    case line(id: String, text: String)
    /// An error event, in red.
    case error(id: String, text: String)

    public var id: String {
        switch self {
        case .user(let id, _), .agent(let id, _, _), .turnEnd(let id, _), .line(let id, _), .error(let id, _): id
        }
    }
}

/// The rows the events make, in order, and then the message in progress when `streaming` has text. A call is one row at the place
/// where it started, completed by its end; an approval is one row at the place where it was asked, completed by the answer.
/// Options and anything else the host may add are not drawn.
public func chatFeed(_ events: [ChatEvent], streaming: String = "") -> [FeedRow] {
    var rows: [FeedRow] = []
    var started: [String: (row: Int, event: ChatEvent)] = [:]
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
            if let call = event.callId { started[call] = (rows.count, event) }
            rows.append(.line(id: id, text: callLine(event, ended: nil)))
        case "tool_end":
            if let call = event.callId, let start = started[call] {
                rows[start.row] = .line(id: rows[start.row].id, text: callLine(start.event, ended: event))
            } else {
                rows.append(.line(id: id, text: callLine(event, ended: event)))
            }
        case "approval":
            if let approval = event.approvalId { asked[approval] = (rows.count, event) }
            rows.append(.line(id: id, text: approvalLine(event, choice: nil)))
        case "approval_answered":
            guard let approval = event.approvalId, let question = asked[approval] else { continue }
            rows[question.row] = .line(id: rows[question.row].id, text: approvalLine(question.event, choice: event.choiceId))
        case "turn_end":
            if let text = closingLine(event, turnStart: turnStart) { rows.append(.turnEnd(id: id, text: text)) }
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

/// What was done, on what, and a short result: the first line of the output, or that the call failed.
private func callLine(_ start: ChatEvent, ended: ChatEvent?) -> String {
    var line = [start.tool ?? ended?.tool, start.arg ?? ended?.arg].compactMap { $0 }.joined(separator: " ")
    guard let ended else { return line }
    let first = ended.output?.first { $0.allSatisfy(\.isWhitespace) == false }.map { String($0.trimmingCharacters(in: .whitespaces).prefix(80)) }
    let result = [ended.status == "err" ? "failed" : nil, first].compactMap { $0 }.joined(separator: ": ")
    if result.isEmpty == false { line += " · " + result }
    return line
}

private func approvalLine(_ approval: ChatEvent, choice: String?) -> String {
    let what = [approval.tool, approval.arg].compactMap { $0 }.joined(separator: " ")
    guard let choice else { return "Approval for \(what): waiting for you" }
    let label = approval.choices?.first { $0.id == choice }?.label ?? choice
    return "Approval for \(what): \(label)"
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
    /// Why the last send, resume or stop was refused, said under the box; nil when it worked.
    public private(set) var refusal: String?
    /// Counts the sends, so a poll that began before one does not tell the model the agent is idle when it is not.
    @ObservationIgnored private var sends = 0

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private var events: [ChatEvent] = []
    @ObservationIgnored private var streaming = ""

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
                cursor = reply.cursor
                changed = changed || reply.events.isEmpty == false
            } while reply.events.count >= Self.page
            changed = changed || reply.streaming != streaming
            streaming = reply.streaming
            loaded = true
            failure = nil
            if sends == sendsBefore, let state = reply.state { busy = state != .idle }
        } catch {
            let message = Self.words(error)
            if failure != message { log("session \(sessionId): \(message)") }
            failure = message
        }
        if changed { rows = chatFeed(events, streaming: streaming) }
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
            refusal = nil
        } else {
            await deliver(text)
        }
    }

    /// Drops the queued message.
    public func cancelQueued() { queued = nil }

    /// The Stop button: ends the turn; the queued message, if any, goes when the poll sees the agent idle.
    public func stop() async {
        do {
            try await host.interrupt(sessionId)
            refusal = nil
        } catch {
            refusal = report(error, "stop the turn")
        }
    }

    /// Sends the text, resuming the session first when the host's list says it is not live. A refusal is shown and the text goes back
    /// to the box when it came from there or from the queue; on success the box is emptied unless the person has typed something else.
    private func deliver(_ text: String) async {
        sends += 1
        do {
            if try await host.list(archived: false).first(where: { $0.id == sessionId })?.live != true { try await host.resume(sessionId) }
            try await host.send(sessionId, text)
        } catch {
            refusal = report(error, "send the message")
            if draft.isEmpty { draft = text }
            return
        }
        refusal = nil
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        sends += 1
        busy = true
        await poll()
    }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = Self.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("session \(sessionId): could not \(doing): \(message)")
        return message
    }

    private static func words(_ error: Error) -> String {
        switch error {
        case ControlError.closed: "The chat host is not answering"
        case ControlError.remote(let reason): reason
        default: "The chat host sent something that was not understood"
        }
    }
}
