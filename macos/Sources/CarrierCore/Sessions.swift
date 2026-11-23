import Foundation

// The Sessions half of the sidebar as plain values (docs/specs/sidebar-home-sessions-carrier.md, Decisions). The sessions epic
// feeds them from the chat host (ChatSessions.swift). The views map them one to one.

public enum SessionState: Hashable {
    case working, waiting, idle, done
}

/// What a session is for the person, in the groups of "By state" and in the filter: the five ways of being in their hands or out of them.
/// A session that asks for a permission or an answer is blocked (`needsYou`); one that answered and has not been opened since is `unread`;
/// one that was seen and is open in the host is `idle`; one whose agent the host closed (nobody asked about it for ten minutes, or the host
/// restarted) is `asleep` and wakes where it left off when a message is sent.
public enum SessionStatus: CaseIterable, Hashable {
    case needsYou, working, unread, idle, asleep

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .unread: "Unread"
        case .idle: "Idle"
        case .asleep: "Asleep"
        }
    }
}

/// The lines a session changed, counted by git on this Mac.
public struct SessionDiff: Equatable, Decodable {
    public var added: Int
    public var removed: Int

    public init(added: Int, removed: Int) { (self.added, self.removed) = (added, removed) }
}

/// A pull request's state on GitHub, and how its checks went (nil when it has none).
public enum PullRequestState: String, Equatable, Decodable { case open, draft, merged, closed }
public enum PullRequestChecks: String, Equatable, Decodable { case passing, failing, pending }

/// The pull request of the branch a session works on.
public struct SessionPullRequest: Equatable, Decodable {
    public var number: Int
    public var url: String
    public var state: PullRequestState
    public var checks: PullRequestChecks?

    public init(number: Int, url: String, state: PullRequestState, checks: PullRequestChecks? = nil) { (self.number, self.url, self.state, self.checks) = (number, url, state, checks) }
}

extension SessionPullRequest {
    /// How its chip is tinted: green while it is open (and its checks are not failing), red when its checks fail, purple once merged, quiet
    /// for a draft or a closed one.
    public enum Tone: Equatable { case open, failing, merged, quiet }

    public var tone: Tone {
        switch state {
        case .merged: .merged
        case .closed, .draft: .quiet
        case .open: checks == .failing ? .failing : .open
        }
    }

    /// What its chip says: "#983 · Draft", "#412 · ✓", "#979 · CI ✕", "#412 · CI running", "#88 · Merged"; the number alone while it is open and has no checks.
    public var chipText: String {
        switch state {
        case .merged: "#\(number) · Merged"
        case .closed: "#\(number) · Closed"
        case .draft: "#\(number) · Draft"
        case .open:
            switch checks {
            case .passing?: "#\(number) · ✓"
            case .failing?: "#\(number) · CI ✕"
            case .pending?: "#\(number) · CI running"
            case nil: "#\(number)"
            }
        }
    }

    /// For VoiceOver: "Pull request 412, open, checks passing".
    public var spoken: String {
        let checks: String? = switch checks {
        case .passing?: "checks passing"
        case .failing?: "checks failing"
        case .pending?: "checks running"
        case nil: nil
        }
        return (["Pull request \(number)", state.rawValue] + [checks]).compactMap { $0 }.joined(separator: ", ")
    }
}

/// Something the agent started and waits for after its turn ended: a command, a monitor, a subagent.
public struct BackgroundTask: Equatable, Decodable {
    public var id: String
    public var kind: String
    public var description: String
    /// When the host first saw it; nil from a host that does not say.
    public var startedAt: Date?

    public init(id: String, kind: String, description: String, startedAt: Date? = nil) { (self.id, self.kind, self.description, self.startedAt) = (id, kind, description, startedAt) }

    private enum CodingKeys: String, CodingKey { case id, kind, description, startedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(String.self, forKey: .kind)
        description = try values.decode(String.self, forKey: .description)
        startedAt = try values.decodeIfPresent(Double.self, forKey: .startedAt).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// What names it: what the agent said it was, else its kind.
    public var name: String { description.isEmpty ? kind : description }
}

/// The tasks the card's line names, one at a time: they take their turn each `tick` (the line rolls from one to the next), and none is no line.
public func backgroundWords(_ tasks: [BackgroundTask], tick: Int) -> String? {
    guard tasks.isEmpty == false else { return nil }
    return "Waiting on \(tasks[abs(tick) % tasks.count].name)"
}

/// How many they are, after the words, when there is more than one: "· 3 tasks".
public func backgroundCount(_ tasks: [BackgroundTask]) -> String? { tasks.count > 1 ? "· \(tasks.count) tasks" : nil }

/// What a session whose turn ended waits for, in a line: "Waiting on pnpm build", "Waiting on pnpm build and 2 more"; nil when it waits for nothing.
public func waitingOnText(_ tasks: [BackgroundTask]) -> String? {
    guard let first = tasks.first else { return nil }
    let name = first.name
    return tasks.count == 1 ? "Waiting on \(name)" : "Waiting on \(name) and \(tasks.count - 1) more"
}

public struct SessionRow: Equatable {
    public var id: String
    public var title: String
    /// The folder's name.
    public var workspace: String
    public var agent: String
    public var state: SessionState
    public var updatedAt: Date
    public var archived: Bool
    /// The branch of a session in a worktree, nil for one in a plain folder.
    public var branch: String?
    /// For a worktree, the branch it was cut from.
    public var branchFrom: String?
    /// Where the session works: the worktree's path, or the folder.
    public var folder: String
    /// The folder the session is grouped under: the repository's folder for a session in a worktree, `folder` otherwise.
    public var base: String
    /// The providers the session has worked with, as the names of their icons; one today, and the row has room for more.
    public var providers: [String]
    /// Whether the host has a title for it; `title` says "Untitled session" when it has none.
    public var titled: Bool
    /// An archived session the clock spares because its worktree holds unsaved work.
    public var kept: Bool
    /// When the clock deletes an archived session; nil when it will not.
    public var deleteAt: Date?
    /// What the agent last wrote, on one line; nil before it answered.
    public var lastMessage: String?
    /// The turns that finished, and the model of the last.
    public var turns: Int
    public var model: String?
    /// Whether the host said anything of how the session went; one that does not leaves all three empty.
    public var reportsActivity: Bool
    /// Whether the host closed the session's agent: it is idle and wakes when a message is sent.
    public var asleep: Bool
    /// Whether it answered and the person has not opened it since; the app sets it (`SessionSeen`), the host does not know.
    public var unread: Bool
    /// The lines it changed, nil when none or when the host has not read them (yet, or at all).
    public var diff: SessionDiff?
    /// The pull request of its branch, nil while none is known.
    public var pullRequest: SessionPullRequest?
    /// What the agent waits for after its turn ended. The session is not idle while it has some: it is working, in the background.
    public var background: [BackgroundTask]
    /// Where the lists place it while it works: the time its turn began, held still (`WorkingOrder`), and nil otherwise, when its last activity does.
    public var orderedAt: Date?

    /// What the lists order and bucket the session by.
    public var sortedAt: Date { orderedAt ?? updatedAt }

    /// Whether the agent is busy: it works, or its turn ended and it waits for something it started. What shows as working, and what cannot be archived.
    public var isWorking: Bool { state == .working || (state != .waiting && background.isEmpty == false) }

    /// What it is for the person; see `SessionStatus`.
    public var status: SessionStatus {
        switch state {
        case .waiting: .needsYou
        case .working: .working
        case .idle, .done: background.isEmpty == false ? .working : unread ? .unread : asleep ? .asleep : .idle
        }
    }

    public init(
        id: String, title: String, workspace: String, agent: String, state: SessionState, updatedAt: Date, archived: Bool = false, branch: String? = nil, branchFrom: String? = nil,
        folder: String = "", base: String? = nil, providers: [String] = [], titled: Bool = true, kept: Bool = false, deleteAt: Date? = nil,
        lastMessage: String? = nil, turns: Int = 0, model: String? = nil, reportsActivity: Bool = false, asleep: Bool = false, unread: Bool = false,
        diff: SessionDiff? = nil, pullRequest: SessionPullRequest? = nil, background: [BackgroundTask] = [], orderedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.agent = agent
        self.state = state
        self.updatedAt = updatedAt
        self.archived = archived
        self.branch = branch
        self.branchFrom = branchFrom
        self.folder = folder
        self.base = base ?? folder
        self.providers = providers
        self.titled = titled
        self.kept = kept
        self.deleteAt = deleteAt
        (self.lastMessage, self.turns, self.model, self.reportsActivity) = (lastMessage, turns, model, reportsActivity)
        (self.asleep, self.unread) = (asleep, unread)
        (self.diff, self.pullRequest, self.background) = (diff, pullRequest, background)
        self.orderedAt = orderedAt
    }
}

/// Holds still the place of the sessions that work. The host moves a session's last activity with every event of its agent, so two that work
/// at once would swap places over and over in lists that put the newest first. While a session works (or waits for the person, or for what
/// it started) its place is the time its turn began, as the app first saw it; when it stops it has its last activity again and takes its place
/// once. The same start as `WorkingClock`'s.
public struct WorkingOrder: Equatable {
    private var began: [String: Date] = [:]

    public init() {}

    /// Sets `orderedAt` of the rows that work and forgets the sessions that stopped or went.
    public mutating func apply(to rows: inout [SessionRow]) {
        var next: [String: Date] = [:]
        for index in rows.indices where rows[index].archived == false {
            let id = rows[index].id
            // a session that waits for the person keeps the place it had, and one that was never seen working has none to keep
            guard rows[index].isWorking || (rows[index].state == .waiting && began[id] != nil) else { continue }
            let start = began[id] ?? rows[index].updatedAt
            next[id] = start
            rows[index].orderedAt = start
        }
        began = next
    }
}

public struct SessionGroup: Equatable {
    public var title: String
    public var rows: [SessionRow]
}

/// What the Sessions half reads. The + is always on: a draft that finds no chat host starts it.
public struct Sessions: Equatable {
    public var rows: [SessionRow] = []

    public init(rows: [SessionRow] = []) {
        self.rows = rows
    }

    /// How many sessions are open, every one that is not archived: the badge on the Sessions row.
    public var open: Int { rows.filter { $0.archived == false }.count }

    /// The accessible name of that badge: "1 open session", "5 open sessions".
    public var openLabel: String { open == 1 ? "1 open session" : "\(open) open sessions" }

    /// How many listed sessions wait for the person: archived ones are not counted.
    public var waiting: Int { rows.filter { $0.state == .waiting && $0.archived == false }.count }
}

/// How the Sessions list is ordered.
public enum SessionSort: String, CaseIterable { case workspace, age, status }

/// The sessions in the order `by` gives. By workspace: one group per workspace ordered by name ignoring case. By age: Today,
/// Yesterday, Last 7 days and Older, counted from the start of today in `calendar`. By state: Needs attention, Working, Active and
/// Done. Empty groups are left out, the rows of a group are newest first and no archived row is listed, searching included. A
/// non-empty `query` keeps the groups of that order, filtered to the rows whose title, workspace or agent contain it ignoring case.
/// The `pinned` rows leave their groups for a "Pinned" one first.
public func sessionGroups(
    _ rows: [SessionRow], by sort: SessionSort = .workspace, query: String = "", pinned: Set<String> = [], now: Date = Date(), calendar: Calendar = .current
) -> [SessionGroup] {
    let active = matching(rows.filter { $0.archived == false }, query)
    let pins = newestFirst("Pinned", active.filter { pinned.contains($0.id) })
    let listed = active.filter { pinned.contains($0.id) == false }
    return (pins.map { [$0] } ?? []) + ordered(listed, by: sort, now: now, calendar: calendar)
}

private func ordered(_ listed: [SessionRow], by sort: SessionSort, now: Date, calendar: Calendar) -> [SessionGroup] {
    switch sort {
    case .workspace:
        return Dictionary(grouping: listed, by: \.workspace)
            .compactMap { newestFirst($0.key, $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    case .age:
        return ageGroups(listed, now: now, calendar: calendar)
    case .status:
        return SessionStatus.allCases.compactMap { status in newestFirst(status.title, listed.filter { $0.status == status }) }
    }
}

/// The archived sessions, and only those, in the age buckets of the Sessions list (Today, Yesterday, Last 7 days, Older) or, by workspace,
/// one group per workspace, newest first, empty groups left out. A non-empty `query` keeps the groups, filtered to the rows whose
/// title, workspace or agent contain it ignoring case.
public func archivedGroups(
    _ rows: [SessionRow], by sort: SessionSort = .age, query: String = "", now: Date = Date(), calendar: Calendar = .current
) -> [SessionGroup] {
    ordered(matching(rows.filter(\.archived), query), by: sort, now: now, calendar: calendar)
}

func matching(_ rows: [SessionRow], _ query: String) -> [SessionRow] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return rows.filter { query.isEmpty || [$0.title, $0.workspace, $0.agent].contains { $0.localizedCaseInsensitiveContains(query) } }
}

private func newestFirst(_ title: String, _ rows: [SessionRow]) -> SessionGroup? {
    rows.isEmpty ? nil : SessionGroup(title: title, rows: rows.sorted { $0.sortedAt > $1.sortedAt })
}

/// Today, Yesterday, Last 7 days and Older, counted from the start of today in `calendar`.
private func ageGroups(_ rows: [SessionRow], now: Date, calendar: Calendar) -> [SessionGroup] {
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    let week = calendar.date(byAdding: .day, value: -7, to: today) ?? yesterday
    let buckets: [(String, (Date) -> Bool)] = [
        ("Today", { $0 >= today }),
        ("Yesterday", { $0 >= yesterday && $0 < today }),
        ("Last 7 days", { $0 >= week && $0 < yesterday }),
        ("Older", { $0 < week }),
    ]
    return buckets.compactMap { title, contains in newestFirst(title, rows.filter { contains($0.sortedAt) }) }
}

/// How many of the sessions are archived, for the Archive row of the sidebar.
public func archivedCount(_ rows: [SessionRow]) -> Int { rows.filter(\.archived).count }
