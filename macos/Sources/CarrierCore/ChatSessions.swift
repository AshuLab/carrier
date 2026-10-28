import Foundation

// The chat host's sessions as the sidebar's values (docs/specs/sessions-in-the-app.md, "Sessions home" and "How it talks to the host"):
// the mapping to `SessionRow`, and the poller that keeps the list and the archived list current.

/// The rows for the sessions the host listed. The row's `workspace` is the title of its group: the last component of the base
/// folder (`workspace.base` for a session in a worktree, the folder otherwise), with the parent folder added when two different
/// base folders would have the same title. A session that is not live is idle, whatever the host last said.
public func sessionRows(_ sessions: [ChatSession]) -> [SessionRow] {
    func base(_ session: ChatSession) -> String { session.workspace?.base ?? session.folder }
    func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
    let clashing = Set(Dictionary(grouping: Set(sessions.map(base)), by: name).filter { $0.value.count > 1 }.keys)
    func title(_ path: String) -> String {
        clashing.contains(name(path)) ? "\(name(URL(fileURLWithPath: path).deletingLastPathComponent().path))/\(name(path))" : name(path)
    }
    return sessions.map { session in
        let state: SessionState = switch (session.live, session.state) {
        case (false, _), (_, .idle): .idle
        case (true, .working): .working
        case (true, .waitingApproval): .waiting
        }
        return SessionRow(
            id: session.id, title: session.title ?? "Untitled session", workspace: title(base(session)), agent: session.agent, state: state,
            updatedAt: Date(timeIntervalSince1970: Double(session.lastActiveAt) / 1000), archived: session.archived,
            branch: session.workspace?.branch
        )
    }
}

/// Asks the host for the sessions: `poll()` is called once a second and lists the active ones every time and the archived ones
/// when `archivedEvery` seconds have passed since they were last read. A host that does not answer the list gives no rows; one that
/// fails only on the archived list keeps the last archived rows it had.
public final class ChatSessionsPoller {
    private let host: ChatHost
    private let archivedEvery: TimeInterval
    private let now: () -> Date
    private let onChange: ([SessionRow]) -> Void
    private var archived: [ChatSession] = []
    private var archivedAt: Date?

    public init(host: ChatHost, archivedEvery: TimeInterval = 5, now: @escaping () -> Date = Date.init, onChange: @escaping ([SessionRow]) -> Void) {
        self.host = host
        self.archivedEvery = archivedEvery
        self.now = now
        self.onChange = onChange
    }

    public func poll() async {
        guard let active = try? await host.list(archived: false) else {
            archived = []
            archivedAt = nil
            return onChange([])
        }
        if archivedAt.map({ now().timeIntervalSince($0) >= archivedEvery }) ?? true, let listed = try? await host.list(archived: true) {
            archived = listed
            archivedAt = now()
        }
        onChange(sessionRows(active + archived))
    }
}
