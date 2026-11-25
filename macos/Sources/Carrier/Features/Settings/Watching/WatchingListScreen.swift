import CarrierCore
import SwiftUI

/// The first screen of Watching: one group of rows, as Projects' list is, with no line of column titles. Each repo is a row with the project's tile and a dot for its
/// health, `owner/name`, under it the project that has it and what its last check said, at the right what it has in flight, and a chevron that opens its screen.
/// The order is `watchingOrder`; with nothing watched the screen is an empty state. Watch a project and Check now are the toolbar's.
struct WatchingListScreen: View {
    let rows: [RepoRow]
    /// The name of the project that has the repo as its `origin`; nil when none does.
    let projectName: (RepoRow) -> String?
    let open: (RepoRow) -> Void
    let watch: () -> Void

    /// The title of the group of rows.
    static let group = "Repositories"

    var body: some View {
        SettingsGroup(id: "repositories", title: rows.isEmpty ? "" : Self.group) {
            if rows.isEmpty {
                EmptyStateView(
                    icon: .inbox, title: "Carrier isn\u{2019}t watching anything",
                    line: "Pick a project and Carrier takes its ready epics, runs the author and the reviewer, and leaves them for you to test.",
                    action: (title: "Watch a project…", run: watch), actionIcon: .plus, actionStyle: .accentGlass
                )
                .frame(minHeight: 260)
            } else {
                ForEach(rows) { row in
                    WatchingRowView(row: row, projectName: projectName(row)) { open(row) }
                }
            }
        }
    }
}

/// A repo of the list.
private struct WatchingRowView: View {
    let row: RepoRow
    let projectName: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                tile
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1).truncationMode(.middle)
                    detail.font(.scaled(11)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chips
                Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.vertical, 10).frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the repository")
    }

    /// The project (or that there is none) and what the last check said, which is red when GitHub refused the repo.
    private var detail: Text {
        Text("\(projectName ?? "No project") \u{00B7} ").foregroundStyle(.secondary) + Text(row.line).foregroundStyle(row.health == .error ? Color.red : .secondary)
    }

    /// What the repo has in flight, as chips; none when nothing is or nobody knows (Carrier is stopped).
    @ViewBuilder private var chips: some View {
        if let epics = row.epics, epics.isNone == false {
            HStack(spacing: 4) {
                if epics.needsYou > 0 { StatusChip(text: "\(epics.needsYou) needs you", tint: .orange) }
                if epics.running > 0 { StatusChip(text: "\(epics.running) running", tint: .green) }
                if epics.queued > 0 { StatusChip(text: "\(epics.queued) queued", tint: .blue) }
            }
            .fixedSize()
        }
    }

    /// The owner dim, the name in bold.
    private var title: AttributedString {
        var owner = AttributedString(row.owner + "/")
        owner.foregroundColor = Color.secondary
        var repo = AttributedString(row.repo)
        repo.font = Font.scaled(13).weight(.semibold)
        return owner + repo
    }

    /// The project's icon (the repo's own letters when none has it), with the repo's health as a dot on its corner.
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            ProjectIcon(repo: row.name, name: row.repo, colorKey: projectColorKey(row.name))
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 3, y: 3)
        }
        .accessibilityElement().accessibilityLabel(health)
    }

    private var color: Color {
        switch row.health {
        case .ok: .green
        case .error: .red
        case .unknown: .gray
        }
    }

    private var health: String {
        switch row.health {
        case .ok: "Healthy"
        case .error: "Error"
        case .unknown: "Not checked"
        }
    }
}

/// Watch a project: the Projects Carrier can watch, searched by name or repository; a click watches it. A project it cannot watch is there, off, with the
/// reason. Add project… goes to the Projects page, where a folder is added or a repository cloned.
struct WatchPicker: View {
    let choices: [WatchChoice]
    let carrierFolder: String
    let watch: (String) -> Void
    let addProject: () -> Void
    @State private var query = ""

    private var shown: [WatchChoice] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.isEmpty == false else { return choices }
        return choices.filter { $0.project.name.lowercased().contains(needle) || ($0.project.repo ?? "").lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $query, prompt: Text("Search your projects")).accessibilityLabel("Search your projects").settingsField(icon: .search)
            if shown.isEmpty {
                Text(choices.isEmpty ? "Every project with a GitHub origin is watched." : "No project matches.").font(.scaled(12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shown) { choice in row(choice) }
                    }
                }
                .frame(maxHeight: 280)
            }
            Divider()
            HStack(spacing: 8) {
                Button(action: addProject) { Label("Add project…", icon: .folderPlus) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                Text("Clone one from GitHub or open a folder").font(.scaled(11)).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(width: 360)
    }

    private func row(_ choice: WatchChoice) -> some View {
        Button {
            if let repo = choice.project.repo, choice.canWatch { watch(repo) }
        } label: {
            HStack(spacing: 10) {
                ProjectIcon(tile: choice.project.tile, imageFolder: carrierFolder)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.project.name).lineLimit(1)
                    Text(choice.reason ?? choice.project.repo ?? "").font(.scaled(11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 6).padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .opacity(choice.canWatch ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(choice.canWatch == false)
        .accessibilityHint(choice.canWatch ? "Watches it" : (choice.reason ?? ""))
    }
}
