import AppKit
import CarrierCore
import CarrierUI
import SwiftUI
import UniformTypeIdentifiers

extension ProjectsModel {
    /// The app's one reading of `projects.json`: the Projects page edits it and the sidebar, the lists and the cards draw from it.
    static let shared = ProjectsModel(host: SocketChatHost(configLauncher: .app))
}

/// The Projects page of Settings (docs/specs/projects.md): the person's projects, one row each, and Add project, which takes a folder of the Mac. A row opens
/// the project as a screen of its own, a place of the window's history (‹ ›) named by its path, and Actions opens its actions screen. The rows are
/// `ProjectsModel`'s, which follows `projects.json`; the page has no automated test of its own.
struct ProjectsTabView: View {
    @Environment(\.pieceTheme) private var theme
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
                            save: { await model.saveActions(path: chosen.path, actions: $0) }
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
            showingActions ? SettingsTitle(text: Copy.projectsActionsTitle(), subtitle: $0.name) : SettingsTitle(text: $0.name, subtitle: $0.line())
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
                        icon: .folder, title: Copy.projectsNoneYet(), line: Copy.projectsNoneYetLine(),
                        action: (title: Copy.projectsAddProject(), run: { adding = true }), actionIcon: .folderPlus, actionStyle: .accentGlass
                    )
                    .frame(minHeight: 260)
                }
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s10) {
                    HStack(spacing: Tokens.Space.s10) {
                        TextField("", text: $query, prompt: Text(Copy.projectsSearch()))
                            .accessibilityLabel(Copy.projectsSearch())
                            .settingsField(icon: .search)
                        HStack(spacing: Tokens.Space.s6) {
                            Text(Copy.projectsGroup()).scaledFont(12).foregroundStyle(.secondary)
                            ChoicePopUp(
                                label: Copy.projectsGroup(),
                                options: ProjectGrouping.allCases.map { (value: $0, title: $0.title()) },
                                selection: $groupBy
                            )
                        }
                        Button { adding = true } label: { Label(Copy.projectsAddProject(), icon: .folderPlus).labelStyle(.titleAndIcon) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                    FlowLayout(spacing: Tokens.Space.s6) {
                        FilterChip(title: Copy.projectsFilterAll(), on: filter == .all) { filter = .all }
                        ForEach(tags, id: \.self) { tag in
                            FilterChip(title: tag, on: filter == .tag(tag)) {
                                filter = filter == .tag(tag) ? .all : .tag(tag)
                            }
                        }
                        FilterChip(title: Copy.projectsFilterWatched(), on: filter == .watched) {
                            filter = filter == .watched ? .all : .watched
                        }
                        FilterChip(title: Copy.projectsFilterLocalOnly(), on: filter == .localOnly) {
                            filter = filter == .localOnly ? .all : .localOnly
                        }
                        FilterChip(title: Copy.projectsFilterHidden(), on: filter == .hidden) {
                            filter = filter == .hidden ? .all : .hidden
                        }
                    }
                }
                if groups.isEmpty {
                    SettingsGroup(title: "") {
                        EmptyStateView(
                            icon: .search, title: Copy.projectsNothingMatches(), line: Copy.projectsNothingMatchesLine(),
                            action: (title: Copy.projectsClearFilters(), run: { query = ""; filter = .all }), actionIcon: .close
                        )
                        .frame(minHeight: 220)
                    }
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                        SettingsGroup(title: group.title ?? "") {
                            if groupIndex == 0 {
                                HStack(spacing: ProjectColumns.gap) {
                                    sortTitle(Copy.projectsColProject(), key: .name).frame(minWidth: ProjectColumns.project, maxWidth: .infinity, alignment: .leading)
                                    if columns.showsTags {
                                        Text(Copy.projectsColTags()).frame(width: ProjectColumns.tags, alignment: .leading).accessibilityHidden(true)
                                    }
                                    sortTitle(Copy.projectsColLastActive(), key: .lastActive).frame(width: ProjectColumns.lastActive, alignment: .leading)
                                    sortTitle(Copy.projectsColDisk(), key: .disk).frame(width: ProjectColumns.disk, alignment: .leading)
                                    if columns.showsCarrier {
                                        Text(Copy.projectsColCarrier()).frame(width: ProjectColumns.carrier, alignment: .leading).accessibilityHidden(true)
                                    }
                                    Color.clear.frame(width: ProjectColumns.trailing, height: 1)
                                }
                                .sectionLabel().padding(.vertical, Tokens.Space.s10)
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
            HStack(spacing: Tokens.Space.s3) {
                Text(title)
                if sorted { Glyph(order.ascending ? .chevronUp : .chevronDown, size: 8, bold: true).accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.projectsSortBy(title: title))
        .accessibilityValue(sorted ? (order.ascending ? Copy.projectsSortAscending() : Copy.projectsSortDescending()) : "")
    }

    /// A clone that is running or failed: it is not a project yet, so the row has no chevron and cannot be opened. It shows git's progress line, or the
    /// reason the clone failed in orange with a way to dismiss it.
    private func cloneRow(_ row: ProjectRow, _ clone: ProjectClone, divider: Bool) -> some View {
        HStack(spacing: Tokens.Space.s12) {
            ProjectIcon(tile: row.tile)
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                HStack(spacing: Tokens.Space.s6) {
                    Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                    switch clone.state {
                    case .cloning: StatusChip(text: Copy.projectsCloningChip(), tint: theme.accent)
                    case .failed: StatusChip(text: Copy.projectsFailedChip(), tint: .orange)
                    }
                }
                Text(row.line())
                    .scaledFont(11).foregroundStyle(clone.state == .failed ? Color.orange : .secondary)
                    .lineLimit(clone.state == .failed ? 3 : 1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clone.state == .failed {
                Button(Copy.projectsDismiss()) { Task { await model.dismissClone(clone.repo) } }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    .accessibilityLabel(Copy.projectsDismissClone(repo: clone.repo))
            }
        }
        .padding(.vertical, Tokens.Space.s10).frame(minHeight: 46)
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
                HStack(spacing: Tokens.Space.s12) {
                    ProjectIcon(tile: row.tile, imageFolder: model.carrierFolder)
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                        if let status = row.status.text() {
                            Label(status, icon: .warningFilled, size: 11).scaledFont(11).foregroundStyle(.orange).lineLimit(1)
                        } else if row.hidden {
                            Label(Copy.projectsHidden(), icon: .eyeOff, size: 11).scaledFont(11).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(row.line()).scaledFont(11).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
                            FlowLayout(spacing: Tokens.Space.s4) {
                                ForEach(row.tags, id: \.self) { tag in
                                    StatusChip(text: tag, tint: .secondary)
                                }
                            }
                        }
                    }
                    .frame(width: ProjectColumns.tags, alignment: .leading)
                }

                Text(row.lastActive.map { timeText($0, now: now) } ?? "—")
                    .scaledFont(12).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: ProjectColumns.lastActive, alignment: .leading)

                // the host's last figure, and a dash for a project it has not measured and always for a folder that is gone
                Text(row.diskBytes.map(formatDiskSize) ?? "—").scaledFont(12).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: ProjectColumns.disk, alignment: .leading)

                if columns.showsCarrier {
                    Text(row.carrierText())
                        .scaledFont(12).foregroundStyle(row.watched ? Color.primary : .secondary).lineLimit(1)
                        .frame(width: ProjectColumns.carrier, alignment: .leading)
                }

                HStack(spacing: Tokens.Space.s10) {
                    Spacer(minLength: 0)
                    if row.pinned { Glyph(.pinFilled, size: 11, label: Copy.projectsPinned()).foregroundStyle(.secondary) }
                    Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .frame(width: ProjectColumns.trailing, alignment: .trailing)
            }
            .padding(.vertical, Tokens.Space.s10).frame(minHeight: 46)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if divider { SettingsDivider() } }
        }
        .buttonStyle(.plain)
    }

    private var cloneDestinationLine: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            HStack(spacing: Tokens.Space.s6) {
                Text(Copy.projectsClonesGoTo())
                    .scaledFont(12)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text((model.projectsPath as NSString).abbreviatingWithTildeInPath)
                    .scaledFont(11.5, design: .monospaced)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(model.projectsPath)
                Button(Copy.projectsChange(), action: changeProjectsFolder)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .controlSize(.small)
                    .help(Copy.projectsChangeHelp())
                Spacer(minLength: 0)
            }
            if let problem = model.projectsFolderProblem {
                ProblemLine(text: problem)
            }
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.top, Tokens.Space.s2)
    }

    /// The system's folder panel for changing where new clones and new projects go (`projectsFolder` in `chat.json`).
    private func changeProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.projectsPath)
        panel.prompt = Copy.projectsChoose()
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.changeProjectsFolder(to: url.path) }
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
        SettingsGroup(title: "", footer: Copy.projectsProblemsFooter()) {
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                ForEach(Array(model.problems.enumerated()), id: \.offset) { _, problem in ProblemLine(text: problem.text()) }
            }
            .padding(.vertical, Tokens.Space.s10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
