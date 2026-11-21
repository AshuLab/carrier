import AppKit
import CarrierCore
import SwiftUI

/// The Projects page of Settings (docs/specs/projects.md): the person's projects, one row each, and Add project, which takes a folder of the Mac. A row opens
/// the project as a screen of its own, a place of the window's history (‹ ›) named by its path, and Actions opens its actions screen. The rows are
/// `ProjectsModel`'s, which follows `projects.json`; the page has no automated test of its own.
struct ProjectsTabView: View {
    let place: SettingsPlace
    let go: (SettingsPlace) -> Void
    @State private var model = ProjectsModel()

    static let actionsPath = "actions"

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
        .preference(key: SettingsTitleKey.self, value: chosen.map {
            showingActions ? SettingsTitle(text: "Actions", subtitle: $0.name) : SettingsTitle(text: $0.name, subtitle: $0.line)
        })
        // the file is another process's too: the list follows it while the page is open
        .task { await model.follow() }
    }

    // MARK: the list

    @ViewBuilder private var list: some View {
        if model.rows.isEmpty {
            SettingsGroup(title: "") {
                EmptyStateView(
                    icon: .folder, title: "No projects yet", line: "Add a folder you work in and it shows here.",
                    action: (title: "Add project", run: add), actionIcon: .folderPlus, actionStyle: .accentGlass
                )
                .frame(minHeight: 260)
            }
        } else {
            HStack {
                Spacer(minLength: 8)
                Button(action: add) { Label("Add project", icon: .folderPlus).labelStyle(.titleAndIcon) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
            SettingsGroup(title: "") {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    NavigationRow(
                        title: row.name, detail: row.line, leading: ProjectIcon(name: row.name, colorKey: row.colorKey), first: index == 0,
                        action: { open(row.path) }
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    /// The system's folder panel; a folder that already is a project opens that project and writes nothing.
    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose the folder of a project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if case .existing(let path)? = model.add(folder: url.path) { open(path) }
    }

    private func open(_ path: String) { go(SettingsPlace(.projects, path: [path])) }

    private func openActions(_ path: String) { go(SettingsPlace(.projects, path: [path, Self.actionsPath])) }

    // MARK: a project

    @ViewBuilder private func projectScreen(_ row: ProjectRow) -> some View {
        let exists = FileManager.default.fileExists(atPath: (row.path as NSString).expandingTildeInPath)
        SettingsGroup(title: "") {
            NavigationRow(title: "Actions", detail: "Commands run for a new worktree or after a clone", first: true, action: { openActions(row.path) }) {
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
            SettingsTabRow(title: "Remote", detail: row.repo ?? "No GitHub remote", mono: row.repo != nil) {
                if let repo = row.repo, let url = URL(string: "https://github.com/\(repo)") {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Open on GitHub", icon: .externalLink).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
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
                    .labelsHidden().toggleStyle(.switch)
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
