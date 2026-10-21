import Foundation

public struct EpicRef: Hashable {
    public var repo: String
    public var issue: Int

    public init(repo: String, issue: Int) {
        self.repo = repo
        self.issue = issue
    }
}

/// What one running session said so far. The cursor only moves forward and an event is kept once, in id order, so a repeated
/// or late reply changes nothing.
public struct Transcript: Equatable {
    public private(set) var events: [ExecEvent] = []
    /// The `after` of the next request.
    public private(set) var next = 0
    public private(set) var running = true
    public private(set) var structured = true

    public mutating func apply(_ reply: EventsReply) {
        var seen = Set(events.map(\.id))
        let fresh = reply.events.filter { seen.insert($0.id).inserted }
        if fresh.isEmpty == false { events = (events + fresh).sorted { $0.id < $1.id } }
        next = max(next, reply.next)
        running = reply.running
        structured = reply.structured
    }
}

/// The latest reply of each request for one epic: the model the views read.
public struct EpicData: Equatable {
    public var sessions: SessionsReply?
    public var epic: EpicReply?
    public var files: FilesReply?
    /// By execution id.
    public var transcripts: [String: Transcript] = [:]
}

/// What is on screen. The poller asks for nothing else.
public struct EpicFocus: Equatable {
    public var epic: EpicRef
    public var epicRunning: Bool
    public var filesTabVisible: Bool
    /// The session whose transcript is visible; nil when none is or it is not running.
    public var transcript: String?
    /// Sessions that are not running whose events are wanted once, for their counts.
    public var counting: [String]

    public init(epic: EpicRef, epicRunning: Bool, filesTabVisible: Bool = false, transcript: String? = nil, counting: [String] = []) {
        self.epic = epic
        self.epicRunning = epicRunning
        self.filesTabVisible = filesTabVisible
        self.transcript = transcript
        self.counting = counting
    }
}

/// Asks the engine for the data behind what is on screen, at the cadence of the PRD: `epic` every 3 s, `sessions` every 5 s
/// (both at once when the epic opens), `events` every 1 s while a running session's transcript is visible, `files` when the
/// tab opens and every 10 s while the epic runs. The events of the sessions to count are read once each, a page per call, after
/// the rest. Nothing with no focus (window closed) and nothing the engine did not advertise.
/// Call `poll` from the connection's thread; `show` may be called from any other, it takes effect at the next `poll`; `now` is the clock.
public final class EpicPoller {
    private enum Kind: CaseIterable {
        case epic, sessions, events, files

        var interval: TimeInterval {
            switch self {
            case .epic: return 3
            case .sessions: return 5
            case .events: return 1
            case .files: return 10
            }
        }
    }

    public private(set) var data: [EpicRef: EpicData] = [:]
    private var focus: EpicFocus?
    private let lock = NSLock()
    private var requested: [EpicFocus?] = []
    /// The sessions whose events were read to the end.
    private var counted: Set<String> = []
    private var lastAsked: [Kind: Date] = [:]
    private let now: () -> Date
    private let onUpdate: (EpicRef, EpicData) -> Void

    /// `onUpdate` is called only when a reply changed what is known about that epic.
    public init(now: @escaping () -> Date = Date.init, onUpdate: @escaping (EpicRef, EpicData) -> Void) {
        self.now = now
        self.onUpdate = onUpdate
    }

    /// Sets what is on screen: nil when the window is closed. What stops being shown is asked at once when it is shown again.
    public func show(_ next: EpicFocus?) {
        lock.lock()
        requested.append(next)
        lock.unlock()
    }

    private func apply(_ next: EpicFocus?) {
        guard next != focus else { return }
        if next?.epic != focus?.epic { lastAsked = [:] }
        if next?.filesTabVisible != true { lastAsked[.files] = nil }
        if next?.transcript != focus?.transcript { lastAsked[.events] = nil }
        focus = next
    }

    /// Sends what is due. A request the engine refuses is dropped until the next hello; a dead connection is thrown.
    public func poll(_ client: ControlClient) throws {
        lock.lock()
        let pending = requested
        requested = []
        lock.unlock()
        pending.forEach(apply)
        guard let focus else { return }
        let key = focus.epic
        let moment = now()
        for kind in Kind.allCases where isDue(kind, focus, moment) {
            lastAsked[kind] = moment
            do {
                switch kind {
                case .epic: if let reply = try client.epic(repo: key.repo, issue: key.issue) { update(key) { $0.epic = reply } }
                case .sessions: if let reply = try client.sessions(repo: key.repo, issue: key.issue) { update(key) { $0.sessions = reply } }
                case .files: if let reply = try client.files(repo: key.repo, issue: key.issue) { update(key) { $0.files = reply } }
                case .events:
                    let id = focus.transcript ?? ""
                    let after = data[key]?.transcripts[id]?.next ?? 0
                    if let reply = try client.events(executionId: id, after: after) { update(key) { $0.transcripts[id, default: Transcript()].apply(reply) } }
                }
            } catch ControlError.remote, ControlError.badLine, ControlError.timeout {
                continue
            }
        }
        try count(focus, client)
    }

    /// One page of the events of the first session still to count.
    private func count(_ focus: EpicFocus, _ client: ControlClient) throws {
        guard let id = focus.counting.first(where: { counted.contains($0) == false && $0 != focus.transcript }) else { return }
        let key = focus.epic
        do {
            let after = data[key]?.transcripts[id]?.next ?? 0
            guard let reply = try client.events(executionId: id, after: after) else { return }
            update(key) { $0.transcripts[id, default: Transcript()].apply(reply) }
            // a full page may be followed by another
            if reply.running == false && reply.events.count < 200 { counted.insert(id) }
        } catch ControlError.remote, ControlError.badLine, ControlError.timeout {
            counted.insert(id)
        }
    }

    private func isDue(_ kind: Kind, _ focus: EpicFocus, _ moment: Date) -> Bool {
        switch kind {
        case .epic, .sessions: break
        case .files: guard focus.filesTabVisible else { return false }
        case .events:
            guard let id = focus.transcript else { return false }
            if data[focus.epic]?.transcripts[id]?.running == false { return false }
        }
        guard let last = lastAsked[kind] else { return true }
        if kind == .files && focus.epicRunning == false { return false }
        return moment.timeIntervalSince(last) >= kind.interval
    }

    private func update(_ key: EpicRef, _ change: (inout EpicData) -> Void) {
        var current = data[key] ?? EpicData()
        let before = current
        change(&current)
        guard current != before || data[key] == nil else { return }
        data[key] = current
        onUpdate(key, current)
    }
}
