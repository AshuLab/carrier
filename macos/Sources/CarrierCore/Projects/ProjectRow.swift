import CoreGraphics
import Foundation
import Observation

/// The keys of a project's `defaults`.
public enum ProjectDefaultKey: String, Sendable {
    case agent, workIn, baseBranch
}

/// One project of the list.
public struct ProjectRow: Equatable, Identifiable, Sendable {
    /// The project's identity, as the file has it.
    public let path: String
    /// The name set on it, else the folder's.
    public let name: String
    /// The custom name stored in `projects.json`, nil when absent.
    public let customName: String?
    /// `owner/name` of its GitHub `origin`, when it has one.
    public let repo: String?
    public let pinned: Bool
    /// Left out of the sheet New session opens (it stays in the sidebar and in this list).
    public let hidden: Bool
    /// `notFound` when its folder is gone.
    public let status: ProjectStatus
    /// How it came to be: `cloned` and `created` are what Carrier made, `added` a folder the person brought (docs/adr/0040).
    public let origin: String
    public let tags: [String]
    public let iconColor: ProjectColor?
    public let iconMark: AppIcon?
    public let iconImage: String?
    /// Actions run in a new worktree or after a clone, from `projects.json`.
    public let actions: [ProjectAction]
    /// Whether its folder is a git repository, read each time with the list and never stored; a project that is not one has no worktrees, base branch or Carrier switch.
    public let isGit: Bool
    /// What a new session here starts with, over Settings > Sessions.
    public let defaults: ProjectDefaults
    /// Set on a row that stands for a clone the host is running or that failed: it is not a project yet and cannot be opened.
    public let clone: ProjectClone?
    /// When a session last worked in it, from `projectsWithLastActive`; derived from the sessions, never stored in the file. nil when none did.
    public var lastActive: Date?
    /// Whether Carrier watches its repository: its `owner/name` is in the engine config's `repos`, from `projectsWithWatched`; never stored in `projects.json`.
    public var watched: Bool
    /// What the project takes on disk as the host last measured it, from `projectsWithDisk`; never stored. nil when it has not been measured.
    public var diskBytes: Int?

    public init(
        path: String,
        name: String,
        customName: String? = nil,
        repo: String?,
        pinned: Bool = false,
        hidden: Bool = false,
        status: ProjectStatus = .ready,
        origin: String = "added",
        tags: [String] = [],
        iconColor: ProjectColor? = nil,
        iconMark: AppIcon? = nil,
        iconImage: String? = nil,
        actions: [ProjectAction] = [],
        isGit: Bool = true,
        defaults: ProjectDefaults = ProjectDefaults(),
        clone: ProjectClone? = nil,
        lastActive: Date? = nil,
        watched: Bool = false
    ) {
        self.path = path
        self.name = name
        self.customName = customName
        self.repo = repo
        self.pinned = pinned
        self.hidden = hidden
        self.status = status
        self.origin = origin
        self.tags = tags
        self.iconColor = iconColor
        self.iconMark = iconMark
        self.iconImage = iconImage
        self.actions = actions
        self.isGit = isGit
        self.defaults = defaults
        self.clone = clone
        self.lastActive = lastActive
        self.watched = watched
    }

    /// The list's row for a clone started from Settings: named as the repository, at the folder it is made in.
    public init(clone: ProjectClone) {
        self.init(path: clone.folder, name: clone.repo.split(separator: "/").last.map(String.init) ?? clone.repo, repo: clone.repo, clone: clone)
    }

    /// Whether a click on the row opens the project's page: not while it is cloning or after its clone failed.
    public var isOpenable: Bool { clone == nil }

    public var id: String { path }
    /// The folder's own name (what the Name field falls back to when emptied).
    public var folderName: String { projectFolderName(path) }
    /// What the row says under the name: the repository, else where the folder is.
    public var line: String {
        switch clone?.state {
        case .cloning: clone?.progress ?? "Cloning…"
        case .failed: clone?.error ?? "The clone failed"
        case nil: repo ?? path
        }
    }
    /// What the list's Carrier column says.
    public var carrierText: String { watched ? "Watching" : "Not watched" }
    /// What its tile's colour is made from, so it matches the project's sessions.
    public var colorKey: String { projectColorKey(path) }
    /// What the project's tile draws: its chosen colour and mark, else initials on a colour made from the name.
    public var tile: ProjectTile { projectTile(name: name, colorKey: colorKey, color: iconColor, mark: iconMark, image: iconImage) }
}

/// What a project's page has, which depends on its folder (docs/specs/projects.md, Scope 21): a folder that is there but is not a git repository has no Worktrees
/// and disk group, no base branch row, no Remote row and no Carrier switch, offers only the base folder to work in, and says why in one line. A folder that is gone is another notice.
public struct ProjectPage: Equatable, Sendable {
    public let worktrees: Bool
    public let baseBranch: Bool
    public let carrier: Bool
    /// Whether the Folder group has the Remote row: a folder that is not a git repository has no remote to show.
    public let remote: Bool
    /// What the Work in choice offers.
    public let workIn: [WorkIn]
    public let notice: String?

    public init(for row: ProjectRow) {
        let plain = row.status == .ready && row.isGit == false
        worktrees = row.status == .ready && plain == false
        baseBranch = plain == false
        carrier = plain == false
        remote = plain == false
        workIn = plain ? [.baseFolder] : WorkIn.allCases
        notice = plain ? "Not a git repository, so it has no worktrees, base branch or Carrier switch." : nil
    }
}
