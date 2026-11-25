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
        /// On a local branch that has a counterpart on `origin` only: the commits it has that `origin/<name>` lacks (not pushed), and the
        /// commits of `origin/<name>` it lacks (behind). Nil on a branch with no counterpart, and from a host that does not count.
        public let ahead: Int?
        public let behind: Int?

        public init(name: String, remote: Bool, ahead: Int? = nil, behind: Int? = nil) {
            self.name = name
            self.remote = remote
            self.ahead = ahead
            self.behind = behind
        }
    }

    /// `owner/name` of the GitHub remote the folder's `origin` is; nil for any other remote, and for none.
    public struct Repo: Decodable, Equatable {
        public let owner: String
        public let name: String

        public init(owner: String, name: String) {
            self.owner = owner
            self.name = name
        }
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
    public let repo: Repo?

    public init(
        folder: String, git: Bool = true, bare: Bool = false, linkedWorktree: Bool = false, branch: String? = nil, defaultBranch: String? = nil,
        dirty: Int = 0, branches: [Branch] = [], fetchedAt: Int? = nil, repo: Repo? = nil
    ) {
        self.repo = repo
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

    /// Whether the folder is a repository with an `origin` to fetch: a GitHub remote, or any remote branch already on disk (the host's reply
    /// does not name other remotes). Choosing the folder fetches only these.
    public var hasOrigin: Bool { git && bare == false && (repo != nil || branches.contains { $0.remote }) }

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
/// `startFrom` says which copy of the branch `from` names, `origin/<from>` or `<from>`; nil leaves it to the host's setting, and `from` then
/// is the exact ref (a host whose hello lacks `worktreeStart` takes no `startFrom`).
public struct WorktreeRequest: Equatable {
    public let from: String
    public let name: String?
    public let startFrom: WorktreeStart?

    public init(from: String, name: String? = nil, startFrom: WorktreeStart? = nil) {
        self.from = from
        self.name = name
        self.startFrom = startFrom
    }
}

/// Where a new worktree is cut from: a branch by its bare name and the side of it. `side` is nil for a repository that is not on this Mac
/// yet (its branches come from GitHub and a fresh clone follows the pick): there is no local side to choose.
public struct StartPoint: Equatable {
    public let branch: String
    public let side: WorktreeStart?

    /// The ref the worktree is cut from, as the chip and the steps name it.
    public var ref: String { side == .remote ? "origin/\(branch)" : branch }

    /// Whether `row` of `tab` is the branch this start is cut from: the same side and the same branch.
    public func chooses(_ row: BranchRow, on tab: WorktreeStart) -> Bool {
        side == tab && row.name == (tab == .remote ? "origin/\(branch)" : branch)
    }
}

/// The start of a worktree: the branch `picked` (else the default one, `defaultStartBranch`) on the side the person left the picker on
/// (`choice`), else the one the setting says. A branch that is not on `origin` can only start from local, and one that is only on `origin`
/// only from there. A branch named as `origin/<name>` (the folder sheet's pick) means its remote side unless the person chose a tab.
public func startPoint(picked: String?, in info: WorkspaceInfo, choice: WorktreeStart?, setting: WorktreeStart, cloned: Bool = false) -> StartPoint? {
    guard let named = picked ?? defaultStartBranch(info) else { return nil }
    let namedOnOrigin = info.branches.contains { $0.remote && $0.name == named }
    let branch = namedOnOrigin ? String(named.dropFirst("origin/".count)) : named
    guard cloned == false else { return StartPoint(branch: branch, side: nil) }
    let onOrigin = info.branches.contains { $0.remote && $0.name == "origin/\(branch)" }
    let onLocal = info.branches.contains { $0.remote == false && $0.name == branch }
    guard onOrigin else { return StartPoint(branch: branch, side: .local) }
    guard onLocal else { return StartPoint(branch: branch, side: .remote) }
    return StartPoint(branch: branch, side: choice ?? (namedOnOrigin ? .remote : setting))
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
public func workSentence(
    folder: String?, workspace: WorkspaceInfo? = nil, worktree: (name: String, from: String?)? = nil, gitMissing: Bool = false,
    bundle: Bundle? = nil, locale: Locale = .current
) -> String {
    guard let folder else { return Copy.newSessionWorkNoFolder(bundle: bundle, locale: locale) }
    let name = URL(fileURLWithPath: folder).lastPathComponent
    guard gitMissing == false else { return Copy.newSessionWorkGitMissing(name: name, reason: gitMissingReason(bundle: bundle, locale: locale), bundle: bundle, locale: locale) }
    guard let workspace else { return Copy.newSessionWorkBase(name: name, bundle: bundle, locale: locale) }
    guard workspace.git else { return Copy.newSessionWorkNotGit(name: name, bundle: bundle, locale: locale) }
    guard workspace.bare == false else { return Copy.newSessionWorkBare(name: name, bundle: bundle, locale: locale) }
    guard workspace.branches.isEmpty == false else { return Copy.newSessionWorkNoCommits(name: name, bundle: bundle, locale: locale) }
    if let worktree { return Copy.newSessionWorkWorktree(name: name, branch: worktreeBranchPrefix + worktree.name, from: worktree.from ?? "…", bundle: bundle, locale: locale) }
    return Copy.newSessionWorkBaseBranch(name: name, branch: workspace.branch ?? Copy.newSessionDetachedHead(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
}

/// Why there is no New worktree and no branch to show while `git` is missing; the reason points to the Health tab.
public func gitMissingReason(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.newSessionGitMissing(bundle: bundle, locale: locale) }

/// The line under the sentence when the base folder has uncommitted changes: how many, and that a worktree keeps them out of the agent's way.
public func uncommittedWarning(_ workspace: WorkspaceInfo, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard workspace.offersWorktree, workspace.dirty > 0 else { return nil }
    return Copy.newSessionUncommittedWarning(count: workspace.dirty, bundle: bundle, locale: locale)
}

/// A row of the branch picker.
public struct BranchRow: Equatable {
    public let name: String
    public let checkedOut: Bool
    public let isDefault: Bool
    /// A local branch with no counterpart on `origin`: it is only in the Local tab, and starts from local.
    public var localOnly = false
    /// How many commits of `origin/<name>` this local branch lacks, and how many it has that are not pushed; 0 with no counterpart or no count.
    public var behind = 0
    public var ahead = 0

    /// "3 behind origin", shown when the branch is behind; nil when it is not.
    public func behindText(bundle: Bundle? = nil, locale: Locale = .current) -> String? { behind > 0 ? Copy.newSessionBehindOrigin(count: behind, bundle: bundle, locale: locale) : nil }
    /// "2 not pushed", shown when the branch has commits `origin` lacks; nil when it has none.
    public func notPushedText(bundle: Bundle? = nil, locale: Locale = .current) -> String? { ahead > 0 ? Copy.newSessionNotPushed(count: ahead, bundle: bundle, locale: locale) : nil }
}

/// The picker's content: the local and the remote branches in two sections (what a search matches, ignoring case), the checked-out one
/// marked and the default one tagged, and how long ago the remote branches were fetched.
public struct BranchPicker: Equatable {
    public let local: [BranchRow]
    public let remote: [BranchRow]
    public let fetched: String
    /// What the footer says when the fetch on choosing could not reach `origin`; nil otherwise.
    public let unreachable: String?

    /// What the tab lists, one tab at a time so a branch is never offered twice: the branches on `origin` for Remote, the local ones for Local.
    public func rows(_ tab: WorktreeStart) -> [BranchRow] { tab == .remote ? remote : local }
}

public func branchPicker(
    _ workspace: WorkspaceInfo, query: String = "", now: Date = Date(), unreachable: Bool = false, bundle: Bundle? = nil, locale: Locale = .current
) -> BranchPicker {
    let wanted = query.trimmingCharacters(in: .whitespaces)
    let defaults = workspace.defaultBranch.map { [$0, "origin/\($0)"] } ?? []
    let onOrigin = Set(workspace.branches.filter(\.remote).map(\.name))
    let rows = workspace.branches
        .filter { wanted.isEmpty || $0.name.localizedCaseInsensitiveContains(wanted) }
        .map {
            (remote: $0.remote, row: BranchRow(
                name: $0.name, checkedOut: $0.remote == false && $0.name == workspace.branch, isDefault: defaults.contains($0.name),
                localOnly: $0.remote == false && onOrigin.contains("origin/\($0.name)") == false,
                behind: $0.behind ?? 0, ahead: $0.ahead ?? 0
            ))
        }
    return BranchPicker(
        local: rows.filter { $0.remote == false }.map(\.row), remote: rows.filter(\.remote).map(\.row),
        fetched: fetchedLine(workspace.fetchedAt, now: now, bundle: bundle, locale: locale), unreachable: unreachable ? unreachableLine(bundle: bundle, locale: locale) : nil
    )
}

/// The footer's words when the fetch that runs on choosing a project could not reach `origin`; with them, `fetchedLine` says since when the branches stand.
public func unreachableLine(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.newSessionUnreachable(bundle: bundle, locale: locale) }

/// The warning under the picker's "from" chip, nil when there is nothing to say: with Local chosen, that the branch is behind its copy on
/// `origin`; with Remote chosen, that the local branch has commits not pushed that the worktree will not have.
public func startWarning(_ point: StartPoint?, in workspace: WorkspaceInfo?, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    guard let point, let side = point.side, let local = workspace?.branches.first(where: { $0.remote == false && $0.name == point.branch }) else { return nil }
    switch side {
    case .local:
        guard let behind = local.behind, behind > 0 else { return nil }
        return Copy.newSessionStartBehind(branch: point.branch, count: behind, bundle: bundle, locale: locale)
    case .remote:
        guard let ahead = local.ahead, ahead > 0 else { return nil }
        return Copy.newSessionStartNotPushed(branch: point.branch, count: ahead, bundle: bundle, locale: locale)
    }
}

/// "Fetched 5 minutes ago"; "Never fetched" when the folder has no record of one.
public func fetchedLine(_ at: Int?, now: Date, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let at else { return Copy.newSessionFetchedNever(bundle: bundle, locale: locale) }
    let seconds = max(0, Int(now.timeIntervalSince1970) - at / 1000)
    switch seconds {
    case ..<60: return Copy.newSessionFetchedNow(bundle: bundle, locale: locale)
    case ..<3600: return Copy.newSessionFetchedMinutes(count: seconds / 60, bundle: bundle, locale: locale)
    case ..<86_400: return Copy.newSessionFetchedHours(count: seconds / 3600, bundle: bundle, locale: locale)
    default: return Copy.newSessionFetchedDays(count: seconds / 86_400, bundle: bundle, locale: locale)
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

public func stateOfName(_ check: NameCheck, bundle: Bundle? = nil, locale: Locale = .current) -> NameState {
    check.valid && check.free ? .free : .problem(check.reason ?? Copy.newSessionNameCannotBeUsed(bundle: bundle, locale: locale))
}
