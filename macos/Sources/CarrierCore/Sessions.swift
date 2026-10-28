import Foundation

// The Sessions half of the sidebar as plain values (docs/specs/sidebar-home-sessions-carrier.md, Decisions). The sessions epic
// feeds them from the chat host (ChatSessions.swift). The views map them one to one.

public enum SessionState: Hashable { case working, waiting, idle, done }

public struct SessionRow: Equatable {
    public var id: String
    public var title: String
    /// The folder's name.
    public var workspace: String
    public var agent: String
    public var state: SessionState
    public var updatedAt: Date
    public var archived: Bool

    public init(id: String, title: String, workspace: String, agent: String, state: SessionState, updatedAt: Date, archived: Bool = false) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.agent = agent
        self.state = state
        self.updatedAt = updatedAt
        self.archived = archived
    }
}

public struct SessionGroup: Equatable {
    public var title: String
    public var rows: [SessionRow]
}

/// What the Sessions half reads. The + is disabled, with `cannotStartReason` as its tooltip, until the chat host's state says it can start.
public struct Sessions: Equatable {
    public var rows: [SessionRow] = []
    public var cannotStartReason: String? = hostNotRunning

    public init(rows: [SessionRow] = [], cannotStartReason: String? = hostNotRunning) {
        self.rows = rows
        self.cannotStartReason = cannotStartReason
    }

    public var canStart: Bool { cannotStartReason == nil }

    /// How many listed sessions wait for the person: archived ones are not counted.
    public var waiting: Int { rows.filter { $0.state == .waiting && $0.archived == false }.count }

    /// The accessible name of the orange count on the folded Sessions row, nil when nothing waits.
    public var waitingLabel: String? {
        switch waiting {
        case 0: nil
        case 1: "1 session waiting"
        default: "\(waiting) sessions waiting"
        }
    }
}

/// How the Sessions list is ordered.
public enum SessionSort: String, CaseIterable { case workspace, age, status }

/// The sessions in the order `by` gives, or, with a non-empty `query`, one group of the matches. By workspace: one group per
/// workspace ordered by name ignoring case. By age: Today, Yesterday, Last 7 days and Older, counted from the start of today in
/// `calendar`. By status: Waiting for you, Working, Idle and Done. Empty groups are left out, the rows of a group are newest first
/// and no archived row is listed. A query matches the title, the workspace and the agent ignoring case; the active matches come
/// newest first and then the archived ones newest first.
public func sessionGroups(
    _ rows: [SessionRow], by sort: SessionSort = .workspace, query: String = "", now: Date = Date(), calendar: Calendar = .current
) -> [SessionGroup] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty == false {
        let hits = rows.filter {
            [$0.title, $0.workspace, $0.agent].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let newest: (SessionRow, SessionRow) -> Bool = { $0.updatedAt > $1.updatedAt }
        let found = hits.filter { $0.archived == false }.sorted(by: newest) + hits.filter(\.archived).sorted(by: newest)
        return found.isEmpty ? [] : [SessionGroup(title: "Results", rows: found)]
    }
    let listed = rows.filter { $0.archived == false }
    func group(_ title: String, _ rows: [SessionRow]) -> SessionGroup? {
        rows.isEmpty ? nil : SessionGroup(title: title, rows: rows.sorted { $0.updatedAt > $1.updatedAt })
    }
    switch sort {
    case .workspace:
        return Dictionary(grouping: listed, by: \.workspace)
            .compactMap { group($0.key, $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    case .age:
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -7, to: today) ?? yesterday
        let buckets: [(String, (Date) -> Bool)] = [
            ("Today", { $0 >= today }),
            ("Yesterday", { $0 >= yesterday && $0 < today }),
            ("Last 7 days", { $0 >= week && $0 < yesterday }),
            ("Older", { $0 < week }),
        ]
        return buckets.compactMap { title, contains in group(title, listed.filter { contains($0.updatedAt) }) }
    case .status:
        let states: [(String, SessionState)] = [("Waiting for you", .waiting), ("Working", .working), ("Idle", .idle), ("Done", .done)]
        return states.compactMap { title, state in group(title, listed.filter { $0.state == state }) }
    }
}

/// How many of the sessions are archived, for the Archive row of the sidebar.
public func archivedCount(_ rows: [SessionRow]) -> Int { rows.filter(\.archived).count }

/// The age on the right of a row: "now", "5m", "3h", "2d".
public func sessionAge(_ updatedAt: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(updatedAt)))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(seconds / 60)m"
    case ..<86400: return "\(seconds / 3600)h"
    default: return "\(seconds / 86400)d"
    }
}
