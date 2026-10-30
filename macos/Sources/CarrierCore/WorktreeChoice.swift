import Foundation

// The worktree half of the new-session sentence (docs/specs/sessions-in-the-app.md, "New session"; the replies are the chat host's,
// docs/specs/session-worktrees.md, "Decisions"): what the host says a folder is, the sentence and its warning, the branch to start
// from, the branch picker's lists and the states of the worktree's name. All pure values; `NewSessionModel` drives them.

/// The reply of `workspace` and `fetch`: what a folder is as a git repository. A plain folder is `git: false` with every other field empty.
public struct WorkspaceInfo: Decodable, Equatable {
    public struct Branch: Decodable, Equatable {
        public let name: String
        /// A remote branch is listed as `origin/<name>`.
        public let remote: Bool
    }

    public let folder: String
    public let git: Bool
    public let bare: Bool
    public let linkedWorktree: Bool
    /// The checked-out branch; nil when HEAD is detached.
    public let branch: String?
    /// `origin/HEAD`, else `main`, else `master` when one exists; nil when none does.
    public let defaultBranch: String?
    /// Files with uncommitted changes, tracked or not.
    public let dirty: Int
    /// Local first, then remote.
    public let branches: [Branch]
    /// Milliseconds since the epoch of the last fetch of `origin`.
    public let fetchedAt: Int?

    public init(
        folder: String, git: Bool = true, bare: Bool = false, linkedWorktree: Bool = false, branch: String? = nil, defaultBranch: String? = nil,
        dirty: Int = 0, branches: [Branch] = [], fetchedAt: Int? = nil
    ) {
        self.folder = folder
        self.git = git
        self.bare = bare
        self.linkedWorktree = linkedWorktree
        self.branch = branch
        self.defaultBranch = defaultBranch
        self.dirty = dirty
        self.branches = branches
        self.fetchedAt = fetchedAt
    }

    /// A worktree needs a repository with a working folder and a commit to start from: with no branch at all there is none.
    public var offersWorktree: Bool { git && bare == false && branches.isEmpty == false }
}

/// The reply of `checkName`: `reason` is the host's, in words, whenever the name is not valid or not free.
public struct NameCheck: Decodable, Equatable {
    public let valid: Bool
    public let free: Bool
    public let reason: String?

    public init(valid: Bool, free: Bool, reason: String? = nil) {
        self.valid = valid
        self.free = free
        self.reason = reason
    }
}

/// What `open` is asked to make: a worktree cut from `from` (a branch `workspace` listed), called `name` (the part after `carrier/`).
public struct WorktreeRequest: Equatable {
    public let from: String
    public let name: String?

    public init(from: String, name: String? = nil) {
        self.from = from
        self.name = name
    }
}

/// Every worktree branch is `carrier/<name>`: the person edits the name, the prefix is fixed.
public let worktreeBranchPrefix = "carrier/"

/// The branch to start from when the person has not picked one: the checked-out branch, else the repository's default branch (when
/// HEAD is detached) as the host lists it (local, else `origin/…`), else nil and the person is asked.
public func defaultStartBranch(_ info: WorkspaceInfo) -> String? {
    if let branch = info.branch { return branch }
    guard let fallback = info.defaultBranch else { return nil }
    return [fallback, "origin/\(fallback)"].first { name in info.branches.contains { $0.name == name } }
}

/// What the sentence says: "Work in web on the base folder (main)", or in a new worktree, or why it cannot be one. `workspace` is nil
/// while the host has not said what the folder is; `worktree` is the chosen name and branch ("…" while the branch is not chosen).
/// `gitMissing` (the health says so) says why there is no branch and no worktree, whatever the host could read of the folder.
public func workSentence(folder: String?, workspace: WorkspaceInfo? = nil, worktree: (name: String, from: String?)? = nil, gitMissing: Bool = false) -> String {
    guard let folder else { return "Work in Choose a workspace… on the base folder" }
    let name = URL(fileURLWithPath: folder).lastPathComponent
    guard gitMissing == false else { return "Work in \(name) in the folder (\(gitMissingReason))" }
    guard let workspace else { return "Work in \(name) on the base folder" }
    guard workspace.git else { return "Work in \(name) in the folder (not a git repository: no worktree)" }
    guard workspace.bare == false else { return "Work in \(name) in the folder (bare repository: no worktree)" }
    guard workspace.branches.isEmpty == false else { return "Work in \(name) in the folder (new project, no commits yet: no worktree)" }
    if let worktree { return "Work in \(name) in a new worktree \(worktreeBranchPrefix)\(worktree.name) from \(worktree.from ?? "…")" }
    return "Work in \(name) on the base folder (\(workspace.branch ?? "detached HEAD"))"
}

/// Why there is no New worktree and no branch to show while `git` is missing; the reason points to the Health tab.
public let gitMissingReason = "git is missing: no worktree, no branch. See Health in Settings"

/// The line under the sentence when the base folder has uncommitted changes: how many, and that a worktree keeps them out of the agent's way.
public func uncommittedWarning(_ workspace: WorkspaceInfo) -> String? {
    guard workspace.offersWorktree, workspace.dirty > 0 else { return nil }
    return "\(workspace.dirty) uncommitted \(workspace.dirty == 1 ? "file" : "files") in the folder. A worktree keeps them out of the agent's way."
}

/// A row of the branch picker.
public struct BranchRow: Equatable {
    public let name: String
    public let checkedOut: Bool
    public let isDefault: Bool
}

/// The picker's content: the local and the remote branches in two sections (what a search matches, ignoring case), the checked-out one
/// marked and the default one tagged, and how long ago the remote branches were fetched.
public struct BranchPicker: Equatable {
    public let local: [BranchRow]
    public let remote: [BranchRow]
    public let fetched: String
}

public func branchPicker(_ workspace: WorkspaceInfo, query: String = "", now: Date = Date()) -> BranchPicker {
    let wanted = query.trimmingCharacters(in: .whitespaces)
    let defaults = workspace.defaultBranch.map { [$0, "origin/\($0)"] } ?? []
    let rows = workspace.branches
        .filter { wanted.isEmpty || $0.name.localizedCaseInsensitiveContains(wanted) }
        .map { (remote: $0.remote, row: BranchRow(name: $0.name, checkedOut: $0.remote == false && $0.name == workspace.branch, isDefault: defaults.contains($0.name))) }
    return BranchPicker(
        local: rows.filter { $0.remote == false }.map(\.row), remote: rows.filter(\.remote).map(\.row),
        fetched: fetchedLine(workspace.fetchedAt, now: now)
    )
}

/// "Fetched 5 minutes ago"; "Never fetched" when the folder has no record of one.
public func fetchedLine(_ at: Int?, now: Date) -> String {
    guard let at else { return "Never fetched" }
    let seconds = max(0, Int(now.timeIntervalSince1970) - at / 1000)
    func unit(_ count: Int, _ name: String) -> String { "Fetched \(count) \(name)\(count == 1 ? "" : "s") ago" }
    switch seconds {
    case ..<60: return "Fetched just now"
    case ..<3600: return unit(seconds / 60, "minute")
    case ..<86_400: return unit(seconds / 3600, "hour")
    default: return unit(seconds / 86_400, "day")
    }
}

/// The states of the worktree's name: the host's suggestion is free; a typed one is checked a moment after typing.
public enum NameState: Equatable {
    case suggesting
    case checking
    case free
    /// Invalid or taken, with the host's reason (or ours when the host could not be asked).
    case problem(String)
}

public func stateOfName(_ check: NameCheck) -> NameState {
    check.valid && check.free ? .free : .problem(check.reason ?? "That name cannot be used")
}
