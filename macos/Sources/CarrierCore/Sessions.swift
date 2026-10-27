import Foundation

// The Sessions half of the sidebar as plain values (docs/specs/sidebar-home-sessions-carrier.md, Decisions). The sessions epic
// feeds them; until then the list is empty, or a dev fixture with `--fixture`. The views map them one to one.

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

/// What the Sessions half reads. `canStart` is false until the sessions epic sets it: the + is disabled while it is.
public struct Sessions: Equatable {
    public var rows: [SessionRow] = []
    public var canStart = false

    public init(rows: [SessionRow] = [], canStart: Bool = false) {
        self.rows = rows
        self.canStart = canStart
    }

    /// Why the + is disabled, for its tooltip.
    public static let cannotStartReason = "Starting sessions is not available yet"
}

public enum SessionSort: String, CaseIterable { case workspace, age, status }

/// The sessions in the order `by` gives, or, with a non-empty `query`, one group of the matches. The workspace order: one group per
/// workspace ordered by name ignoring case, each with its rows newest first, and no archived row. A query matches the title, the
/// workspace and the agent ignoring case; the active matches come newest first and then the archived ones newest first.
/// `now` and `calendar` are for the age buckets.
public func sessionGroups(
    _ rows: [SessionRow], by: SessionSort = .workspace, query: String = "", now: Date = Date(), calendar: Calendar = .current
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
    // ponytail: only the workspace order exists; the age and status orders arrive with #415
    let byWorkspace = Dictionary(grouping: rows.filter { $0.archived == false }, by: \.workspace)
    return byWorkspace
        .map { SessionGroup(title: $0.key, rows: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

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

/// The dev fixture: sample sessions in several workspaces, one of each state and archived ones, for `--fixture`.
public func sampleSessions(now: Date) -> [SessionRow] {
    func row(_ id: String, _ title: String, _ workspace: String, _ agent: String, _ state: SessionState, minutesAgo: Int, archived: Bool = false) -> SessionRow {
        SessionRow(id: id, title: title, workspace: workspace, agent: agent, state: state, updatedAt: now.addingTimeInterval(Double(-60 * minutesAgo)), archived: archived)
    }
    return [
        row("s1", "Add a retry to the sync worker", "carrier", "Claude", .working, minutesAgo: 2),
        row("s2", "Which migration should go first?", "carrier", "Codex", .waiting, minutesAgo: 14),
        row("s3", "Explore the pricing page layout", "web", "Claude", .idle, minutesAgo: 190),
        row("s4", "Fix the flaky login test", "web", "Claude", .done, minutesAgo: 60 * 30),
        row("s5", "A very long title that goes on and on about renaming every helper in the whole repository", "Dotfiles", "Antigravity", .idle, minutesAgo: 60 * 24 * 4),
        row("s6", "Old spike on the cache", "web", "Codex", .done, minutesAgo: 60 * 24 * 20, archived: true),
        row("s7", "Rename the config keys", "carrier", "Claude", .done, minutesAgo: 60 * 24 * 9, archived: true),
    ]
}
