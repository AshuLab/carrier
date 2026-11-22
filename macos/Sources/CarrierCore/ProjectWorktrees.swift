import Foundation

// The worktrees group of a project's page (docs/specs/projects.md, Scope 13): the host's `projectWorktrees` answer and the words of its rows.

/// A worktree of a project as the host lists it: under Carrier's worktrees folder, still on disk, with the session whose worktree it is.
public struct ProjectWorktree: Decodable, Equatable, Identifiable, Sendable {
    /// What is true of it, the first that applies: a session of it is open, it holds uncommitted changes, its session's pull request is merged, it has commits no other branch holds.
    public enum State: String, Decodable, Sendable { case sessionOpen, uncommitted, merged, notPushed, clean }

    public struct Session: Decodable, Equatable, Sendable {
        public let id: String
        public let title: String?

        public init(id: String, title: String? = nil) {
            self.id = id
            self.title = title
        }
    }

    public let path: String
    /// Nil when HEAD is detached.
    public let branch: String?
    /// Nil for a worktree whose session is gone.
    public let session: Session?
    /// Milliseconds since the epoch: the session's last activity, or the folder's modification time with no session.
    public let lastActiveAt: Double
    public let state: State

    public var id: String { path }

    public init(path: String, branch: String?, session: Session?, lastActiveAt: Double, state: State) {
        self.path = path
        self.branch = branch
        self.session = session
        self.lastActiveAt = lastActiveAt
        self.state = state
    }
}

/// The reply of `projectWorktrees`: the project's own folder with its branch, then its worktrees.
public struct ProjectWorktrees: Decodable, Equatable, Sendable {
    public struct Main: Decodable, Equatable, Sendable {
        public let path: String
        public let branch: String?

        public init(path: String, branch: String?) {
            self.path = path
            self.branch = branch
        }
    }

    public let main: Main
    public let worktrees: [ProjectWorktree]

    public init(main: Main, worktrees: [ProjectWorktree]) {
        self.main = main
        self.worktrees = worktrees
    }
}

/// One row of the Worktrees and disk group, in words.
public struct WorktreeRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// The branch, "Detached HEAD" when it has none.
    public let branch: String
    /// The session that made it ("No session" when it is gone); nil for the main clone.
    public let session: String?
    /// How long since it was last used ("3d"); nil for the main clone.
    public let age: String?
    /// Nil for the main clone.
    public let state: String?
    /// What `state` is said of, for the colour of its chip.
    public let kind: ProjectWorktree.State?
    /// What the folder takes on disk, as the host last measured it; nil when it has not (a worktree made since).
    public var bytes: Int?

    /// The size as the row says it: a dash until it is measured.
    public var size: String { bytes.map(formatDiskSize) ?? "—" }

    /// The row's second line: the session and the age, "Main clone" for the main one.
    public var detail: String { session.map { [$0, age].compactMap { $0 }.joined(separator: " · ") } ?? "Main clone" }
}

private func branchWords(_ branch: String?) -> String { branch ?? "Detached HEAD" }

/// The main clone first, then each worktree as the host listed it; `sizes` are the host's figures by folder.
public func worktreeRows(_ reply: ProjectWorktrees, sizes: [String: Int] = [:], now: Date, format: TimeFormat = .stored()) -> [WorktreeRow] {
    let main = WorktreeRow(id: reply.main.path, branch: branchWords(reply.main.branch), session: nil, age: nil, state: nil, kind: nil, bytes: sizes[reply.main.path])
    return [main] + reply.worktrees.map { worktree in
        WorktreeRow(
            id: worktree.path,
            branch: branchWords(worktree.branch),
            session: worktree.session.map { $0.title ?? "Untitled session" } ?? "No session",
            age: timeText(Date(timeIntervalSince1970: worktree.lastActiveAt / 1000), now: now, format: format),
            state: stateWords(worktree.state),
            kind: worktree.state,
            bytes: sizes[worktree.path]
        )
    }
}

private func stateWords(_ state: ProjectWorktree.State) -> String {
    switch state {
    case .sessionOpen: "Session open"
    case .uncommitted: "Uncommitted changes"
    case .merged: "Merged"
    case .notPushed: "Not pushed"
    case .clean: "Clean"
    }
}
