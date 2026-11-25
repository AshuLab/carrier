import AppKit
import CarrierCore
import CarrierUI
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
    /// What Clean up would take, asked when the page has a finished worktree (Merged or In main); nil while it is not known.
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
                    SettingsTabRow(title: Copy.projectsFolderNotFound(), detail: "", first: true, problem: Copy.projectsFolderGone(path: row.path)) {
                        Button(Copy.projectsLocate(), action: locate).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
            SettingsGroup(title: Copy.projectsIdentity()) {
                SettingsTabRow(title: Copy.projectsName(), detail: Copy.projectsNameDetail(), first: true) {
                    ProjectNameField(stored: row.customName ?? "", prompt: row.folderName) { await model.setName($0, path: row.path) }
                }
                SettingsTabRow(title: Copy.projectsIcon(), detail: Copy.projectsIconDetail()) {
                    HStack(spacing: Tokens.Space.s10) {
                        ProjectIcon(tile: row.tile, imageFolder: model.carrierFolder)
                        Button(Copy.projectsChange()) { pickingIcon = true }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .accessibilityLabel(Copy.projectsChangeIcon())
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
                SettingsTabRow(title: Copy.projectsColTags(), detail: Copy.projectsTagsDetail()) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        TextField("", text: $newTag, prompt: Text(Copy.projectsAddTag()))
                            .settingsField(width: settingsSelectWidth)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                            .accessibilityLabel(Copy.projectsAddTag())
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
            SettingsGroup(title: Copy.projectsNewSessionsHere(), footer: page.notice) {
                SettingsTabRow(
                    title: Copy.projectsShowWhenStarting(),
                    detail: row.hidden ? Copy.projectsShowDetailHidden(name: row.name) : Copy.projectsShowDetailShown(name: row.name),
                    first: true
                ) {
                    Toggle(Copy.projectsShowWhenStarting(), isOn: Binding(get: { row.hidden == false }, set: { hidden in Task { await model.setHidden(hidden == false, path: row.path) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                SettingsTabRow(id: "starts-with", title: Copy.projectsStartsWith(), detail: Copy.projectsStartsWithDetail()) {
                    startPicker
                }
                SettingsTabRow(id: "work-in", title: Copy.projectsWorkIn(), detail: Copy.projectsWorkInDetail()) {
                    ChoicePopUp(label: Copy.projectsWorkIn(), options: workInOptions, selection: defaultBinding(.workIn, row.defaults.workIn?.projectValue))
                }
                if page.baseBranch {
                    SettingsTabRow(title: Copy.projectsBaseBranch(), detail: Copy.projectsBaseBranchDetail()) {
                        ChoicePopUp(label: Copy.projectsBaseBranch(), options: branchOptions, selection: defaultBinding(.baseBranch, row.defaults.baseBranch))
                    }
                }
            }
            if page.worktrees { worktreesGroup }
            if page.carrier { carrierGroup }
            SettingsGroup(title: "") {
                NavigationRow(title: Copy.projectsActionsTitle(), detail: Copy.projectsActionsDetail(), first: true, action: openActions) {
                    Text(projectActionsSummary(row.actions.count)).scaledFont(12).foregroundStyle(.secondary)
                }
            }
            SettingsGroup(title: "") {
                SettingsTabRow(title: Copy.projectsFolder(), detail: row.path, first: true, mono: true) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (row.path as NSString).expandingTildeInPath)])
                    } label: { Label(Copy.projectsReveal(), icon: .folder).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(exists == false)
                }
                if page.remote {
                    SettingsTabRow(title: Copy.projectsRemote(), detail: row.repo ?? Copy.projectsNoRemote(), mono: row.repo != nil) {
                        if let repo = row.repo, let url = URL(string: "https://github.com/\(repo)") {
                            Button { NSWorkspace.shared.open(url) } label: { Label(Copy.projectsOpenGitHub(), icon: .externalLink).labelStyle(.titleAndIcon) }
                                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        }
                    }
                }
                SettingsTabRow(
                    title: Copy.projectsRemove(),
                    detail: canDeleteFromDisk(origin: row.origin) ? Copy.projectsRemoveDetailDisk(name: row.name) : Copy.projectsRemoveDetail(name: row.name)
                ) {
                    Button(role: .destructive) { canDeleteFromDisk(origin: row.origin) ? (choosingRemove = true) : (confirmingRemove = true) } label: { Label(Copy.projectsRemoveEllipsis(), icon: .trash) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(deleting)
                }
            }
        }
        .writingToolsBehavior(.disabled)
        // the ellipsis of Remove… is this question
        .alert(Copy.projectsRemoveQuestion(name: row.name), isPresented: $confirmingRemove) {
            Button(Copy.projectsCancel(), role: .cancel) {}
            Button(Copy.projectsRemove(), role: .destructive) { Task { if await model.remove(path: row.path) { close() } } }
        } message: {
            Text(projectRemovalWords())
        }
        .confirmationDialog(Copy.projectsRemoveDialog(name: row.name), isPresented: $choosingRemove, titleVisibility: .visible) {
            Button(Copy.projectsRemoveFromCarrier()) { Task { if await model.remove(path: row.path) { close() } } }
            Button(Copy.projectsAlsoDelete(), role: .destructive) { Task { await deleteFromDisk(confirmed: false) } }
            Button(Copy.projectsCancel(), role: .cancel) {}
        } message: {
            Text(Copy.projectsRemoveDialogMessage(
                words: projectRemovalWords(),
                delete: deleteFromDiskWords(worktrees: worktrees?.worktrees.count ?? 0, bytes: model.disk[(row.path as NSString).expandingTildeInPath]?.bytes)))
        }
        .alert(deletionAsk?.title ?? "", isPresented: Binding(get: { deletionAsk != nil }, set: { if $0 == false { deletionAsk = nil } }), presenting: deletionAsk) { ask in
            Button(ask.canConfirm ? Copy.projectsCancel() : Copy.projectsOk(), role: .cancel) {}
            if ask.canConfirm { Button(Copy.projectsMoveToTrashAnyway(), role: .destructive) { Task { await deleteFromDisk(confirmed: true) } } }
        } message: { ask in
            Text(ask.message)
        }
        .alert(cleanup.flatMap { cleanUpWords($0) }.map { Copy.projectsCleanUpQuestion(words: $0) } ?? Copy.projectsCleanUp(), isPresented: $confirmingCleanup) {
            Button(Copy.projectsCancel(), role: .cancel) {}
            Button(Copy.projectsCleanUp(), role: .destructive) { Task { await runCleanup() } }
        } message: {
            Text(cleanUpQuestionWords)
        }
        .alert(Copy.projectsStopWatchingQuestion(repo: row.repo ?? ""), isPresented: $confirmingStop) {
            Button(Copy.projectsCancel(), role: .cancel) {}
            Button(Copy.projectsStopWatching(), role: .destructive) { setWatching(false) }
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
        return SettingsGroup(id: "carrier", title: Copy.projectsCarrierGroup()) {
            SettingsTabRow(title: Copy.projectsLetWatch(), detail: watch.detail, first: true, problem: watch.problem) {
                Toggle(Copy.projectsLetWatch(), isOn: Binding(get: { watch.isOn }, set: { $0 ? setWatching(true) : (confirmingStop = true) }))
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
                watchFailure = Copy.projectsWatchConfigInvalid()
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
        panel.prompt = Copy.projectsLocatePrompt()
        panel.message = Copy.projectsLocateMessage(name: row.name)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = row.path
        Task { if await model.locate(path: path, to: url.path) { moved(url.path) } }
    }

    private func publishPin() {
        let path = row.path, pinned = row.pinned
        headerAction?.set(
            owner,
            title: pinned ? Copy.projectsPinned() : Copy.projectsPin(),
            icon: pinned ? .pinFilled : .pin,
            active: pinned,
            help: pinned ? Copy.projectsUnpinHelp() : Copy.projectsPinHelp()
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
        if row.iconImage != nil { return Copy.projectsIconCustom() }
        let color = row.iconColor?.title() ?? Copy.projectsIconAutoColor()
        let mark = row.iconMark.map { projectMarkTitle($0) } ?? Copy.projectsIconInitials()
        return Copy.projectsIconSummary(color: color, mark: mark)
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
            panel.prompt = Copy.projectsChoose()
            panel.message = Copy.projectsChooseImageMessage()
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
