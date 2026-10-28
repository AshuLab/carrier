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
/// The session's summary, the pending approvals and the options come with it too; the slices that draw them read them.
public struct ChatEvents: Decodable, Equatable {
    public let events: [ChatEvent]
    public let cursor: Int
    public let streaming: String

    public init(events: [ChatEvent], cursor: Int, streaming: String = "") {
        self.events = events
        self.cursor = cursor
        self.streaming = streaming
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
    /// An approval, for now as one plain line.
    case line(id: String, text: String)
    /// An error event, in red.
    case error(id: String, text: String)

    public var id: String {
        switch self {
        case .user(let id, _), .agent(let id, _, _), .turnEnd(let id, _), .tools(let id, _), .line(let id, _), .error(let id, _): id
        }
    }
}

/// The rows the events make, in order, and then the message in progress when `streaming` has text. Consecutive calls are one row
/// at the place where the first started, each completed by its end (a turn that ends first stops the calls still going); an
/// approval is one row at the place where it was asked, completed by the answer.
/// Options and anything else the host may add are not drawn.
public func chatFeed(_ events: [ChatEvent], streaming: String = "") -> [FeedRow] {
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
            rows.append(.line(id: id, text: approvalLine(event, choice: nil)))
        case "approval_answered":
            guard let approval = event.approvalId, let question = asked[approval] else { continue }
            rows[question.row] = .line(id: rows[question.row].id, text: approvalLine(question.event, choice: event.choiceId))
        case "turn_end":
            for spot in going.values {
                guard case .tools(let group, var calls) = rows[spot.row] else { continue }
                calls.calls[spot.call].stop()
                rows[spot.row] = .tools(id: group, calls)
            }
            going = [:]
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
        } catch {
            let message = Self.words(error)
            if failure != message { log("session \(sessionId): \(message)") }
            failure = message
        }
        if changed { rows = chatFeed(events, streaming: streaming) }
    }

    private static func words(_ error: Error) -> String {
        switch error {
        case ControlError.closed: "The chat host is not answering"
        case ControlError.remote(let reason): reason
        default: "The chat host sent something that was not understood"
        }
    }
}
