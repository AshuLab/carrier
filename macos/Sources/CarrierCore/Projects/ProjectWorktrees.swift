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
        /// What the project's own folder would lose in the Trash: `uncommitted`, `notPushed` (commits no remote holds) or `clean`; nil from a host that does not say.
        public let state: ProjectWorktree.State?

        public init(path: String, branch: String?, state: ProjectWorktree.State? = nil) {
            self.path = path
            self.branch = branch
            self.state = state
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

    /// Whether the row has a Remove button: every worktree does, the main clone does not.
    public var hasRemove: Bool { kind != nil }
    /// Why its Remove button is disabled: only while its session is open. An uncommitted change is refused by the host, with its words, when the button is pressed.
    public func removeBlockedBy(bundle: Bundle? = nil, locale: Locale = .current) -> String? { kind == .sessionOpen ? worktreeOpenWords(bundle: bundle, locale: locale) : nil }

    /// The row's second line: the session and the age, "Main clone" for the main one.
    public func detail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        session.map { [$0, age].compactMap { $0 }.joined(separator: " · ") } ?? Copy.projectsWorktreeMainClone(bundle: bundle, locale: locale)
    }
}

private func branchWords(_ branch: String?, bundle: Bundle?, locale: Locale) -> String { branch ?? Copy.projectsWorktreeDetached(bundle: bundle, locale: locale) }

/// The main clone first, then each worktree as the host listed it; `sizes` are the host's figures by folder.
public func worktreeRows(
    _ reply: ProjectWorktrees, sizes: [String: Int] = [:], now: Date, format: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current
) -> [WorktreeRow] {
    let main = WorktreeRow(id: reply.main.path, branch: branchWords(reply.main.branch, bundle: bundle, locale: locale), session: nil, age: nil, state: nil, kind: nil, bytes: sizes[reply.main.path])
    return [main] + reply.worktrees.map { worktree in
        WorktreeRow(
            id: worktree.path,
            branch: branchWords(worktree.branch, bundle: bundle, locale: locale),
            session: worktree.session.map { $0.title ?? Copy.projectsWorktreeUntitled(bundle: bundle, locale: locale) } ?? Copy.projectsWorktreeNoSession(bundle: bundle, locale: locale),
            age: timeText(Date(timeIntervalSince1970: worktree.lastActiveAt / 1000), now: now, format: format),
            state: stateWords(worktree.state, bundle: bundle, locale: locale),
            kind: worktree.state,
            bytes: sizes[worktree.path]
        )
    }
}

private func stateWords(_ state: ProjectWorktree.State, bundle: Bundle?, locale: Locale) -> String {
    switch state {
    case .sessionOpen: Copy.projectsWorktreeStateOpen(bundle: bundle, locale: locale)
    case .uncommitted: Copy.projectsWorktreeStateUncommitted(bundle: bundle, locale: locale)
    case .merged: Copy.projectsWorktreeStateMerged(bundle: bundle, locale: locale)
    case .notPushed: Copy.projectsWorktreeStateNotPushed(bundle: bundle, locale: locale)
    case .clean: Copy.projectsWorktreeStateClean(bundle: bundle, locale: locale)
    }
}

/// What the host says when a session holds the worktree, which is also why the button is off while it is.
public func worktreeOpenWords(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.projectsWorktreeOpen(bundle: bundle, locale: locale) }

/// The reply of `cleanProjectWorktrees`: the merged worktrees nothing blocks (the ones Clean up removes, or removed) with the bytes each folder holds, and the ones it skips with the reason.
public struct ProjectCleanup: Decodable, Equatable, Sendable {
    public struct Removed: Decodable, Equatable, Sendable {
        public let path: String
        public let bytes: Int

        public init(path: String, bytes: Int) {
            self.path = path
            self.bytes = bytes
        }
    }

    public struct Skipped: Decodable, Equatable, Sendable {
        public let path: String
        public let reason: String
        /// The text code and parameters of `reason`; nil from a host that predates the codes.
        public let code: String?
        public let params: [String: TextParam]?

        public init(path: String, reason: String, code: String? = nil, params: [String: TextParam]? = nil) {
            self.path = path
            self.reason = reason
            self.code = code
            self.params = params
        }

        /// The reason in the person's language: the copy of its code, else its words.
        public func shownReason(bundle: Bundle? = nil, locale: Locale = .current) -> String { shownText(reason, code: code, params: params, bundle: bundle, locale: locale) }
    }

    public let removed: [Removed]
    public let skipped: [Skipped]

    public init(removed: [Removed], skipped: [Skipped]) {
        self.removed = removed
        self.skipped = skipped
    }

    public var bytes: Int { removed.reduce(0) { $0 + $1.bytes } }
}

/// The Clean up button's detail: how many worktrees it takes and how much they hold ("3 worktrees, 1.2 GB"); nil when there is none to take, which hides the button.
public func cleanUpWords(_ cleanup: ProjectCleanup, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard cleanup.removed.isEmpty == false else { return nil }
    return Copy.projectsCleanUpWords(
        count: cleanup.removed.count, size: ByteCountFormatter.string(fromByteCount: Int64(cleanup.bytes), countStyle: .file), bundle: bundle, locale: locale)
}

/// What Clean up reports after it ran: what went and, for each worktree it skipped, its folder's name and the reason.
public func cleanUpReport(_ cleanup: ProjectCleanup, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    var lines: [String] = []
    if let taken = cleanUpWords(cleanup, bundle: bundle, locale: locale) { lines.append(Copy.projectsCleanUpRemoved(taken: taken, bundle: bundle, locale: locale)) }
    for skip in cleanup.skipped {
        lines.append(Copy.projectsCleanUpSkipped(name: (skip.path as NSString).lastPathComponent, reason: skip.shownReason(bundle: bundle, locale: locale), bundle: bundle, locale: locale))
    }
    return lines.isEmpty ? Copy.projectsCleanUpNothing(bundle: bundle, locale: locale) : lines.joined(separator: "\n")
}
