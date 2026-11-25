import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// One project's screen: its Identity group (name, icon colour and mark, tags), its Pin action in the page's header, Actions row, and its folder and remote.
struct ProjectDetailView: View {
    @Environment(\.pieceTheme) var theme
    let row: ProjectRow
    let model: ProjectsModel
    let watchedRepos: [String]?
    let state: ConnectionState?
    let canReload: Bool
    /// Reads the engine config again after the switch wrote it.
    let reloadWatched: () -> Void
    let openActions: () -> Void
    let close: () -> Void
    /// Called with the project's new path after Locate… wrote it, which is the page's place now.
    let moved: (String) -> Void
    @Environment(\.settingsHeaderAction) var headerAction
    @State var confirmingRemove = false
    /// A project Carrier made asks first whether its files go too (docs/adr/0040); the question the host's fresh answer or the Trash raised, and whether the move is under way.
    @State var choosingRemove = false
    @State var deletionAsk: DeletionAsk?
    @State var deleting = false
    @State var owner = UUID()
    @State var pickingIcon = false
    @State var newTag = ""
    @State var worktrees: ProjectWorktrees?
    @State var worktreesProblem: String?
    /// What Clean up would take, asked when the page has a merged worktree; nil while it is not known.
    @State var cleanup: ProjectCleanup?
    @State var confirmingCleanup = false
    /// The worktrees whose Remove is running (or Clean up's), the reason the host refused each one, and what the last Clean up did.
    @State var removing: Set<String> = []
    @State var removeProblems: [String: String] = [:]
    @State var cleanUpNote: String?
    /// The branches the project's folder has, read when the page opens; empty for a folder that is not a git repository, and while the host has not answered.
    @State var branches: [WorkspaceInfo.Branch] = []
    let catalog = ModelCatalog.shared
    /// What Settings > Sessions starts a new session with, which a project left on "Same as everywhere" follows.
    @AppStorage(Preference.chatNewSessionAgent) var everywhereAgent
    @AppStorage(Preference.chatNewSessionModel) var everywhereModel
    @AppStorage(Preference.chatNewSessionEffort) var everywhereEffort
    @AppStorage(Preference.chatNewSessionAccess) var everywhereAccess
    /// Why the last change of the Carrier switch was refused, and the question asked before it goes off.
    @State var watchFailure: String?
    @State var confirmingStop = false
    private let reloaded = ReloadStatus.shared

    var body: some View {
        let exists = row.status == .ready
        let page = ProjectPage(for: row)
        Group {
            if exists == false {
                SettingsGroup(title: "") {
                    SettingsTabRow(title: "Folder not found", detail: "", first: true, problem: "\(row.path) is not there any more. Locate it to open the project again.") {
                        Button("Locate…", action: locate).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
            SettingsGroup(title: "Identity") {
                SettingsTabRow(title: "Name", detail: "Empty uses the folder's name", first: true) {
                    ProjectNameField(stored: row.customName ?? "", prompt: row.folderName) { await model.setName($0, path: row.path) }
                }
                SettingsTabRow(title: "Icon", detail: "Color and mark, or an image; initials when none is chosen") {
                    HStack(spacing: Tokens.Space.s10) {
                        ProjectIcon(tile: row.tile, imageFolder: model.carrierFolder)
                        Button("Change…") { pickingIcon = true }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .accessibilityLabel("Change the icon")
                            .accessibilityValue(iconSummary)
                            .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                                ProjectIconPopover(
                                    selectedColor: row.iconColor,
                                    selectedMark: row.iconMark,
                                    hasImage: row.iconImage != nil,
                                    setColor: { color in Task { await model.setIconColor(color, path: row.path) } },
                                    setMark: { mark in Task { await model.setIconMark(mark, path: row.path) } },
                                    chooseImage: chooseImage,
                                    reset: { Task { await model.resetIcon(path: row.path) } }
                                )
                                .padding(Tokens.Space.s14)
                            }
                    }
                }
                SettingsTabRow(title: "Tags", detail: "Press Return to add") {
                    VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        TextField("", text: $newTag, prompt: Text("Add a tag"))
                            .settingsField(width: settingsSelectWidth)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                            .accessibilityLabel("Add a tag")
                        if row.tags.isEmpty == false {
                            FlowLayout(spacing: Tokens.Space.s6) {
                                ForEach(row.tags, id: \.self) { tag in
                                    ProjectTagChip(tag: tag) { Task { await model.removeTag(tag, path: row.path) } }
                                }
                            }
                            .frame(width: settingsSelectWidth, alignment: .leading)
                        }
                    }
                }
            }
            SettingsGroup(title: "New sessions here", footer: page.notice) {
                SettingsTabRow(
                    title: "Show when starting a session",
                    detail: row.hidden
                        ? "\(row.name) does not appear in the new session picker. Nothing is deleted: it stays in this list and its sessions stay in the sidebar."
                        : "\(row.name) is listed when you choose where to work in a new session",
                    first: true
                ) {
                    Toggle("Show when starting a session", isOn: Binding(get: { row.hidden == false }, set: { hidden in Task { await model.setHidden(hidden == false, path: row.path) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                SettingsTabRow(id: "starts-with", title: "Starts with", detail: "Provider, model and reasoning; Same as everywhere is Settings > Sessions") {
                    startPicker
                }
                SettingsTabRow(id: "work-in", title: "Work in", detail: "The base folder or a new worktree; Default is Settings > Sessions") {
                    ChoicePopUp(label: "Work in", options: workInOptions, selection: defaultBinding(.workIn, row.defaults.workIn?.projectValue))
                }
                if page.baseBranch {
                    SettingsTabRow(title: "Base branch", detail: "The branch a new session here starts from; Default branch is the one checked out") {
                        ChoicePopUp(label: "Base branch", options: branchOptions, selection: defaultBinding(.baseBranch, row.defaults.baseBranch))
                    }
                }
            }
            if page.worktrees { worktreesGroup }
            if page.carrier { carrierGroup }
            SettingsGroup(title: "") {
                NavigationRow(title: "Actions", detail: "Commands run for a new worktree or after a clone", first: true, action: openActions) {
                    Text(projectActionsSummary(row.actions.count)).scaledFont(12).foregroundStyle(.secondary)
                }
            }
            SettingsGroup(title: "") {
                SettingsTabRow(title: "Folder", detail: row.path, first: true, mono: true) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (row.path as NSString).expandingTildeInPath)])
                    } label: { Label("Reveal in Finder", icon: .folder).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(exists == false)
                }
                if page.remote {
                    SettingsTabRow(title: "Remote", detail: row.repo ?? "No GitHub remote", mono: row.repo != nil) {
                        if let repo = row.repo, let url = URL(string: "https://github.com/\(repo)") {
                            Button { NSWorkspace.shared.open(url) } label: { Label("Open on GitHub", icon: .externalLink).labelStyle(.titleAndIcon) }
                                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        }
                    }
                }
                SettingsTabRow(title: "Remove", detail: canDeleteFromDisk(origin: row.origin) ? "Takes \(row.name) out of Carrier, and its files too if you choose" : "Takes \(row.name) out of Carrier; its folder and worktrees stay") {
                    Button(role: .destructive) { canDeleteFromDisk(origin: row.origin) ? (choosingRemove = true) : (confirmingRemove = true) } label: { Label("Remove…", icon: .trash) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(deleting)
                }
            }
        }
        .writingToolsBehavior(.disabled)
        // the ellipsis of Remove… is this question
        .alert("Remove \(row.name) from Carrier?", isPresented: $confirmingRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { Task { if await model.remove(path: row.path) { close() } } }
        } message: {
            Text(projectRemovalWords)
        }
        .confirmationDialog("Remove \(row.name)?", isPresented: $choosingRemove, titleVisibility: .visible) {
            Button("Remove from Carrier") { Task { if await model.remove(path: row.path) { close() } } }
            Button("Also delete from disk", role: .destructive) { Task { await deleteFromDisk(confirmed: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(projectRemovalWords)\n\nAlso delete from disk: \(deleteFromDiskWords(worktrees: worktrees?.worktrees.count ?? 0, bytes: model.disk[(row.path as NSString).expandingTildeInPath]?.bytes))")
        }
        .alert(deletionAsk?.title ?? "", isPresented: Binding(get: { deletionAsk != nil }, set: { if $0 == false { deletionAsk = nil } }), presenting: deletionAsk) { ask in
            Button(ask.canConfirm ? "Cancel" : "OK", role: .cancel) {}
            if ask.canConfirm { Button("Move to the Trash anyway", role: .destructive) { Task { await deleteFromDisk(confirmed: true) } } }
        } message: { ask in
            Text(ask.message)
        }
        .alert(cleanup.flatMap(cleanUpWords).map { "Clean up \($0)?" } ?? "Clean up", isPresented: $confirmingCleanup) {
            Button("Cancel", role: .cancel) {}
            Button("Clean up", role: .destructive) { Task { await runCleanup() } }
        } message: {
            Text(cleanUpQuestionWords)
        }
        .alert("Stop watching \(row.repo ?? "")?", isPresented: $confirmingStop) {
            Button("Cancel", role: .cancel) {}
            Button("Stop watching", role: .destructive) { setWatching(false) }
        } message: {
            Text(row.repo.map { removalText(repoEpics($0, snapshot: snapshot), appliesNow: appliesWhileRunning(state: state, canReload: canReload)) } ?? "")
        }
        .task(id: row.path) {
            // a fresh figure is asked for and the host measures in the background; the list's follow loop reads it as it lands
            if page.worktrees {
                await model.refreshDisk(.now, of: [row.path])
                await loadWorktrees()
            }
        }
        .task(id: row.path) { branches = await model.branches(of: row.path) }
        .onAppear(perform: publishPin)
        .onChange(of: row.pinned) { publishPin() }
        .onChange(of: row.path) { publishPin() }
        .onDisappear { headerAction?.clear(owner) }
    }

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = state { return snapshot }
        return nil
    }

    /// The Carrier group: the one switch that makes Carrier watch the project's repository (its `owner/name` in the engine config's repos).
    private var carrierGroup: some View {
        let watch = projectWatchRow(repo: row.repo, repos: watchedRepos, state: state, canReload: canReload, outcome: reloaded.outcome, failure: watchFailure)
        return SettingsGroup(id: "carrier", title: "Carrier") {
            SettingsTabRow(title: "Let Carrier watch this project", detail: watch.detail, first: true, problem: watch.problem) {
                Toggle("Let Carrier watch this project", isOn: Binding(get: { watch.isOn }, set: { $0 ? setWatching(true) : (confirmingStop = true) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(watch.canChange == false)
            }
        }
    }

    /// Asks the engine to change its config like the Watching page does, which runs on it at once; a refusal is shown on the row.
    private func setWatching(_ on: Bool) {
        guard let repo = row.repo else { return }
        Task {
            if let names = currentConfig().flatMap({ configRepoNames(json: $0) }) {
                switch watchChange(on, repo: repo, in: names) {
                case .refused(let words): watchFailure = words
                case .send(let list): watchFailure = await saveEngineConfig(.watchedRepos(list), send: EngineConfigSender.app.send).problem
                }
            } else {
                watchFailure = "The config file could not be read or the list is not valid."
            }
            reloadWatched()
        }
    }

    /// The system's folder panel for the project's new place; the folder goes through the check for folders that cannot be projects before the path is replaced.
    private func locate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Locate"
        panel.message = "Choose the new place of \(row.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = row.path
        Task { if await model.locate(path: path, to: url.path) { moved(url.path) } }
    }

    private func publishPin() {
        let path = row.path, pinned = row.pinned
        headerAction?.set(
            owner,
            title: pinned ? "Pinned" : "Pin",
            icon: pinned ? .pinFilled : .pin,
            active: pinned,
            help: pinned ? "Unpin project" : "Pin project"
        ) {
            Task { await model.setPinned(!pinned, path: path) }
        }
    }

    private func addTag() {
        let candidate = newTag
        newTag = ""
        guard addingProjectTag(candidate, to: row.tags) != row.tags else { return }
        let path = row.path
        Task { await model.addTag(candidate, path: path) }
    }

    private var iconSummary: String {
        if row.iconImage != nil { return "Custom image" }
        let color = row.iconColor?.rawValue.capitalized ?? "Automatic color"
        let mark = row.iconMark?.rawValue.capitalized ?? "initials"
        return "\(color), \(mark)"
    }

    private func chooseImage() {
        pickingIcon = false
        let path = row.path
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]
            panel.prompt = "Choose"
            panel.message = "Choose an image for the project's icon"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let rasterized = ProjectIconStore.canRead(url) ? nil : rasterizedImage(at: url)
            Task {
                if let rasterized { await model.setIconImage(cgImage: rasterized, path: path) } else { await model.setIconImage(from: url, path: path) }
            }
        }
    }

    private func rasterizedImage(at url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let limit = CGFloat(ProjectIconStore.maxPixelSize)
        let scale = min(1, min(limit / size.width, limit / size.height))
        let target = NSSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        var rect = NSRect(origin: .zero, size: target)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
