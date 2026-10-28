import Foundation

// The Sessions home as plain values (docs/specs/sessions-in-the-app.md, "Sessions home"): what the filter keeps, the chips that say
// so, the line under the title and which empty state the page shows. The sort and the search are `sessionGroups`; the view draws these.

/// What the filter popover can tick: the session's status and its agent. Nothing ticked in a kind shows every value of it.
public struct SessionFilter: Equatable {
    public var statuses: Set<SessionState>
    public var agents: Set<String>

    public init(statuses: Set<SessionState> = [], agents: Set<String> = []) {
        self.statuses = statuses
        self.agents = agents
    }

    /// The statuses the popover offers: `done` is in the type but nothing produces it.
    public static let offeredStatuses: [SessionState] = [.waiting, .working, .idle]

    public var count: Int { statuses.count + agents.count }

    public func matches(_ row: SessionRow) -> Bool {
        (statuses.isEmpty || statuses.contains(row.state)) && (agents.isEmpty || agents.contains(row.agent))
    }

    /// One chip per ticked value: the statuses in the popover's order, then the agents by name.
    public var chips: [SessionChip] {
        Self.offeredStatuses.filter(statuses.contains).map(SessionChip.status) + agents.sorted().map(SessionChip.agent)
    }

    public mutating func remove(_ chip: SessionChip) {
        switch chip {
        case .status(let state): statuses.remove(state)
        case .agent(let name): agents.remove(name)
        }
    }
}

public enum SessionChip: Hashable {
    case status(SessionState)
    case agent(String)

    public var title: String {
        switch self {
        case .status(let state): state.title
        case .agent(let name): name
        }
    }
}

/// What the page shows for `rows`: the groups, the line under the title and, when there is nothing to list, which empty state.
public struct SessionsPage: Equatable {
    public var subtitle: String
    public var groups: [SessionGroup]
    public var emptyState: EmptyState?
}

/// Filters keep the rows they match, in the search's results too. The subtitle is "5 active · 1 waits for you" ("1 of 5 · …" with a
/// filter on, "2 results" with a search); it says nothing while there are no active sessions. With no search the page is empty
/// ("No sessions yet") when no session is active, and "No sessions match" when a search or a filter leaves nothing.
public func sessionsPage(
    _ rows: [SessionRow], by sort: SessionSort = .workspace, query: String = "", filter: SessionFilter = SessionFilter(), now: Date = Date(),
    calendar: Calendar = .current
) -> SessionsPage {
    let searching = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let active = rows.filter { $0.archived == false }
    let groups = sessionGroups(rows.filter(filter.matches), by: sort, query: query, now: now, calendar: calendar)
    let shown = groups.reduce(0) { $0 + $1.rows.count }
    let waiting = active.filter { $0.state == .waiting }.count
    let subtitle: String
    if searching {
        subtitle = shown == 1 ? "1 result" : "\(shown) results"
    } else if active.isEmpty {
        subtitle = ""
    } else {
        let count = filter.count == 0 ? "\(active.count) active" : "\(shown) of \(active.count)"
        subtitle = waiting == 0 ? count : "\(count) · \(waiting) \(waiting == 1 ? "waits" : "wait") for you"
    }
    let empty: EmptyState? = groups.isEmpty ? (searching == false && active.isEmpty ? .noSessions : .noSessionsMatch) : nil
    return SessionsPage(subtitle: subtitle, groups: groups, emptyState: empty)
}
