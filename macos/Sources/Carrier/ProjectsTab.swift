import AppKit
import CarrierCore
import SwiftUI

/// The Projects page of Settings (docs/specs/projects.md): the person's projects, one row each, and Add project, which takes a folder of the Mac. A row opens
/// the project as a screen of its own, a place of the window's history (‹ ›) named by its path. The rows are `ProjectsModel`'s, which follows `projects.json`;
/// the page has no automated test of its own.
struct ProjectsTabView: View {
    let place: SettingsPlace
    let go: (SettingsPlace) -> Void
    @State private var model = ProjectsModel()

    var body: some View {
        let chosen = place.path.first.flatMap { path in model.rows.first { $0.path == path } }
        SettingsPageBody {
            if model.problems.isEmpty {
                if let failure = model.failure { ProblemLine(text: failure) }
                if let chosen { projectScreen(chosen) } else { list }
            } else {
                problems
            }
        }
        .preference(key: SettingsTitleKey.self, value: chosen.map { SettingsTitle(text: $0.name, subtitle: $0.line) })
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
                        title: row.name, detail: row.line, leading: ProjectIcon(tile: row.tile), first: index == 0,
                        action: { open(row.path) }
                    ) {
                        if row.pinned { Glyph(.pinFilled, size: 11, label: "Pinned").foregroundStyle(.secondary) }
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

    // MARK: a project

    @ViewBuilder private func projectScreen(_ row: ProjectRow) -> some View {
        ProjectDetailView(row: row, model: model).id(row.path)
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

/// One project's screen: its Identity group (name, icon colour and mark, tags), its Pin action in the page's header, and its folder and remote.
private struct ProjectDetailView: View {
    let row: ProjectRow
    let model: ProjectsModel
    @Environment(\.settingsHeaderAction) private var headerAction
    @State private var owner = UUID()
    @State private var pickingIcon = false
    @State private var newTag = ""

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: (row.path as NSString).expandingTildeInPath)
        Group {
            SettingsGroup(title: "Identity") {
                SettingsTabRow(title: "Name", detail: "Empty uses the folder's name", first: true) {
                    ProjectNameField(stored: row.customName ?? "", prompt: row.folderName) { model.setName($0, path: row.path) }
                }
                SettingsTabRow(title: "Icon", detail: "Color and mark; initials when none is chosen") {
                    HStack(spacing: 10) {
                        ProjectIcon(tile: row.tile)
                        Button("Change…") { pickingIcon = true }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .accessibilityLabel("Change the icon")
                            .accessibilityValue(iconSummary)
                            .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                                ProjectIconPopover(
                                    selectedColor: row.iconColor,
                                    selectedMark: row.iconMark,
                                    setColor: { model.setIconColor($0, path: row.path) },
                                    setMark: { model.setIconMark($0, path: row.path) },
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
        .writingToolsBehavior(.disabled)
        .onAppear(perform: publishPin)
        .onChange(of: row.pinned) { publishPin() }
        .onChange(of: row.path) { publishPin() }
        .onDisappear { headerAction?.clear(owner) }
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
        let color = row.iconColor?.rawValue.capitalized ?? "Automatic color"
        let mark = row.iconMark?.rawValue.capitalized ?? "initials"
        return "\(color), \(mark)"
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

/// The Change… popover for a project's icon: eight colours and eight marks, matching `AccountEditor`'s 30 pt grid.
private struct ProjectIconPopover: View {
    let selectedColor: ProjectColor?
    let selectedMark: AppIcon?
    let setColor: (ProjectColor?) -> Void
    let setMark: (AppIcon?) -> Void
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
                    if selectedColor != nil || selectedMark != nil {
                        Button("Reset", action: reset).buttonStyle(HoverTextButtonStyle(tint: nil)).font(.scaled(11))
                    }
                }
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(ProjectColor.allCases, id: \.self) { choice in
                        let on = selectedColor == choice
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
                let tint = selectedColor?.color ?? Color.primary
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(projectIconMarks, id: \.self) { choice in
                        let on = selectedMark == choice
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
        }
        .frame(width: Self.gridWidth, alignment: .leading)
    }
}
