import Foundation

// Deleting a project from disk (docs/adr/0040): what the Remove question offers, what stops it and what the person must confirm, and the move to the Trash.
// It is the one place where Carrier takes a folder off the Mac, so every step refuses before it acts and nothing is ever removed outright.

/// Whether the Remove question offers deleting from disk: only a folder Carrier made (`cloned`, `created`), never one the person added.
public func canDeleteFromDisk(origin: String) -> Bool { origin == "cloned" || origin == "created" }

/// What "Also delete from disk" says it does: the folder and the worktrees go to the Trash, with what they hold (the project's total, when known), and the
/// space is freed only when the Trash is emptied.
public func deleteFromDiskWords(worktrees: Int, bytes: Int?, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let bytes else { return Copy.projectsDeleteFromDisk(worktrees: worktrees, bundle: bundle, locale: locale) }
    return Copy.projectsDeleteFromDiskSized(worktrees: worktrees, size: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file), bundle: bundle, locale: locale)
}

/// What the host's fresh answer about a project says of deleting it: `refusals` stop it for good (a session of the project is working, waiting or open), and
/// `unsaved` is what would be lost, which the person may confirm after seeing it.
public struct ProjectDeletionCheck: Equatable, Sendable {
    public let refusals: [String]
    public let unsaved: [String]

    public var canGoOn: Bool { refusals.isEmpty }
    public var needsConfirmation: Bool { unsaved.isEmpty == false }
}

/// Reads the host's `projectWorktrees` answer and the sessions it lists, both asked just before acting. A session of the project is one whose base folder is
/// its path; one that is not idle, or whose agent runs, refuses. The main clone and each worktree with uncommitted changes or commits no remote holds are listed.
public func projectDeletionCheck(path: String, reply: ProjectWorktrees, sessions: [ChatSession], bundle: Bundle? = nil, locale: Locale = .current) -> ProjectDeletionCheck {
    var refusals: [String] = []
    var covered: Set<String> = []
    for session in sessions where isSameFolder(session.workspace?.base ?? session.folder, path) && (session.live || session.state != .idle) {
        covered.insert(session.id)
        let name = session.title ?? Copy.projectsWorktreeUntitled(bundle: bundle, locale: locale)
        switch session.state {
        case .working, .preparing: refusals.append(Copy.projectsDeleteSessionWorking(name: name, bundle: bundle, locale: locale))
        case .waitingApproval: refusals.append(Copy.projectsDeleteSessionWaiting(name: name, bundle: bundle, locale: locale))
        case .idle: refusals.append(Copy.projectsDeleteSessionOpen(name: name, bundle: bundle, locale: locale))
        }
    }
    // the host's own view of a worktree whose session the list did not name
    for worktree in reply.worktrees where worktree.state == .sessionOpen && covered.contains(worktree.session?.id ?? "") == false {
        refusals.append(Copy.projectsDeleteWorktreeSessionOpen(branch: worktree.branch ?? Copy.projectsDeleteAWorktree(bundle: bundle, locale: locale), bundle: bundle, locale: locale))
    }
    var unsaved: [String] = []
    switch reply.main.state {
    case nil: refusals.append(Copy.projectsDeleteHostOlder(bundle: bundle, locale: locale))
    case .uncommitted?: unsaved.append(Copy.projectsDeleteUncommitted(name: projectFolderName(reply.main.path), bundle: bundle, locale: locale))
    case .notPushed?: unsaved.append(Copy.projectsDeleteNotPushed(name: projectFolderName(reply.main.path), bundle: bundle, locale: locale))
    default: break
    }
    for worktree in reply.worktrees {
        let name = worktree.branch ?? (worktree.path as NSString).lastPathComponent
        switch worktree.state {
        case .uncommitted: unsaved.append(Copy.projectsDeleteUncommitted(name: name, bundle: bundle, locale: locale))
        case .notPushed: unsaved.append(Copy.projectsDeleteNotPushed(name: name, bundle: bundle, locale: locale))
        default: break
        }
    }
    return ProjectDeletionCheck(refusals: refusals, unsaved: unsaved)
}

/// Why the project's folder and its worktrees cannot be moved to the Trash, in words; nil when they can. The folder must be a git repository of its own that is
/// not Carrier's, not the home folder or a parent of it or of the Carrier folder, and a real folder (not a link); each worktree must lie under the chat's
/// `worktrees/` folder, deeper than it, and never be the project itself.
public func projectTrashRefusal(
    path: String, worktrees: [String], carrierFolder: String, home: String = NSHomeDirectory(), bundle: Bundle? = nil, locale: Locale = .current
) -> String? {
    let expanded = (path as NSString).expandingTildeInPath
    if let refusal = projectFolderRefusal(expanded, carrierFolder: carrierFolder) { return refusal.shown(bundle: bundle, locale: locale) }
    let real = normalizedFolder(expanded)
    for keep in [normalizedFolder(home), normalizedFolder(carrierFolder)] where real == keep || keep.hasPrefix(real + "/") {
        return Copy.projectsTrashHome(bundle: bundle, locale: locale)
    }
    guard real.split(separator: "/").count >= 2 else { return Copy.projectsTrashTooHigh(bundle: bundle, locale: locale) }
    var info = stat()
    guard lstat(expanded, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return Copy.projectsTrashLink(bundle: bundle, locale: locale) }
    guard FileManager.default.fileExists(atPath: expanded + "/.git") else { return Copy.projectsTrashNotGit(bundle: bundle, locale: locale) }
    let root = normalizedFolder(CarrierPlaces(folder: carrierFolder).chatWorktrees) + "/"
    for worktree in worktrees {
        let there = normalizedFolder(worktree)
        guard there.hasPrefix(root), there != real else { return Copy.projectsTrashNotWorktree(name: (worktree as NSString).lastPathComponent, bundle: bundle, locale: locale) }
    }
    return nil
}

/// Moves the worktrees and then the project's folder to the Trash, after `projectTrashRefusal`. When one cannot go (another volume, a permission) what was
/// already moved is put back and the reason is thrown: nothing is removed. `trash` answers where the item went; it is the system's Trash unless a test says so.
public func moveProjectToTrash(
    path: String,
    worktrees: [String],
    carrierFolder: String,
    home: String = NSHomeDirectory(),
    trash: (URL) throws -> URL = systemTrash,
    bundle: Bundle? = nil,
    locale: Locale = .current
) throws {
    if let refusal = projectTrashRefusal(path: path, worktrees: worktrees, carrierFolder: carrierFolder, home: home, bundle: bundle, locale: locale) { throw ProjectTrashError(words: refusal) }
    var moved: [(from: URL, to: URL)] = []
    for item in worktrees.filter({ FileManager.default.fileExists(atPath: $0) }) + [(path as NSString).expandingTildeInPath] {
        let from = URL(fileURLWithPath: item)
        do {
            moved.append((from, try trash(from)))
        } catch {
            var stuck: [String] = []
            for entry in moved.reversed() {
                do { try FileManager.default.moveItem(at: entry.to, to: entry.from) } catch { stuck.append(entry.from.lastPathComponent) }
            }
            let left = stuck.isEmpty
                ? Copy.projectsTrashNothingRemoved(bundle: bundle, locale: locale)
                : Copy.projectsTrashStuck(names: stuck.joined(separator: ", "), bundle: bundle, locale: locale)
            throw ProjectTrashError(words: Copy.projectsTrashCouldNotMove(name: from.lastPathComponent, reason: error.localizedDescription, left: left, bundle: bundle, locale: locale))
        }
    }
}

public struct ProjectTrashError: Error, LocalizedError, Equatable {
    public let words: String
    public var errorDescription: String? { words }
}

/// `FileManager.trashItem`: the folder goes to the Trash and the answer is where it lies there.
public func systemTrash(_ url: URL) throws -> URL {
    var result: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    return (result as URL?) ?? url
}
