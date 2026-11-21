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

    // MARK: a project

    @ViewBuilder private func projectScreen(_ row: ProjectRow) -> some View {
        let exists = FileManager.default.fileExists(atPath: (row.path as NSString).expandingTildeInPath)
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
