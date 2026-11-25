import Foundation

/// What `deletePreview` says of one session: `worktree` is nil for a session in a base folder, else what deleting would discard from it.
public struct SessionDeletePreview: Decodable, Equatable {
    public let sessionId: String
    public let worktree: Worktree?

    /// `dirty` is the files with uncommitted changes, `unpushed` the commits on the branch that no other branch or remote branch holds.
    public struct Worktree: Decodable, Equatable {
        public let path: String
        public let branch: String
        public let dirty: Int
        public let unpushed: Int

        public init(path: String, branch: String, dirty: Int, unpushed: Int) {
            self.path = path
            self.branch = branch
            self.dirty = dirty
            self.unpushed = unpushed
        }
    }

    public init(sessionId: String, worktree: Worktree?) {
        self.sessionId = sessionId
        self.worktree = worktree
    }
}

/// The reply of `githubRepos`: one page of the repositories the person's `gh` login can read, whether the host has another, and (page 1
/// only) the login.
public struct GithubReposPage: Decodable, Equatable {
    public let repos: [AvailableRepo]
    public let hasMore: Bool
    public let login: String?

    public init(repos: [AvailableRepo], hasMore: Bool, login: String? = nil) {
        self.repos = repos
        self.hasMore = hasMore
        self.login = login
    }
}

/// A clone the person started from Settings, as the host lists it: running with git's latest progress line, or failed with its reason until it is dismissed.
/// One that finished is a project in `projects.json` and is no longer listed.
public struct ProjectClone: Decodable, Equatable, Identifiable, Sendable {
    public enum State: String, Decodable, Sendable { case cloning, failed }

    /// `owner/name`.
    public let repo: String
    /// Where it is being made.
    public let folder: String
    public let state: State
    /// Git's latest progress line ("Receiving objects: 45%"), once it has said one.
    public let progress: String?
    /// Why a failed clone failed, in the host's words.
    public let error: String?
    /// The text code and parameters of `error`; nil from a host that predates the codes.
    public let code: String?
    public let params: [String: TextParam]?

    public var id: String { repo.lowercased() }

    /// Why a failed clone failed in the person's language: the copy of its code, else the host's words; nil when there is none.
    public func shownError(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        error.map { shownText($0, code: code, params: params, bundle: bundle, locale: locale) }
    }

    public init(repo: String, folder: String, state: State, progress: String? = nil, error: String? = nil, code: String? = nil, params: [String: TextParam]? = nil) {
        self.repo = repo
        self.folder = folder
        self.state = state
        self.progress = progress
        self.error = error
        self.code = code
        self.params = params
    }
}

struct ProjectClonesReply: Decodable { let clones: [ProjectClone] }
struct NewProjectReply: Decodable { let folder: String }

/// What a person is told when the chat host that is running is older than the app and has no projects requests: the app replaces an older host when
/// no session is working, so the way out is to finish the work and restart the host.
public let projectsNeedNewerHost = "The chat host that is running is older than this app and cannot manage projects. Restart the chat host (when no session is working) to use it."

/// The reply of `repoBranches`: the default branch of a repository that need not be on disk and its branches (the first hundred, as GitHub lists
/// them), and whether there are more.
public struct RepoBranches: Decodable, Equatable {
    public let defaultBranch: String
    public let branches: [String]
    public let hasMore: Bool

    public init(defaultBranch: String, branches: [String], hasMore: Bool = false) {
        self.defaultBranch = defaultBranch
        self.branches = branches
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey { case defaultBranch = "default", branches, hasMore }
}
