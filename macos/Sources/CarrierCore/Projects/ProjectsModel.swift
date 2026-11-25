import CoreGraphics
import Foundation
import Observation

/// The rows of `projects.json`, kept in step with the file: it follows what another process writes. A file that does not match its schema (or cannot be
/// read) gives no rows and its problems. A change is a request to the chat host, or to `carrier config` when the host cannot take it (ProjectsRequests.swift): the app reads
/// the file and never writes it, and each change waits for the answer.
@MainActor @Observable public final class ProjectsModel {
    public internal(set) var rows: [ProjectRow] = []
    public private(set) var problems: [ProjectsProblem] = []
    /// Why the last add could not be written, when it could not.
    public private(set) var failure: String?
    /// Where new clones and new projects go by default (`projectsFolder` of `chat.json`).
    public private(set) var projectsPath: String
    /// Why the last Change… of the default folder was refused, in words; the old folder stands.
    public private(set) var projectsFolderProblem: String?
    /// The clones the host runs or that failed, as it last said (`refreshClones`).
    public private(set) var clones: [ProjectClone] = []
    /// What the host last said each project folder takes on disk, by the folder with `~` expanded; a project never measured is not here.
    public internal(set) var disk: [String: ProjectDiskFigure] = [:]
    /// The project folders the host has queued or is measuring, as it last said.
    public private(set) var measuring: Set<String> = []
    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let file: ProjectsFile
    @ObservationIgnored private let imageStore: ProjectIconStore
    @ObservationIgnored private let remote: (String) -> String?
    @ObservationIgnored private let readChatConfig: () throws -> Data?
    @ObservationIgnored private let home: String

    public var carrierFolder: String { file.folder }

    public init(
        host: ChatHost = SocketChatHost(),
        file: ProjectsFile = .current(),
        remote: @escaping (String) -> String? = originRepo(ofFolder:),
        readChatConfig: @escaping () throws -> Data? = currentChatConfig,
        home: String = NSHomeDirectory()
    ) {
        self.host = host
        self.file = file
        self.imageStore = ProjectIconStore(folder: file.folder)
        self.remote = remote
        self.readChatConfig = readChatConfig
        self.home = home
        self.projectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
    }

    /// Reads the file again; the rows and problems change only when they differ, so the page is not drawn again for nothing.
    public func reload() {
        let nextProjectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
        if projectsPath != nextProjectsPath { projectsPath = nextProjectsPath }
        var newRows: [ProjectRow] = []
        var newProblems: [ProjectsProblem] = []
        do {
            newRows = projectRows(try file.read(), remote: remote)
        } catch ProjectsFileError.invalid(let found) {
            newProblems = found
        } catch {
            newProblems = [ProjectsProblem(path: "(file)", message: "cannot be read: \(error.localizedDescription)")]
        }
        if rows != newRows { rows = newRows }
        if problems != newProblems { problems = newProblems }
    }

    /// Reloads now and then again each `interval`, until the task is cancelled. The host is asked for its clones once, and again at each turn only
    /// while one is running, so a page with none open does not talk to it. ponytail: a poll of a small file, which also sees an edit made in place; a file watcher if it ever costs.
    public func follow(every interval: Duration = .seconds(1)) async {
        await refreshClones()
        // the figures the host has, and the projects it has not measured for a day are measured again, one at a time, in the background
        await refreshDisk(.stale)
        while Task.isCancelled == false {
            reload()
            try? await Task.sleep(for: interval)
            if clones.contains(where: { $0.state == .cloning }) { await refreshClones() }
            if measuring.isEmpty == false { await refreshDisk(.read, of: Array(measuring)) }
        }
    }

    /// Asks the host what `paths` (the projects whose folder is there, when nil) take on disk, and for it to measure as `refresh` says; keeps the figures it answers and
    /// which of those folders it has queued. A host that does not answer leaves what was known: the figures are the host's, and a dash is all the page has to say.
    public func refreshDisk(_ refresh: ProjectDiskRefresh, of paths: [String]? = nil) async {
        let folders = (paths ?? rows.filter { $0.status == .ready }.map(\.path)).map { ($0 as NSString).expandingTildeInPath }
        guard folders.isEmpty == false, let reply = try? await host.projectDisk(folders, refresh: refresh) else { return }
        for figure in reply.projects where figure.bytes != nil && disk[figure.folder] != figure { disk[figure.folder] = figure }
        let queued = measuring.subtracting(folders).union(reply.measuring)
        if queued != measuring { measuring = queued }
    }

    /// The worktrees of a project, as the host lists them (`projectWorktrees`); the host is asked about the folder as written, `~` expanded.
    public func worktrees(of path: String) async throws -> ProjectWorktrees {
        try await host.projectWorktrees((path as NSString).expandingTildeInPath)
    }

    /// Removes the folder of one worktree of a project (the host keeps its branch and its session); throws the host's words when it refuses.
    public func removeWorktree(_ worktree: String, of path: String) async throws {
        try await host.removeProjectWorktree((path as NSString).expandingTildeInPath, path: worktree)
    }

    /// What Clean up would remove from a project and skip, or with `run` what it removed and skipped.
    public func cleanUpWorktrees(of path: String, run: Bool) async throws -> ProjectCleanup {
        try await host.cleanProjectWorktrees((path as NSString).expandingTildeInPath, run: run)
    }

    /// Asks the host again, just now, what a project holds and which sessions it has, and what that says of deleting it from disk (`projectDeletionCheck`);
    /// `worktrees` are the folders the Trash move takes with the project's. Throws the host's words when it cannot answer: nothing is deleted on a guess.
    public func deletionCheck(of path: String) async throws -> (check: ProjectDeletionCheck, worktrees: [String]) {
        let reply = try await worktrees(of: path)
        let sessions = try await host.list(archived: false)
        return (projectDeletionCheck(path: path, reply: reply, sessions: sessions), reply.worktrees.map(\.path))
    }

    /// Moves the project's folder and `worktrees` to the Trash and, only when that worked, takes the project out of the list. A folder that cannot be moved
    /// throws its reason and leaves the project, its folders and the sessions as they were.
    public func deleteFromDisk(path: String, worktrees: [String], trash: (URL) throws -> URL = systemTrash) async throws {
        // the question only offers it for what Carrier made, and this is the last place that can say no
        guard let entry = rows.first(where: { $0.path == path }), canDeleteFromDisk(origin: entry.origin) else {
            throw ProjectTrashError(words: "Carrier only deletes the projects it made, so nothing was deleted")
        }
        try moveProjectToTrash(path: path, worktrees: worktrees, carrierFolder: file.folder, home: home, trash: trash)
        await remove(path: path)
    }

    /// The rows of the clones that are running or failed, to show among the projects: they are not projects yet.
    public var cloneRows: [ProjectRow] { clones.map(ProjectRow.init(clone:)) }

    /// Asks the host which clones run or failed. A host that is not running, or is older, leaves what was known: the clones are the host's, and what
    /// it cannot say is not a reason to forget them. The file is read after, so a clone that just finished is a project when it stops being a clone.
    public func refreshClones() async {
        guard let latest = try? await host.projectClones() else { return }
        if clones != latest { clones = latest }
        reload()
    }

    /// Starts cloning `repo` into `parent` (nil: the projects folder) and puts the clone in the list at once; throws the host's words when it refuses.
    @discardableResult public func startClone(_ repo: String, into parent: String?) async throws -> ProjectClone {
        let started = try await host.cloneProject(repo, into: parent)
        clones = clones.filter { $0.id != started.id } + [started]
        return started
    }

    /// Asks the host to make `<parent>/local/<name>` with `git init` and register it (origin `created`), then reads the file so the project is in `rows`; answers its
    /// folder, or throws the host's words when it refuses (a folder that is already there, a name it does not take, a host that is older).
    public func createProject(_ name: String, into parent: String?) async throws -> String {
        let folder = try await host.newProject(name, into: parent)
        reload()
        return folder
    }

    /// Whether `path` is a project of the list or a folder that is already there: a new project cannot be made at it.
    public func isTaken(_ path: String) -> Bool {
        rows.contains { isSameFolder($0.path, path) } || FileManager.default.fileExists(atPath: path)
    }

    /// Forgets a failed clone: the host drops it and the row goes.
    public func dismissClone(_ repo: String) async {
        if let left = try? await host.dismissClone(repo) { clones = left }
    }

    /// Adds `folder` as a project, or says it already is one and writes nothing. nil when it could not be: `failure` says why (the folder is refused, or the host refused the file).
    @discardableResult public func add(folder: String) async -> ProjectAdd? {
        if let refusal = addRefusal(folder: folder, replacing: nil) {
            failure = refusal
            return nil
        }
        guard let reply = await send(.add(folder: folder)), let path = reply.saved?.path else { return nil }
        return reply.added == true ? .added(path) : .existing(path)
    }

    /// Why `folder` cannot be a project: `projectFolderRefusal`, else a worktree directory that is another project's (`worktreeClashRefusal`), naming it.
    /// `replacing` is the path of the project being pointed at `folder` (Locate…), which does not count as another. nil when it can; a file that does not
    /// read is left to the write, which says why.
    public func addRefusal(folder: String, replacing: String?) -> String? {
        if let refusal = projectFolderRefusal(folder, carrierFolder: file.folder) { return refusal.shown() }
        let others = projectRows((try? file.read()) ?? [], remote: remote).filter { $0.path != replacing }
        return worktreeClashRefusal(folder: folder, repo: remote(folder), among: others)?.shown()
    }

    /// Points the project at `path` to `folder`, its new place, after the check for folders that cannot be projects; everything else of the entry stays and
    /// so do the sessions that remember the old path. False when nothing was written: `failure` says why.
    @discardableResult public func locate(path: String, to folder: String) async -> Bool {
        if let refusal = projectFolderRefusal(folder, carrierFolder: file.folder) {
            failure = refusal.shown()
            return false
        }
        if rows.contains(where: { $0.path != path && isSameFolder($0.path, folder) }) {
            failure = "That folder is already a project"
            return false
        }
        if let refusal = addRefusal(folder: folder, replacing: path) {
            failure = refusal
            return false
        }
        return await send(.move(path: path, folder: folder)) != nil
    }

    /// Clears the last add failure (for example when a sheet is dismissed).
    public func clearFailure() { failure = nil }

    /// Asks for `folder` as `projectsFolder` in `chat.json`; the host refuses a folder inside Carrier's own folders and the old path stays, with the reason in `projectsFolderProblem`.
    public func changeProjectsFolder(to folder: String) async {
        do {
            _ = try await host.changeProjects(.setFolder(folder))
            projectsFolderProblem = nil
            projectsPath = projectsFolder(chatJSON: (try? readChatConfig()) ?? nil, carrierFolder: file.folder, home: home)
        } catch {
            projectsFolderProblem = "\(Self.words(error)). The projects folder stays \(projectsPath)."
        }
    }

    /// Takes the project out of the list and, once the reply says it was removed, deletes its icon image copy (unless another project names it). The folder, the worktrees,
    /// the sessions and `engine.json` are not touched: watching is the engine's file and removing a project never changes it.
    @discardableResult public func remove(path: String) async -> Bool {
        let entries = (try? file.read()) ?? []
        let image = entries.first { $0.path == path }?.iconImage
        let others = entries.filter { $0.path != path }
        guard await send(.remove(path: path))?.removed != nil else { return false }
        if let image, others.contains(where: { $0.iconImage == image }) == false { imageStore.delete(image) }
        return true
    }

    /// Sets the project's name, or removes `name` when `raw` is empty or blank so it goes back to the folder's name.
    @discardableResult public func setName(_ raw: String, path: String) async -> Bool {
        await send(.edit(path: path, key: "name", value: ConfigValue(normalizedProjectName(raw)))) != nil
    }

    /// Hides the project from the sheet New session opens, or shows it again; shown leaves `hidden` out of the entry. Nothing else changes.
    @discardableResult public func setHidden(_ hidden: Bool, path: String) async -> Bool {
        await send(.edit(path: path, key: "hidden", value: hidden ? .flag(true) : .remove)) != nil
    }

    /// Sets what a new session here starts with: a nil value is the same as everywhere and takes its key out, and `defaults` goes when none is left.
    @discardableResult public func setDefault(_ key: ProjectDefaultKey, _ value: String?, path: String) async -> Bool {
        await send(.editDefaults(path: path, changes: [key.rawValue: ConfigValue(value)])) != nil
    }

    /// Sets what a new session here starts with, as the picker of Settings > Sessions has it: the agent, its model and reasoning and its access, which
    /// go together. An empty value, or no agent at all, is the same as everywhere and takes its key out.
    @discardableResult public func setStart(_ start: NewSessionStart, path: String) async -> Bool {
        let named = start.agent.isEmpty == false
        func own(_ value: String) -> ConfigValue { ConfigValue(named && value.isEmpty == false ? value : nil) }
        let access = named ? start.access.filter { $0.value.isEmpty == false } : [:]
        return await send(.editDefaults(path: path, changes: [
            "agent": own(start.agent), "model": own(start.model), "effort": own(start.effort), "access": access.isEmpty ? .remove : .map(access),
        ])) != nil
    }

    /// The branches `path` has, local first, as the host reads them; empty when it is not a git repository or the host did not answer.
    public func branches(of path: String) async -> [WorkspaceInfo.Branch] {
        (try? await host.workspace(path))?.branches ?? []
    }

    /// Pins or unpins the project; unpinned leaves `pinned` out of the entry.
    @discardableResult public func setPinned(_ pinned: Bool, path: String) async -> Bool {
        await send(.edit(path: path, key: "pinned", value: pinned ? .flag(true) : .remove)) != nil
    }

    /// Adds a tag (trimmed, lower case, no repeats, blank ignored) to the project's entry.
    @discardableResult public func addTag(_ raw: String, path: String) async -> Bool {
        await send(.editTags(path: path, add: [raw], remove: [])) != nil
    }

    /// Removes `tag` from the project's entry.
    @discardableResult public func removeTag(_ tag: String, path: String) async -> Bool {
        await send(.editTags(path: path, add: [], remove: [tag])) != nil
    }

    /// Sets or clears the project's icon colour, clearing any image and deleting its copy while keeping every other key.
    @discardableResult public func setIconColor(_ color: ProjectColor?, path: String) async -> Bool {
        await editIconClearingImage(path: path, changes: ["color": ConfigValue(color?.rawValue)])
    }

    /// Sets or clears the project's icon mark, clearing any image and deleting its copy while keeping every other key.
    @discardableResult public func setIconMark(_ mark: AppIcon?, path: String) async -> Bool {
        await editIconClearingImage(path: path, changes: ["mark": ConfigValue(mark?.rawValue)])
    }

    /// Clears the project's icon colour, mark and image, deleting any copied image file while keeping every other key of the entry.
    @discardableResult public func resetIcon(path: String) async -> Bool {
        await editIconClearingImage(path: path, changes: ["color": .remove, "mark": .remove])
    }

    /// Copies and reduces the image at `sourceURL` into `project-icons`, points `icon.image` at it, and deletes any previous copy.
    @discardableResult public func setIconImage(from sourceURL: URL, path: String) async -> Bool {
        await saveIconImage(path: path) { try $0.save(from: sourceURL) }
    }

    /// Scales and saves `image` into `project-icons`, points `icon.image` at it, and deletes any previous copy.
    @discardableResult public func setIconImage(cgImage image: CGImage, path: String) async -> Bool {
        await saveIconImage(path: path) { try $0.save(cgImage: image) }
    }

    /// The copy of an icon image goes only when the reply says the change was saved, and only when no other project names it.
    private func editIconClearingImage(path: String, changes: [String: ConfigValue]) async -> Bool {
        let entries = (try? file.read()) ?? []
        let previousImage = entries.first { $0.path == path }?.iconImage
        guard await send(.editIcon(path: path, changes: changes.merging(["image": .remove]) { $1 })) != nil else { return false }
        if let previousImage, entries.contains(where: { $0.path != path && $0.iconImage == previousImage }) == false { imageStore.delete(previousImage) }
        return true
    }

    private func saveIconImage(path: String, save: (ProjectIconStore) throws -> String) async -> Bool {
        let entries = (try? file.read()) ?? []
        let previous = entries.first { $0.path == path }?.iconImage
        let name: String
        do { name = try save(imageStore) } catch {
            failure = (error as? ProjectIconStoreError)?.localizedDescription ?? "The image could not be saved: \(error.localizedDescription)"
            return false
        }
        guard await send(.editIcon(path: path, changes: ["image": .text(name)])) != nil else {
            imageStore.delete(name)
            return false
        }
        if let previous, previous != name, entries.contains(where: { $0.path != path && $0.iconImage == previous }) == false { imageStore.delete(previous) }
        return true
    }

    /// Asks for `actions` on the project at `path` and reloads the list; false without asking when any action is invalid, and when the host refuses.
    @discardableResult public func saveActions(path: String, actions: [ProjectAction]) async -> Bool {
        guard actions.allSatisfy({ projectActionProblems($0).isEmpty }) else { return false }
        return await send(.setActions(path: path, actions: actions)) != nil
    }

    /// Sends the change and waits for the reply; reads the file again after it. nil when it was refused or could not be sent: `failure` says why, and the file stands as it was.
    private func send(_ change: ProjectsChange) async -> ProjectsChanged? {
        do {
            let reply = try await host.changeProjects(change)
            failure = nil
            reload()
            return reply
        } catch {
            failure = Self.words(error)
            reload()
            return nil
        }
    }

    private static func words(_ error: Error) -> String {
        if case ControlError.remote(let refusal) = error { return refusal.shown() }
        return "projects.json cannot be changed: \(ConversationModel.words(error))"
    }
}
