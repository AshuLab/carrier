import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

extension ProjectsModel {
    /// The app's one reading of `projects.json`: the Projects page edits it and the sidebar, the lists and the cards draw from it.
    static let shared = ProjectsModel()
}

/// The Projects page of Settings (docs/specs/projects.md): the person's projects, one row each, and Add project, which takes a folder of the Mac. A row opens
/// the project as a screen of its own, a place of the window's history (‹ ›) named by its path, and Actions opens its actions screen. The rows are
/// `ProjectsModel`'s, which follows `projects.json`; the page has no automated test of its own.
struct ProjectsTabView: View {
    let place: SettingsPlace
    let go: (SettingsPlace) -> Void
    var sessions: [SessionRow] = []
    /// What the Carrier switch of a project needs to say when a change applies (the Repos page's inputs).
    var state: ConnectionState?
    var canReload = false
    private let model = ProjectsModel.shared
    /// The engine config's repos as the file is when the page opens (and after a change of the switch); nil when it cannot be read.
    @State private var watchedRepos: [String]?
    @State private var query = ""
    @State private var filter: ProjectFilter = .all
    @State private var groupBy: ProjectGrouping = .none
    @State private var order = ProjectOrder()
    @State private var adding = false

    static let actionsPath = "actions"

    /// The page's width, to drop the Tags and Carrier columns when the Project column would be left with less than `ProjectColumns.project`; the list takes the
    /// window, less the page's 24 and the card's 14 on each side.
    @State private var pageWidth: CGFloat = 0
    private var columns: ProjectColumns { ProjectColumns(contentWidth: pageWidth - 28) }

    private var showingActions: Bool { place.path.count > 1 && place.path[1] == Self.actionsPath }

    var body: some View {
        let chosen = place.path.first.flatMap { path in model.rows.first { $0.path == path } }
        SettingsPageBody {
            if model.problems.isEmpty {
                if let chosen {
                    if showingActions {
                        if let failure = model.failure { ProblemLine(text: failure) }
                        ProjectActionsView(
                            savedActions: chosen.actions,
                            save: { model.saveActions(path: chosen.path, actions: $0) }
                        )
                        .id(chosen.path)
                    } else {
                        projectScreen(chosen)
                    }
                } else {
                    if let failure = model.failure { ProblemLine(text: failure) }
                    list
                }
            } else {
                problems
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { pageWidth = $0 }
        .preference(key: SettingsTitleKey.self, value: chosen.map {
            showingActions ? SettingsTitle(text: "Actions", subtitle: $0.name) : SettingsTitle(text: $0.name, subtitle: $0.line)
        })
        .sheet(isPresented: $adding, onDismiss: { model.clearFailure() }) {
            AddProjectSheet(
                mode: .settings,
                model: model,
                recent: recentFolders(from: sessions),
                openProject: open
            )
            .themed()
        }
        // the file is another process's too: the list follows it while the page is open
        .task { await model.follow() }
        // the engine config is read when the page opens and when a project's page does, so the switch shows the file as it is then
        .onAppear(perform: loadWatched)
        // a refusal or a failed write belongs to the screen it happened on, not to the one the person goes to next
        .onChange(of: place) { loadWatched(); model.clearFailure() }
    }

    private func loadWatched() {
        watchedRepos = (try? Data(contentsOf: URL(fileURLWithPath: configFilePath()))).flatMap { configRepoNames(json: $0) }
    }

    // MARK: the list

    @ViewBuilder private var list: some View {
        let shown = model.rows + model.cloneRows
        let tags = projectTagsInUse(shown)
        let groups = projectList(projectsWithWatched(projectsWithDisk(projectsWithLastActive(shown, sessions: sessions), figures: model.disk), repos: watchedRepos), query: query, filter: filter, groupBy: groupBy, order: order)
        let now = Date()
        Group {
            if shown.isEmpty {
                SettingsGroup(title: "") {
                    EmptyStateView(
                        icon: .folder, title: "No projects yet", line: "Add a folder you work in and it shows here.",
                        action: (title: "Add project", run: { adding = true }), actionIcon: .folderPlus, actionStyle: .accentGlass
                    )
                    .frame(minHeight: 260)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("", text: $query, prompt: Text("Search projects"))
                            .accessibilityLabel("Search projects")
                            .settingsField(icon: .search)
                        HStack(spacing: 6) {
                            Text("Group").font(.scaled(12)).foregroundStyle(.secondary)
                            ChoicePopUp(
                                label: "Group",
                                options: ProjectGrouping.allCases.map { (value: $0, title: $0.title) },
                                selection: $groupBy
                            )
                        }
                        Button { adding = true } label: { Label("Add project", icon: .folderPlus).labelStyle(.titleAndIcon) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                    FlowLayout(spacing: 6) {
                        FilterChip(title: "All", on: filter == .all) { filter = .all }
                        ForEach(tags, id: \.self) { tag in
                            FilterChip(title: tag, on: filter == .tag(tag)) {
                                filter = filter == .tag(tag) ? .all : .tag(tag)
                            }
                        }
                        FilterChip(title: "Watched", on: filter == .watched) {
                            filter = filter == .watched ? .all : .watched
                        }
                        FilterChip(title: "Local only", on: filter == .localOnly) {
                            filter = filter == .localOnly ? .all : .localOnly
                        }
                        FilterChip(title: "Hidden", on: filter == .hidden) {
                            filter = filter == .hidden ? .all : .hidden
                        }
                    }
                }
                if groups.isEmpty {
                    SettingsGroup(title: "") {
                        EmptyStateView(
                            icon: .search, title: "Nothing matches", line: "Try another word or filter.",
                            action: (title: "Clear filters", run: { query = ""; filter = .all }), actionIcon: .close
                        )
                        .frame(minHeight: 220)
                    }
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                        SettingsGroup(title: group.title ?? "") {
                            if groupIndex == 0 {
                                HStack(spacing: ProjectColumns.gap) {
                                    sortTitle("Project", key: .name).frame(minWidth: ProjectColumns.project, maxWidth: .infinity, alignment: .leading)
                                    if columns.showsTags {
                                        Text("Tags").frame(width: ProjectColumns.tags, alignment: .leading).accessibilityHidden(true)
                                    }
                                    sortTitle("Last active", key: .lastActive).frame(width: ProjectColumns.lastActive, alignment: .leading)
                                    sortTitle("Disk", key: .disk).frame(width: ProjectColumns.disk, alignment: .leading)
                                    if columns.showsCarrier {
                                        Text("Carrier").frame(width: ProjectColumns.carrier, alignment: .leading).accessibilityHidden(true)
                                    }
                                    Color.clear.frame(width: ProjectColumns.trailing, height: 1)
                                }
                                .sectionLabel().padding(.vertical, 10)
                            }
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                projectRow(row, now: now, divider: groupIndex == 0 || index > 0)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: tags) { _, latest in
            if case .tag(let current) = filter, latest.contains(current) == false { filter = .all }
        }
        cloneDestinationLine
    }

    /// A column title that sorts the list by `key` when clicked; the sorted one shows its direction.
    private func sortTitle(_ title: String, key: ProjectSortKey) -> some View {
        let sorted = order.key == key
        return Button { order = order.clicked(key) } label: {
            HStack(spacing: 3) {
                Text(title)
                if sorted { Glyph(order.ascending ? .chevronUp : .chevronDown, size: 8, bold: true).accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityValue(sorted ? (order.ascending ? "ascending" : "descending") : "")
    }

    /// A clone that is running or failed: it is not a project yet, so the row has no chevron and cannot be opened. It shows git's progress line, or the
    /// reason the clone failed in orange with a way to dismiss it.
    private func cloneRow(_ row: ProjectRow, _ clone: ProjectClone, divider: Bool) -> some View {
        HStack(spacing: 12) {
            ProjectIcon(tile: row.tile)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                    switch clone.state {
                    case .cloning: StatusChip(text: "Cloning", tint: .accentColor)
                    case .failed: StatusChip(text: "Failed", tint: .orange)
                    }
                }
                Text(row.line)
                    .font(.scaled(11)).foregroundStyle(clone.state == .failed ? Color.orange : .secondary)
                    .lineLimit(clone.state == .failed ? 3 : 1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clone.state == .failed {
                Button("Dismiss") { Task { await model.dismissClone(clone.repo) } }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    .accessibilityLabel("Dismiss the failed clone of \(clone.repo)")
            }
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { if divider { SettingsDivider() } }
    }

    @ViewBuilder private func projectRow(_ row: ProjectRow, now: Date, divider: Bool) -> some View {
        if let clone = row.clone {
            cloneRow(row, clone, divider: divider)
        } else {
            openableRow(row, now: now, divider: divider)
        }
    }

    private func openableRow(_ row: ProjectRow, now: Date, divider: Bool) -> some View {
        Button { open(row.path) } label: {
            HStack(spacing: ProjectColumns.gap) {
                HStack(spacing: 12) {
                    ProjectIcon(tile: row.tile, imageFolder: model.carrierFolder)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                        if let status = row.status.text {
                            Label(status, icon: .warningFilled, size: 11).font(.scaled(11)).foregroundStyle(.orange).lineLimit(1)
                        } else if row.hidden {
                            Label("Hidden", icon: .eyeOff, size: 11).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(row.line).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: ProjectColumns.project, maxWidth: .infinity, alignment: .leading)
                .opacity(row.hidden ? 0.55 : 1)

                if columns.showsTags {
                    Group {
                        if row.tags.isEmpty {
                            Color.clear.frame(height: 1)
                        } else {
                            FlowLayout(spacing: 4) {
                                ForEach(row.tags, id: \.self) { tag in
                                    StatusChip(text: tag, tint: .secondary)
                                }
                            }
                        }
                    }
                    .frame(width: ProjectColumns.tags, alignment: .leading)
                }

                Text(row.lastActive.map { timeText($0, now: now) } ?? "—")
                    .font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: ProjectColumns.lastActive, alignment: .leading)

                // the host's last figure, and a dash for a project it has not measured and always for a folder that is gone
                Text(row.diskBytes.map(formatDiskSize) ?? "—").font(.scaled(12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: ProjectColumns.disk, alignment: .leading)

                if columns.showsCarrier {
                    Text(row.carrierText)
                        .font(.scaled(12)).foregroundStyle(row.watched ? Color.primary : .secondary).lineLimit(1)
                        .frame(width: ProjectColumns.carrier, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if row.pinned { Glyph(.pinFilled, size: 11, label: "Pinned").foregroundStyle(.secondary) }
                    Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .frame(width: ProjectColumns.trailing, alignment: .trailing)
            }
            .padding(.vertical, 10).frame(minHeight: 46)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if divider { SettingsDivider() } }
        }
        .buttonStyle(.plain)
    }

    private var cloneDestinationLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("New clones go to ")
                    .font(.scaled(12))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text((model.projectsPath as NSString).abbreviatingWithTildeInPath)
                    .font(.scaled(11.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(model.projectsPath)
                Button("Change…", action: changeProjectsFolder)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .controlSize(.small)
                    .help("Where repositories are cloned and new projects are made")
                Spacer(minLength: 0)
            }
            if let problem = model.projectsFolderProblem {
                ProblemLine(text: problem)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// The system's folder panel for changing where new clones and new projects go (`projectsFolder` in `chat.json`).
    private func changeProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.projectsPath)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.changeProjectsFolder(to: url.path)
        }
    }

    private func open(_ path: String) { go(SettingsPlace(.projects, path: [path])) }

    private func openActions(_ path: String) { go(SettingsPlace(.projects, path: [path, Self.actionsPath])) }

    // MARK: a project

    @ViewBuilder private func projectScreen(_ row: ProjectRow) -> some View {
        if let failure = model.failure { ProblemLine(text: failure) }
        ProjectDetailView(
            row: row, model: model, watchedRepos: watchedRepos, state: state, canReload: canReload, reloadWatched: loadWatched,
            openActions: { openActions(row.path) }, close: { go(SettingsPlace(.projects)) }, moved: open
        ).id(row.path)
    }

    // MARK: a file that does not match

    private var problems: some View {
        SettingsGroup(title: "", footer: "Fix the file and the page follows. Nothing is written to it while it is wrong.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.problems.enumerated()), id: \.offset) { _, problem in ProblemLine(text: problem.text) }
            }
            .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One project's screen: its Identity group (name, icon colour and mark, tags), its Pin action in the page's header, Actions row, and its folder and remote.
private struct ProjectDetailView: View {
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
    @Environment(\.settingsHeaderAction) private var headerAction
    @State private var confirmingRemove = false
    /// A project Carrier made asks first whether its files go too (docs/adr/0040); the question the host's fresh answer or the Trash raised, and whether the move is under way.
    @State private var choosingRemove = false
    @State private var deletionAsk: DeletionAsk?
    @State private var deleting = false
    @State private var owner = UUID()
    @State private var pickingIcon = false
    @State private var newTag = ""
    @State private var worktrees: ProjectWorktrees?
    @State private var worktreesProblem: String?
    /// What Clean up would take, asked when the page has a merged worktree; nil while it is not known.
    @State private var cleanup: ProjectCleanup?
    @State private var confirmingCleanup = false
    /// The worktrees whose Remove is running (or Clean up's), the reason the host refused each one, and what the last Clean up did.
    @State private var removing: Set<String> = []
    @State private var removeProblems: [String: String] = [:]
    @State private var cleanUpNote: String?
    /// The branches the project's folder has, read when the page opens; empty for a folder that is not a git repository, and while the host has not answered.
    @State private var branches: [WorkspaceInfo.Branch] = []
    private let catalog = ModelCatalog.shared
    /// What Settings > Sessions starts a new session with, which a project left on "Same as everywhere" follows.
    @AppStorage(AppPreferences.newSessionAgentKey) private var everywhereAgent = ""
    @AppStorage(AppPreferences.newSessionModelKey) private var everywhereModel = ""
    @AppStorage(AppPreferences.newSessionEffortKey) private var everywhereEffort = ""
    @AppStorage(AppPreferences.newSessionAccessKey) private var everywhereAccess = ""
    /// Why the last change of the Carrier switch was refused, and the question asked before it goes off.
    @State private var watchFailure: String?
    @State private var confirmingStop = false
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
                    ProjectNameField(stored: row.customName ?? "", prompt: row.folderName) { model.setName($0, path: row.path) }
                }
                SettingsTabRow(title: "Icon", detail: "Color and mark, or an image; initials when none is chosen") {
                    HStack(spacing: 10) {
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
                                    setColor: { model.setIconColor($0, path: row.path) },
                                    setMark: { model.setIconMark($0, path: row.path) },
                                    chooseImage: chooseImage,
                                    reset: { model.resetIcon(path: row.path) }
                                )
                                .padding(14)
                            }
                    }
                }
                SettingsTabRow(title: "Tags", detail: "Press Return to add") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("", text: $newTag, prompt: Text("Add a tag"))
                            .settingsField(width: settingsSelectWidth)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                            .accessibilityLabel("Add a tag")
                        if row.tags.isEmpty == false {
                            FlowLayout(spacing: 6) {
                                ForEach(row.tags, id: \.self) { tag in
                                    ProjectTagChip(tag: tag) { model.removeTag(tag, path: row.path) }
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
                    Toggle("Show when starting a session", isOn: Binding(get: { row.hidden == false }, set: { model.setHidden($0 == false, path: row.path) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                SettingsTabRow(title: "Starts with", detail: "Provider, model and reasoning; Same as everywhere is Settings > Sessions") {
                    startPicker
                }
                SettingsTabRow(title: "Work in", detail: "The base folder or a new worktree; Default is Settings > Sessions") {
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
                    Text(projectActionsSummary(row.actions.count)).font(.scaled(12)).foregroundStyle(.secondary)
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
            Button("Remove", role: .destructive) { if model.remove(path: row.path) { close() } }
        } message: {
            Text(projectRemovalWords)
        }
        .confirmationDialog("Remove \(row.name)?", isPresented: $choosingRemove, titleVisibility: .visible) {
            Button("Remove from Carrier") { if model.remove(path: row.path) { close() } }
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
        return SettingsGroup(title: "Carrier") {
            SettingsTabRow(title: "Let Carrier watch this project", detail: watch.detail, first: true, problem: watch.problem) {
                Toggle("Let Carrier watch this project", isOn: Binding(get: { watch.isOn }, set: { $0 ? setWatching(true) : (confirmingStop = true) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(watch.canChange == false)
            }
        }
    }

    /// Writes the engine config like the Repos page does and asks the engine to reload; a refusal is shown on the row.
    private func setWatching(_ on: Bool) {
        guard let repo = row.repo else { return }
        watchFailure = saveWatch(on, repo: repo, path: configFilePath()).problem
        reloadWatched()
    }

    /// The Worktrees and disk group: the total and a bar, then the main clone and each worktree Carrier made with its size. The worktrees are asked of the host when
    /// the page opens, and so is a fresh measure; the last known figure stays on show meanwhile.
    @ViewBuilder private var worktreesGroup: some View {
        let figure = model.disk[(row.path as NSString).expandingTildeInPath]
        let measuring = model.measuring.contains((row.path as NSString).expandingTildeInPath)
        SettingsGroup(title: "Worktrees and disk", footer: "The worktrees Carrier made for sessions of this project, and what each folder takes on disk.") {
            if let worktrees {
                let items = worktreeRows(worktrees, sizes: figure?.parts ?? [:], now: Date())
                let shares = diskShares(items)
                SettingsTabRow(title: "Total", detail: diskTotalWords(figure, measuring: measuring, now: Date()), first: true) {
                    HStack(spacing: 8) {
                        if measuring { ProgressView().controlSize(.small) }
                        Text(figure?.bytes.map(formatDiskSize) ?? "—").fontWeight(.medium).monospacedDigit()
                    }
                }
                if shares.isEmpty == false {
                    DiskBar(shares: shares, color: { diskColor($0, in: items) })
                        .padding(.vertical, 10).frame(maxWidth: .infinity)
                        .overlay(alignment: .top) { SettingsDivider() }
                }
                ForEach(items) { item in
                    SettingsTabRow(title: item.branch, detail: item.detail, mono: true, problem: removeProblems[item.id]) {
                        HStack(spacing: 10) {
                            if let state = item.state, let kind = item.kind { StatusChip(text: state, tint: worktreeTint(kind)) }
                            if item.hasRemove {
                                Button { Task { await removeWorktree(item.id) } } label: { Label("Remove", icon: .trash) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                                    .disabled(item.removeBlockedBy != nil || removing.contains(item.id))
                                    .help(item.removeBlockedBy ?? "Removes this worktree's folder; its branch and its session stay")
                                    .accessibilityLabel("Remove the worktree \(item.branch)")
                            }
                            HStack(spacing: 6) {
                                Circle().fill(diskColor(item.id, in: items)).frame(width: 7, height: 7).accessibilityHidden(true)
                                Text(item.size).font(.scaled(12)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
                if let cleanup, let words = cleanUpWords(cleanup) {
                    SettingsTabRow(title: "Clean up", detail: "Merged worktrees nothing blocks: \(words)") {
                        Button { confirmingCleanup = true } label: { Label("Clean up", icon: .trash) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .disabled(removing.isEmpty == false)
                    }
                }
                if let cleanUpNote {
                    SettingsTabRow(title: "Last clean up", detail: cleanUpNote, wrapsDetail: true) { EmptyView() }
                }
            } else if let worktreesProblem {
                SettingsTabRow(title: "Worktrees", detail: "", first: true, problem: worktreesProblem) { EmptyView() }
            } else {
                SettingsTabRow(title: "Worktrees", detail: "", first: true) { ProgressView().controlSize(.small) }
            }
        }
    }

    /// The colour of a folder in the bar and before its size: the main clone the theme's accent, then one for each worktree, round again after six.
    private func diskColor(_ id: String, in items: [WorktreeRow]) -> Color {
        let palette: [Color] = [.themeAccent, .teal, .indigo, .purple, .pink, .mint]
        return palette[(items.firstIndex { $0.id == id } ?? 0) % palette.count]
    }

    /// What the alert of Clean up says it takes and leaves.
    private var cleanUpQuestionWords: String { "Their folders go, with what git ignores in them. Their branches and their sessions stay, and a session's next message brings its folder back." }

    private func worktreeTint(_ state: ProjectWorktree.State) -> Color {
        switch state {
        case .sessionOpen: .accentColor
        case .merged: .green
        case .uncommitted, .notPushed: .orange
        case .clean: .secondary
        }
    }

    /// The question or refusal that stops deleting a project from disk: `canConfirm` when it is unsaved work the person may accept, and not when it is a session that is open or a failure.
    private struct DeletionAsk {
        let title: String
        let message: String
        var canConfirm = false
    }

    /// Asks the host again just now (`deletionCheck`) and goes on only when nothing refuses and the unsaved work, if any, was confirmed; a failed move leaves everything where it was.
    private func deleteFromDisk(confirmed: Bool) async {
        deleting = true
        defer { deleting = false }
        do {
            let (check, folders) = try await model.deletionCheck(of: row.path)
            if check.canGoOn == false {
                deletionAsk = DeletionAsk(title: "\(row.name) cannot be deleted yet", message: "\(check.refusals.joined(separator: "\n"))\n\nClose the sessions of the project first. Nothing was deleted.")
            } else if check.needsConfirmation && confirmed == false {
                deletionAsk = DeletionAsk(title: "\(row.name) has work that is not saved", message: "\(check.unsaved.joined(separator: "\n"))\n\nMoving it to the Trash keeps it there until the Trash is emptied.", canConfirm: true)
            } else {
                try model.deleteFromDisk(path: row.path, worktrees: folders)
                close()
            }
        } catch ControlError.remote(let words) {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: words)
        } catch let error as ProjectTrashError {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: error.words)
        } catch {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: "The chat host did not answer. Nothing was deleted.")
        }
    }

    /// A value of `defaults` as a select's: nil is the first entry, and choosing it takes the key out of the file.
    private func defaultBinding(_ key: ProjectDefaultKey, _ value: String?) -> Binding<String?> {
        Binding(get: { value }, set: { _ = model.setDefault(key, $0, path: row.path) })
    }

    /// What a new session here starts with, as the project's entry has it; no agent is the same as everywhere.
    private var projectStart: NewSessionStart {
        let own = row.defaults
        return NewSessionStart(agent: own.agent ?? "", model: own.model ?? "", effort: own.effort ?? "", access: own.access)
    }

    /// The same panel as Settings > Sessions: provider, model, reasoning and access. Its first row is "Same as everywhere", which writes nothing.
    private var startPicker: some View {
        let own = projectStart
        let access = NewSessionStart.json(fromAccess: own.access)
        return ModelPickerButton(
            provider: own.agent.isEmpty ? nil : own.agent, model: own.model.isEmpty ? nil : own.model, effort: own.effort,
            accounts: startPickerAccounts(catalog), catalog: catalog, showsAccess: false,
            accessScales: accessScalesOfStart(catalog: catalog, agent: own.agent.isEmpty ? everywhereAgent : own.agent, access: access),
            chooseAccess: { option, value in
                var start = namedStart()
                start.access[option] = value
                _ = model.setStart(start, path: row.path)
            },
            effortFallback: (label: "Same as everywhere", detail: "Follows Settings > Sessions."), inherited: PickerInherited(
                provider: everywhereAgent.isEmpty ? nil : everywhereAgent, model: everywhereModel.isEmpty ? nil : everywhereModel,
                effort: everywhereEffort.isEmpty ? nil : everywhereEffort, follows: "Settings > Sessions"
            ),
            allowsDefaultModel: true
        ) { pick in
            var start = projectStart
            switch pick {
            case .account(let agent, let model):
                // the reasoning and access are the provider's own: another provider starts over
                if agent != start.agent { start.effort = ""; start.access = [:] }
                start.agent = agent
                start.model = model ?? ""
            case .effort(let level):
                start = namedStart()
                start.effort = level
            case .inherit, .none: start = NewSessionStart()
            }
            _ = model.setStart(start, path: row.path)
        }
        .task { await catalog.load() }
    }

    /// The project's start with an agent named: one still on "Same as everywhere" takes what that is now (the first provider that can work when
    /// Settings > Sessions names none), so a reasoning or access level can be set on it.
    private func namedStart() -> NewSessionStart {
        var start = projectStart
        guard start.agent.isEmpty else { return start }
        start.agent = everywhereAgent.isEmpty ? (catalog.agents.first { $0.found }?.name ?? "") : everywhereAgent
        start.model = start.agent == everywhereAgent ? everywhereModel : ""
        return start
    }

    private var workInOptions: [(value: String?, title: String)] {
        [(nil, "Default")] + ProjectPage(for: row).workIn.map { ($0.projectValue, $0 == .baseFolder ? "Base folder" : "New worktree") }
    }

    private var branchOptions: [(value: String?, title: String)] {
        var names: [String] = []
        for branch in branches {
            let name = branch.remote && branch.name.hasPrefix("origin/") ? String(branch.name.dropFirst("origin/".count)) : branch.name
            if names.contains(name) == false { names.append(name) }
        }
        if let named = row.defaults.baseBranch, names.contains(named) == false { names.append(named) }
        return [(nil, "Default branch")] + names.map { ($0, $0) }
    }

    private func loadWorktrees() async {
        guard row.status == .ready else { return }
        do {
            let listed = try await model.worktrees(of: row.path)
            worktrees = listed
            worktreesProblem = nil
            // measuring what Clean up takes walks the folders, so only a project with a merged worktree asks
            cleanup = listed.worktrees.contains { $0.state == .merged } ? try? await model.cleanUpWorktrees(of: row.path, run: false) : nil
        } catch ControlError.remote(let words) {
            worktreesProblem = words
        } catch {
            worktreesProblem = "The chat host did not answer."
        }
    }

    /// Removes one worktree's folder; the host's reason for refusing it stays in that row until the next try.
    private func removeWorktree(_ path: String) async {
        removing.insert(path)
        defer { removing.remove(path) }
        do {
            try await model.removeWorktree(path, of: row.path)
            removeProblems[path] = nil
            cleanUpNote = nil
        } catch ControlError.remote(let words) {
            removeProblems[path] = words
        } catch {
            removeProblems[path] = "The chat host did not answer."
        }
        // what is left of the project is measured again, so the total and the bar follow the folders that went
        await model.refreshDisk(.now, of: [row.path])
        await loadWorktrees()
    }

    private func runCleanup() async {
        guard let cleanup else { return }
        removing = Set(cleanup.removed.map(\.path))
        defer { removing = [] }
        do {
            cleanUpNote = cleanUpReport(try await model.cleanUpWorktrees(of: row.path, run: true))
            removeProblems = [:]
        } catch ControlError.remote(let words) {
            cleanUpNote = words
        } catch {
            cleanUpNote = "The chat host did not answer."
        }
        // what is left of the project is measured again, so the total and the bar follow the folders that went
        await model.refreshDisk(.now, of: [row.path])
        await loadWorktrees()
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
        if model.locate(path: row.path, to: url.path) { moved(url.path) }
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
            model.setPinned(!pinned, path: path)
        }
    }

    private func addTag() {
        let candidate = newTag
        newTag = ""
        guard addingProjectTag(candidate, to: row.tags) != row.tags else { return }
        model.addTag(candidate, path: row.path)
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
            if ProjectIconStore.canRead(url) {
                model.setIconImage(from: url, path: path)
            } else if let rasterized = rasterizedImage(at: url) {
                model.setIconImage(cgImage: rasterized, path: path)
            } else {
                model.setIconImage(from: url, path: path)
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

/// The project's Name field: writes on Return or focus loss, reverts on failure, updates when another process changes `projects.json`, and
/// clears `name` (falling back to the folder's name) when emptied.
private struct ProjectNameField: View {
    let stored: String
    let prompt: String
    let commit: (String) -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(stored: String, prompt: String, commit: @escaping (String) -> Bool) {
        self.stored = stored
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: stored)
    }

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .settingsField(width: settingsSelectWidth, focused: $focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .onChange(of: stored) { _, now in if focused == false { draft = now } }
            .onDisappear(perform: save)
            .accessibilityLabel("Name")
    }

    private func save() {
        let next = normalizedProjectName(draft) ?? ""
        let current = normalizedProjectName(stored) ?? ""
        if next == current {
            draft = current
            return
        }
        if commit(draft) {
            draft = next
        } else {
            draft = stored
        }
    }
}

/// A tag capsule with a cross button to remove it.
private struct ProjectTagChip: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(tag).font(.scaled(12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Button(action: remove) {
                Glyph(.close, size: 9, bold: true).foregroundStyle(.secondary)
                    .frame(width: 16, height: 16).background(Circle().fill(Color.primary.opacity(0.12))).contentShape(Circle())
            }
            .buttonStyle(.plain).help("Remove \(tag)").accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// The Change… popover for a project's icon: eight colours, eight marks and Choose image…, matching `AccountEditor`'s 30 pt grid.
private struct ProjectIconPopover: View {
    let selectedColor: ProjectColor?
    let selectedMark: AppIcon?
    let hasImage: Bool
    let setColor: (ProjectColor?) -> Void
    let setMark: (AppIcon?) -> Void
    let chooseImage: () -> Void
    let reset: () -> Void

    private static let tile: CGFloat = 30, gap: CGFloat = 8, columns = 8
    private static let gridWidth = CGFloat(columns) * tile + CGFloat(columns - 1) * gap
    private var grid: [GridItem] { Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.gap), count: Self.columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Color").sectionLabel()
                    Spacer(minLength: 8)
                    if selectedColor != nil || selectedMark != nil || hasImage {
                        Button("Reset", action: reset).buttonStyle(HoverTextButtonStyle(tint: nil)).font(.scaled(11))
                    }
                }
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(ProjectColor.allCases, id: \.self) { choice in
                        let on = hasImage == false && selectedColor == choice
                        let name = choice.rawValue.capitalized
                        Button { setColor(on ? nil : choice) } label: {
                            Circle().fill(choice.color)
                                .frame(width: 20, height: 20).padding(5)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(on ? 1 : 0))
                                .frame(width: Self.tile, height: Self.tile)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Mark").sectionLabel()
                let tint = (hasImage ? nil : selectedColor)?.color ?? Color.primary
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(projectIconMarks, id: \.self) { choice in
                        let on = hasImage == false && selectedMark == choice
                        let name = choice.rawValue.capitalized
                        Button { setMark(on ? nil : choice) } label: {
                            Glyph(choice, size: 15).foregroundStyle(tint)
                                .frame(width: Self.tile, height: Self.tile)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            SettingsDivider()
            Button(action: chooseImage) {
                Label("Choose image…", icon: .photo).labelStyle(.titleAndIcon)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .controlSize(.small)
        }
        .frame(width: Self.gridWidth, alignment: .leading)
    }
}

/// A project's Actions screen (docs/specs/projects.md, Scope 16; docs/adr/0039): two groups (`New worktree` and `After clone`), each listing
/// its actions and ending in Add action. Valid edits write at once to `projects.json`; a blank name or command is not written and shows as a problem.
private struct ProjectActionsView: View {
    let savedActions: [ProjectAction]
    let save: ([ProjectAction]) -> Bool

    @State private var drafts: [ProjectActionDraft]
    @State private var savedById: [UUID: ProjectAction]
    @State private var lastWritten: [ProjectAction]

    init(savedActions: [ProjectAction], save: @escaping ([ProjectAction]) -> Bool) {
        self.savedActions = savedActions
        self.save = save
        let initial = savedActions.map { ProjectActionDraft(action: $0) }
        _drafts = State(initialValue: initial)
        _savedById = State(initialValue: Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.action) }))
        _lastWritten = State(initialValue: savedActions)
    }

    var body: some View {
        Group {
            group(
                when: .newWorktree,
                footer: "Runs in order when a session creates a new worktree, and again when a cleaned one comes back."
            )
            group(
                when: .afterClone,
                footer: "Runs in order in the folder right after a repository is cloned."
            )
        }
        .writingToolsBehavior(.disabled)
        .onChange(of: drafts) { commit() }
        .onChange(of: savedActions) { syncExternal($1) }
    }

    private func group(when: ProjectActionWhen, footer: String) -> some View {
        let items = drafts.filter { $0.action.when == when }
        return SettingsGroup(title: when.title, footer: footer) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                actionRows(item, first: offset == 0)
            }
            Button { add(when) } label: { Label("Add action", icon: .plus).labelStyle(.titleAndIcon) }
                .buttonStyle(HoverTextButtonStyle(tint: nil))
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { if items.isEmpty == false { SettingsDivider() } }
        }
    }

    @ViewBuilder private func actionRows(_ item: ProjectActionDraft, first: Bool) -> some View {
        let problems = projectActionProblems(item.action)
        let label = item.action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = label.isEmpty ? "action" : label
        SettingsTabRow(title: "Name", detail: "", first: first, problem: problems[.name]) {
            HStack(spacing: 10) {
                TextField("", text: binding(item.id, \.name), prompt: Text("Install dependencies"))
                    .accessibilityLabel("Name").settingsField(width: 200)
                Toggle("On", isOn: binding(item.id, \.on))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel("Enable \(named)")
                    .help(item.action.on ? "Turn off" : "Turn on")
                IconButton(icon: .trash, name: "Delete \(named)") { delete(item.id) }
            }
        }
        .accessibilityElement(children: .contain)
        SettingsTabRow(title: "Command", detail: "Runs with sh -c", problem: problems[.command]) {
            TextField("", text: binding(item.id, \.command), prompt: Text("pnpm install"))
                .font(.scaled(11.5, design: .monospaced))
                .accessibilityLabel("Command")
                .settingsField(width: 282)
                .writingToolsBehavior(.disabled)
        }
        .accessibilityElement(children: .contain)
        SettingsTabRow(title: "If it fails", detail: "") {
            ChoicePopUp(
                label: "If it fails",
                options: ProjectActionOnFail.allCases.map { (value: $0, title: $0.title) },
                selection: binding(item.id, \.onFail)
            )
        }
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<ProjectAction, Value>) -> Binding<Value> {
        Binding(
            get: { drafts.first { $0.id == id }?.action[keyPath: keyPath] ?? ProjectAction(when: .newWorktree)[keyPath: keyPath] },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                drafts[index].action[keyPath: keyPath] = value
            }
        )
    }

    private func add(_ when: ProjectActionWhen) {
        drafts.append(ProjectActionDraft(action: ProjectAction(when: when)))
    }

    private func delete(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        savedById.removeValue(forKey: id)
    }

    private func commit() {
        let toWrite = mergedProjectActions(drafts: drafts, saved: savedById)
        guard toWrite != lastWritten else { return }
        if save(toWrite) {
            lastWritten = toWrite
            let liveIds = Set(drafts.map(\.id))
            savedById = savedById.filter { liveIds.contains($0.key) }
            for draft in drafts where projectActionProblems(draft.action).isEmpty {
                savedById[draft.id] = draft.action
            }
        }
    }

    private func syncExternal(_ latest: [ProjectAction]) {
        guard latest != lastWritten else { return }
        let refreshed = latest.map { ProjectActionDraft(action: $0) }
        drafts = refreshed
        savedById = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0.action) })
        lastWritten = latest
    }
}

/// The bar of a project's disk: one segment for each folder, as wide as its share, in the colour of its dot.
struct DiskBar: View {
    let shares: [DiskShare]
    let color: (String) -> Color

    var body: some View {
        GeometryReader { geometry in
            let room = geometry.size.width - CGFloat(shares.count - 1)
            HStack(spacing: 1) {
                ForEach(shares) { share in color(share.id).frame(width: max(2, room * share.fraction)) }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(height: 8).accessibilityHidden(true)
    }
}
