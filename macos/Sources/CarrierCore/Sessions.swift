import Foundation

// The Sessions half of the sidebar as plain values (docs/specs/sidebar-home-sessions-carrier.md, Decisions). The sessions epic
// feeds them from the chat host (ChatSessions.swift). The views map them one to one.

public enum SessionState: Hashable {
    case working, waiting, idle, done

    /// The group's title by state and the filter's wording.
    public var title: String {
        switch self {
        case .waiting: "Needs attention"
        case .working: "Working"
        case .idle: "Active"
        case .done: "Done"
        }
    }
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

    public init(
        id: String, title: String, workspace: String, agent: String, state: SessionState, updatedAt: Date, archived: Bool = false, branch: String? = nil,
        folder: String = "", base: String? = nil, providers: [String] = [], titled: Bool = true, kept: Bool = false, deleteAt: Date? = nil,
        lastMessage: String? = nil, turns: Int = 0, model: String? = nil, reportsActivity: Bool = false
    ) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.agent = agent
        self.state = state
        self.updatedAt = updatedAt
        self.archived = archived
        self.branch = branch
        self.folder = folder
        self.base = base ?? folder
        self.providers = providers
        self.titled = titled
        self.kept = kept
        self.deleteAt = deleteAt
        (self.lastMessage, self.turns, self.model, self.reportsActivity) = (lastMessage, turns, model, reportsActivity)
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
        return [SessionState.waiting, .working, .idle, .done].compactMap { state in newestFirst(state.title, listed.filter { $0.state == state }) }
    }
}

/// The archived sessions, and only those, in the age buckets of the Sessions list (Today, Yesterday, Last 7 days, Older), newest
/// first, empty buckets left out. A non-empty `query` keeps the buckets, filtered to the rows whose title, workspace or agent contain
/// it ignoring case.
public func archivedGroups(_ rows: [SessionRow], query: String = "", now: Date = Date(), calendar: Calendar = .current) -> [SessionGroup] {
    ageGroups(matching(rows.filter(\.archived), query), now: now, calendar: calendar)
}

func matching(_ rows: [SessionRow], _ query: String) -> [SessionRow] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return rows.filter { query.isEmpty || [$0.title, $0.workspace, $0.agent].contains { $0.localizedCaseInsensitiveContains(query) } }
}

private func newestFirst(_ title: String, _ rows: [SessionRow]) -> SessionGroup? {
    rows.isEmpty ? nil : SessionGroup(title: title, rows: rows.sorted { $0.updatedAt > $1.updatedAt })
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
    return buckets.compactMap { title, contains in newestFirst(title, rows.filter { contains($0.updatedAt) }) }
}

/// How many of the sessions are archived, for the Archive row of the sidebar.
public func archivedCount(_ rows: [SessionRow]) -> Int { rows.filter(\.archived).count }
