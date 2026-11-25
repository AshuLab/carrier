import Foundation

// The chat host's sessions as the sidebar's values (docs/specs/sessions-in-the-app.md, "Sessions home" and "How it talks to the host"):
// the mapping to `SessionRow`, and the poller that keeps the list and the archived list current.

/// The rows for the sessions the host listed. The row's `workspace` is the title of its group: the last component of the base
/// folder (`workspace.base` for a session in a worktree, the folder otherwise), with the parent folder added when two different
/// base folders would have the same title. A session that is not live is idle, whatever the host last said.
public func sessionRows(_ sessions: [ChatSession], bundle: Bundle? = nil, locale: Locale = .current) -> [SessionRow] {
    func base(_ session: ChatSession) -> String { session.workspace?.base ?? session.folder }
    let titles = groupTitles(Set(sessions.map(base)), projects: [])
    return sessions.map { session in
        let state: SessionState = switch (session.live, session.state) {
        // the host prepares it in the background: it shows at once, working, whether or not its agent has started
        case (_, .preparing): .working
        case (false, _), (_, .idle): .idle
        case (true, .working): .working
        case (true, .waitingApproval): .waiting
        }
        return SessionRow(
            id: session.id, title: session.title ?? Copy.chatSessionUntitled(bundle: bundle, locale: locale), workspace: titles[base(session)] ?? "", agent: session.agent, state: state,
            updatedAt: Date(timeIntervalSince1970: Double(session.lastActiveAt) / 1000), archived: session.archived,
            branch: session.workspace?.branch, branchFrom: session.workspace?.from, folder: session.folder, base: base(session), providers: session.providers, titled: session.title != nil,
            kept: session.kept, deleteAt: session.deleteAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            lastMessage: session.lastMessage, turns: session.turns, model: session.model, reportsActivity: session.reportsActivity,
            asleep: session.live == false && session.state != .preparing,
            diff: session.diff, pullRequest: session.pullRequest, background: session.background
        )
    }
}

/// What the Open menu of a conversation's title bar does.
public enum OpenAction: Equatable {
    case reveal(path: String)
    case copy(String)
}

public struct OpenItem: Equatable {
    public let title: String
    public let action: OpenAction
}

/// The title bar's name for a conversation: the session's title, "New session" while it has none.
public func conversationTitle(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    row.titled ? row.title : Copy.sessionsNew(bundle: bundle, locale: locale)
}

/// The line under the title: the workspace. Where the session works (a worktree or the folder itself) is the pill in the toolbar.
public func conversationSubtitle(_ row: SessionRow) -> String {
    row.branch == nil ? row.workspace : "\(row.workspace) · \(worktreeFolderName(row))"
}

/// The name of a session's folder: for a worktree what tells it from the project's other worktrees.
public func worktreeFolderName(_ row: SessionRow) -> String { (row.folder as NSString).lastPathComponent }

/// The Open menu: reveal the session's folder, copy its path and, for a worktree, copy its branch name.
public func openMenuItems(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> [OpenItem] {
    var items = [
        OpenItem(title: Copy.chatOpenRevealInFinder(bundle: bundle, locale: locale), action: .reveal(path: row.folder)),
        OpenItem(title: Copy.chatOpenCopyPath(bundle: bundle, locale: locale), action: .copy(row.folder)),
    ]
    if let branch = row.branch { items.append(OpenItem(title: Copy.chatOpenCopyBranchName(bundle: bundle, locale: locale), action: .copy(branch))) }
    return items
}

/// The title of the group of each base folder: the project's name when it is one, else the folder's name, with the parent folder added when two
/// different base folders would have the same title.
func groupTitles(_ bases: Set<String>, projects: [ProjectRow]) -> [String: String] {
    func name(_ path: String) -> String { projectIdentity(path: path, in: projects).title }
    let clashing = Set(Dictionary(grouping: bases, by: name).filter { $0.value.count > 1 }.keys)
    return Dictionary(uniqueKeysWithValues: bases.map { path in
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return (path, clashing.contains(name(path)) ? "\(URL(fileURLWithPath: parent).lastPathComponent)/\(name(path))" : name(path))
    })
}

/// `rows` with the title of each group taken from `projects`: a project's name replaces its folder's.
public func retitled(_ rows: [SessionRow], projects: [ProjectRow]) -> [SessionRow] {
    let titles = groupTitles(Set(rows.map(\.base)), projects: projects)
    return rows.map { row in
        var row = row
        row.workspace = titles[row.base] ?? row.workspace
        return row
    }
}

/// Keeps the sidebar's rows current from the host's updates (`ChatHost.sessionUpdates`): the active and the archived sessions as rows, and, once
/// both lists were read in one cycle, the ids the host knows (what the terminals' pruning compares with). A host that did not answer changes
/// nothing: the rows stay as they were, and with them what the person has seen.
public final class ChatSessionsPoller {
    private let host: ChatHost
    private let onAuthoritativeSessionIds: (Set<String>) -> Void
    private let onChange: ([SessionRow]) -> Void

    public init(host: ChatHost, onAuthoritativeSessionIds: @escaping (Set<String>) -> Void = { _ in }, onChange: @escaping ([SessionRow]) -> Void) {
        self.host = host
        self.onAuthoritativeSessionIds = onAuthoritativeSessionIds
        self.onChange = onChange
    }

    /// Follows the updates until the task is cancelled.
    public func run() async {
        for await update in await host.sessionUpdates() {
            guard update.stale == false else { continue }
            let combined = update.active + update.archived
            onChange(sessionRows(combined))
            if update.authoritative { onAuthoritativeSessionIds(Set(combined.map(\.id))) }
        }
    }
}
