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
/// or late reply changes nothing. The items are built as the events arrive: events past the newest one are appended and only
/// they are processed; one older than the newest (rare) rebuilds the items.
public struct Transcript: Equatable {
    public private(set) var events: [ExecEvent] = []
    /// What the view draws of the main session (events with no agent id), kept in step with `events`.
    public var items: [TranscriptItem] { builder.items }
    /// How many events the items have processed so far: an append adds its own count, a rebuild adds them all.
    public var work: Int { lanes.reduce(builder.work) { $0 + $1.builder.work } }
    /// One per subagent that has events, in order of appearance (Lanes.swift).
    var lanes: [LaneState] = []
    private var laneIndex: [String: Int] = [:]
    /// The `after` of the next request.
    public private(set) var next = 0
    public private(set) var running = true
    public private(set) var structured = true
    /// The summarised output lines, read only while the harness has no parser yet (`structured` false).
    public internal(set) var tail: [String] = []
    private var seen = Set<Int>()
    private var builder = TranscriptBuilder()

    public init() {}

    public mutating func apply(_ reply: EventsReply) {
        let fresh = reply.events.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        if let first = fresh.first {
            if let last = events.last, first.id < last.id {
                events = (events + fresh).sorted { $0.id < $1.id }
                builder.reset()
                for index in lanes.indices { lanes[index].reset() }
                for event in events { route(event) }
            } else {
                events += fresh
                for event in fresh { route(event) }
            }
        }
        next = max(next, reply.next)
        running = reply.running
        structured = reply.structured
    }

    private mutating func route(_ event: ExecEvent) {
        guard let agent = event.agentId else { return builder.add(event) }
        if laneIndex[agent] == nil {
            laneIndex[agent] = lanes.count
            lanes.append(LaneState(agentId: agent))
        }
        lanes[laneIndex[agent]!].add(event)
    }
}

/// The latest reply of each request for one epic: the model the views read.
public struct EpicData: Equatable {
    public var sessions: SessionsReply?
    public var epic: EpicReply?
    public var files: FilesReply?
    /// By execution id.
    public var transcripts: [String: Transcript] = [:]
    /// The fragment of each file row that was opened, asked once and kept.
    public var fragments: [OpenFile: FileFragment] = [:]
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
    /// The file rows open in the Files changed tab: each is asked for its fragment once.
    public var openFiles: Set<OpenFile>

    public init(
        epic: EpicRef, epicRunning: Bool, filesTabVisible: Bool = false, transcript: String? = nil, counting: [String] = [],
        openFiles: Set<OpenFile> = []
    ) {
        self.epic = epic
        self.epicRunning = epicRunning
        self.filesTabVisible = filesTabVisible
        self.transcript = transcript
        self.counting = counting
        self.openFiles = openFiles
    }
}

/// Asks the engine for the data behind what is on screen, at the cadence of the PRD: `epic` every 3 s, `sessions` every 5 s
/// (both at once when the epic opens), `events` every 1 s while a running session's transcript is visible, `files` when the
/// tab opens and every 10 s while the epic runs, and the fragment of a file row once, when it is first opened. The events of the sessions to count are read once each, newest session first,
/// a page per request and up to `pagesPerPoll` requests per poll, after the rest. Nothing with no focus (window closed) and nothing the engine did not advertise.
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

    /// How many pages of events one poll may read for the sessions to count: the socket is local and a page takes milliseconds, so
    /// the counts of an epic with many sessions arrive in a poll or two instead of one session per second.
    static let pagesPerPoll = 8

    public private(set) var data: [EpicRef: EpicData] = [:]
    private var focus: EpicFocus?
    private let lock = NSLock()
    private var requested: [EpicFocus?] = []
    /// The sessions whose events were read to the end.
    private var counted: Set<String> = []
    private var lastAsked: [Kind: Date] = [:]
    private let now: () -> Date
    private let onUpdate: (EpicRef, EpicData) -> Void
    private let onCapabilities: (Set<ControlClient.Capability>) -> Void
    private var capabilities: Set<ControlClient.Capability> = []

    /// `onUpdate` is called only when a reply changed what is known about that epic; `onCapabilities` when the hello of the connection
    /// being polled lists something other than the last one did.
    public init(
        now: @escaping () -> Date = Date.init, onCapabilities: @escaping (Set<ControlClient.Capability>) -> Void = { _ in },
        onUpdate: @escaping (EpicRef, EpicData) -> Void
    ) {
        self.now = now
        self.onCapabilities = onCapabilities
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
        if client.capabilities != capabilities {
            capabilities = client.capabilities
            onCapabilities(capabilities)
        }
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
                    if let reply = try client.events(executionId: id, after: after) {
                        update(key) { $0.transcripts[id, default: Transcript()].apply(reply) }
                        if reply.structured == false { try tail(id, key, client) }
                    }
                }
            } catch ControlError.remote, ControlError.badLine, ControlError.timeout {
                continue
            }
        }
        try fragments(focus, client)
        for _ in 0..<Self.pagesPerPoll {
            guard try count(focus, client) else { break }
        }
    }

    /// The open file rows that have no fragment yet. A merged slice and a fix round have fixed ends: one reply, or one failure, is kept.
    private func fragments(_ focus: EpicFocus, _ client: ControlClient) throws {
        let key = focus.epic
        for file in focus.openFiles where data[key]?.fragments[file] == nil {
            do {
                guard let reply = try client.fileDiff(repo: key.repo, issue: key.issue, section: file.section, path: file.path) else { return }
                update(key) { $0.fragments[file] = fileFragment(reply) }
            } catch ControlError.remote, ControlError.badLine, ControlError.timeout {
                update(key) { $0.fragments[file] = .failed }
            }
        }
    }

    /// One page of the events of the first session still to count; false when there is none left.
    private func count(_ focus: EpicFocus, _ client: ControlClient) throws -> Bool {
        guard let id = focus.counting.first(where: { counted.contains($0) == false && $0 != focus.transcript }) else { return false }
        let key = focus.epic
        do {
            let after = data[key]?.transcripts[id]?.next ?? 0
            guard let reply = try client.events(executionId: id, after: after) else { return false }
            update(key) { $0.transcripts[id, default: Transcript()].apply(reply) }
            if reply.structured == false { try tail(id, key, client) }
            // a full page may be followed by another
            if reply.running == false && reply.events.count < 200 { counted.insert(id) }
        } catch ControlError.remote, ControlError.badLine, ControlError.timeout {
            // given up on: the session shows what it has (nothing) and not a loading that never ends
            counted.insert(id)
            update(key) { if $0.transcripts[id] == nil { $0.transcripts[id] = Transcript() } }
        }
        return true
    }

    /// The latest summarised lines of a session whose harness has no events.
    private func tail(_ id: String, _ key: EpicRef, _ client: ControlClient) throws {
        do {
            let lines = try client.tail(executionId: id, lines: 60)
            update(key) { $0.transcripts[id, default: Transcript()].tail = lines }
        } catch ControlError.remote, ControlError.badLine, ControlError.timeout {}
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
