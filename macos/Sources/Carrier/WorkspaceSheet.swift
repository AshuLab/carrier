import AppKit
import CarrierCore
import SwiftUI

/// Where a new session works, as a sheet (docs/specs/workspace-sources.md): the sources on the left, the one that is chosen on the right,
/// and a footer with the projects folder and Cancel. The model drives it (`step` and the lists); choosing a workspace closes the sheet, and
/// nothing is cloned or written until the first message is sent.
struct WorkspaceSheet: View {
    @Bindable var model: NewSessionModel
    /// Opens the Health tab of Settings.
    let openHealth: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?
    @State private var visibility = Visibility.all

    private enum Field { case url, project }
    private enum Visibility: String, CaseIterable { case all = "All", `public` = "Public", `private` = "Private" }

    /// One radius for every row, card and notice, so the sheet reads as one piece.
    private let radius: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .windowSheetSize()
    }

    // MARK: Rail

    /// The sheet's name, then where the workspace can come from: a step each, and the folder panel, which is not a step.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            RailHeader(title: "Choose a workspace", detail: "Where the agent works", icon: "folder.fill")
            railRow("Recent", "Folders you used lately", "clock", selected: model.step == .menu) { model.show(.menu) }
            if model.sources.contains(.githubURL) {
                railRow("From a GitHub URL", model.sourceReason(.githubURL) ?? "Clone owner/repo", "link", selected: model.step == .url, off: model.sourceReason(.githubURL) != nil) { model.show(.url) }
            }
            if model.sources.contains(.githubRepos) {
                railRow("My repositories", model.sourceReason(.githubRepos) ?? "Browse yours and clone one", "list.bullet", selected: model.step == .repos, off: model.sourceReason(.githubRepos) != nil) { Task { await model.showRepos() } }
            }
            if model.sources.contains(.newProject) {
                railRow("New project", "Start from an empty folder", "folder.badge.gearshape", selected: model.step == .project) { model.show(.project) }
            }
            if model.sources.contains(.localFolder) {
                Divider().padding(.vertical, 8)
                railRow("Open a folder…", "Any folder on this Mac", "folder.badge.plus", selected: false, action: openFolder)
            }
            if let gh = model.ghState {
                HealthFixButton(tool: .gh, state: gh).padding(.horizontal, 8).padding(.top, 8)
                if gh.blocks {
                    Button("Open Health in Settings") {
                        dismiss()
                        openHealth()
                    }
                    .buttonStyle(.link).font(.callout).padding(.horizontal, 8).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        // The header sits 24 from the top and 24 from the left (16 + the row's 8), as the step's header does on the right.
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 14).frame(width: 250)
        .background(Color.secondary.opacity(0.06))
    }

    private func railRow(_ title: String, _ detail: String, _ icon: String, selected: Bool, off: Bool = false, action: @escaping () -> Void) -> some View {
        RailRow(title: title, detail: detail, icon: icon, selected: selected, off: off, action: action)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive").foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Projects folder").font(.subheadline).foregroundStyle(.secondary)
                    Text((model.projectsPath as NSString).abbreviatingWithTildeInPath)
                        .font(.callout.monospaced()).lineLimit(1).truncationMode(.head).textSelection(.enabled)
                }
                Button("Change…", action: changeProjectsFolder).controlSize(.small).help("Where repositories are cloned and new projects are made")
                Spacer(minLength: 16)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let problem = model.projectsFolderProblem {
                notice(problem, "exclamationmark.triangle.fill", .red)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch model.step {
        case .menu: recentStep
        case .url: urlStep
        case .repos: reposStep
        case .project: projectStep
        }
    }

    /// A step's title and what it does, then its body.
    private func stepPage<Body: View>(_ title: String, _ detail: String, icon: String, @ViewBuilder _ body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.scaled(16, weight: .medium)).foregroundStyle(Color.themeAccent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: radius).fill(Color.themeAccent.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            body()
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The recent folders, then the ones already in the projects folder; with none of either, how to get a first one.
    private var recentStep: some View {
        stepPage("Recent", "Folders you have worked in. Pick one to start there.", icon: "clock") {
            if model.recent.isEmpty && model.projects.isEmpty {
                emptyState("clock", "No folders yet", "Folders you work in show up here. Open one, clone a repository or start a new project.") {
                    Button("Open a folder…", action: openFolder).buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if model.recent.isEmpty == false {
                            sectionLabel("Recent")
                            ForEach(model.recent, id: \.path) { folderRow($0.name, $0.path) }
                        }
                        if model.projects.isEmpty == false {
                            sectionLabel("In your projects folder").padding(.top, model.recent.isEmpty ? 0 : 12)
                            ForEach(model.projects, id: \.path) { folderRow($0.name, $0.path) }
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ name: String, _ path: String) -> some View {
        HoverRow(action: { dismiss(); Task { await model.choose(folder: path) } }) { hovering in
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(Color.themeAccent.opacity(0.8)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).fontWeight(.medium)
                    Text((path as NSString).abbreviatingWithTildeInPath).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 8)
                RowHint(text: "Open", shown: hovering)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
    }

    /// From a GitHub URL: the text and what will happen to it when the message is sent.
    private var urlStep: some View {
        stepPage("From a GitHub URL", "Bring in any repository you can read, by its name or address.", icon: "link") {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Repository", "magnifyingglass")
                TextField("owner/repo or https://github.com/owner/repo", text: $model.urlText)
                    .textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled()
                    .focused($focused, equals: .url).onSubmit(useRepo)
                if model.urlText.isEmpty == false && model.reference == nil {
                    notice("That does not look like a GitHub repository. Use owner/repo, or paste its github.com link.", "exclamationmark.triangle.fill", .orange)
                } else if model.alreadyThere {
                    notice("Already in your projects folder. It will be updated (fetch) when the message is sent, not cloned again.", "arrow.triangle.2.circlepath", .orange)
                } else if let reference = model.reference {
                    pathLine("Will be cloned when the message is sent, to", "\(model.projectsPath)/\(reference)")
                }
            }
            watchCard(for: "this repo", on: Binding(get: { model.watching }, set: { model.watch = $0 }), reason: model.watchProblem)
            howItWorks([
                ("person.badge.key", "Private repositories work too: Carrier uses your own GitHub sign-in (gh), never the engine's."),
                ("arrow.down.circle", "Nothing is cloned until you send the first message. A repository is cloned once; next time it is only fetched, and nothing in it is deleted."),
            ])
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Button(action: useRepo) { Label(model.repoButton, systemImage: model.alreadyThere ? "arrow.triangle.2.circlepath" : "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).disabled(model.canUseRepo == false)
            }
        }
        .onAppear { focused = .url }
    }

    /// My repositories: a search and a filter over what is loaded, the rows (each says whether it is private and whether Carrier watches
    /// it), a notice while the list is partial with Load more, and the watch box under the list; choosing a row fills the plan with it.
    private var reposStep: some View {
        stepPage("My repositories", model.login.map { "Signed in to GitHub as \($0)." } ?? "The repositories your GitHub account can read.", icon: "list.bullet") {
            if model.repoList.blocked {
                emptyState("exclamationmark.icloud", "GitHub did not answer", model.reposReason ?? "Check your connection and sign-in, then try again.", tint: .orange) {
                    Button { Task { await model.loadRepos() } } label: { Label("Try again", systemImage: "arrow.clockwise") }.disabled(model.loadingRepos)
                }
            } else if model.repoList.repos.isEmpty && model.loadingRepos {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your repositories…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchField
                let rows = model.repoRows().filter { visibility == .all || (visibility == .private) == $0.isPrivate }
                if rows.isEmpty {
                    reposEmpty
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(rows) { repoRow($0) }
                            if model.repoList.hasMore {
                                VStack(spacing: 8) {
                                    Text("\(model.repoList.repos.count) loaded, there are more. Search and the filter only look at these.").font(.subheadline).foregroundStyle(.secondary)
                                    loadMoreButton
                                    if model.repoList.problem != nil, let reason = model.reposReason {
                                        notice(reason, "exclamationmark.triangle.fill", .red)
                                    }
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                        }
                    }
                }
                watchCard(for: "the repo I choose", on: $model.watch, reason: nil)
                Label("Click a repository to work there. It is cloned when you send the first message.", systemImage: "cursorarrow.click").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// One field: a magnifier, the text, and the visibility filter as a menu at its end (it shows its choice while it is not All).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search the loaded repositories", text: $model.reposQuery).textFieldStyle(.plain).autocorrectionDisabled()
            Menu {
                Picker("Show", selection: $visibility) {
                    ForEach(Visibility.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    if visibility != .all { Text(visibility.rawValue).font(.subheadline.weight(.semibold)) }
                    Image(systemName: visibility == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .foregroundStyle(visibility == .all ? Color.secondary : Color.themeAccent)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Show all, public or private repositories")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: radius).fill(Color.secondary.opacity(0.12)))
    }

    /// The list has nothing to show: because there are no repositories, or because the search or the filter left none.
    @ViewBuilder private var reposEmpty: some View {
        let more = model.repoList.hasMore
        if model.reposQuery.isEmpty && visibility == .all {
            emptyState("tray", "No repositories", "Your account has none Carrier can list. Use From a GitHub URL for one by name.") {
                Button { model.show(.url) } label: { Label("From a GitHub URL", systemImage: "link") }
            }
        } else if model.reposQuery.isEmpty {
            emptyState(visibility == .private ? "lock.slash" : "globe", "No \(visibility.rawValue.lowercased()) repositories loaded", more ? "Load more to look further." : "Your account has none.") {
                if more { loadMoreButton }
            }
        } else {
            emptyState("magnifyingglass", "No match for “\(model.reposQuery)”", more ? "Search only looks at the \(model.repoList.repos.count) loaded. Load more, or use the URL." : "Nothing loaded matches.") {
                if more { loadMoreButton }
            }
        }
    }

    private var loadMoreButton: some View {
        Button { Task { await model.loadRepos() } } label: {
            Label(model.loadingRepos ? "Loading…" : model.repoList.problem != nil ? "Try again" : "Load more", systemImage: "arrow.down")
        }
        .disabled(model.loadingRepos)
    }

    private func repoRow(_ row: GithubRepoRow) -> some View {
        HoverRow(action: { dismiss(); Task { await model.choose(repo: row.name) } }) { hovering in
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "book.closed").foregroundStyle(.secondary).frame(width: 18).padding(.top, 2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        let parts = row.name.split(separator: "/", maxSplits: 1).map(String.init)
                        Text("\(Text(parts[0] + "/").foregroundStyle(.secondary))\(Text(parts[1]).fontWeight(.semibold))").lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            if row.isPrivate { badge("Private", "lock.fill", .indigo) } else { badge("Public", "globe", .secondary) }
                            Text(row.pushed).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let reason = row.cannotWatch {
                            Label("Carrier will not watch it: \(reason)", systemImage: "eye.slash").font(.subheadline).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 8)
                if row.watched { badge("Watched", "eye.fill", .green) }
                RowChevron(shown: hovering)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .accessibilityLabel("\(row.name), \(row.isPrivate ? "private" : "public")\(row.watched ? ", watched" : "")")
    }

    /// New project: a name, the path it will make, and the button; no watch box, a new project has no GitHub repository.
    private var projectStep: some View {
        stepPage("New project", "Start from nothing: an empty folder with git ready.", icon: "folder.badge.gearshape") {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Name", "textformat")
                TextField("my-project", text: $model.projectName)
                    .textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled()
                    .focused($focused, equals: .project).onSubmit(create)
                if let warning = model.projectNameWarning {
                    notice(warning, "exclamationmark.triangle.fill", .orange)
                } else {
                    pathLine("Will be created when the message is sent, at", model.projectPath)
                }
            }
            howItWorks([
                ("terminal", "When you send the first message, Carrier makes the folder and runs git init on main."),
                ("icloud.slash", "It stays on this Mac. It has no GitHub repository, so Carrier does not watch it."),
            ])
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Button(action: create) { Label("Use this project", systemImage: "plus.circle") }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).disabled(model.canUseNow == false)
            }
        }
        .onAppear { focused = .project }
    }

    // MARK: Pieces

    /// The watch box, with what watching means: it is a choice made now and acted on once the agent has answered the first message, and the engine hears of it at its next start.
    private func watchCard(for what: String, on: Binding<Bool>, reason: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: on.wrappedValue && reason == nil ? "eye.fill" : "eye.slash")
                .foregroundStyle(on.wrappedValue && reason == nil ? Color.green : .secondary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Let Carrier watch \(what)")
                Text(reason ?? "Carrier looks for epics marked ready and solves them with its agents. It starts listening the next time Carrier starts.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("Let Carrier watch \(what)", isOn: on).labelsHidden().toggleStyle(.switch)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: radius).fill(Color.secondary.opacity(0.08)))
        .disabled(reason != nil)
    }

    /// A few lines on how the step works, each with its icon.
    private func howItWorks(_ points: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(points, id: \.1) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.scaled(13, weight: .medium)).foregroundStyle(Color.themeAccent)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: radius).fill(Color.themeAccent.opacity(0.16)))
                        .accessibilityHidden(true)
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: radius).fill(Color.secondary.opacity(0.08)))
    }

    /// A path and what it is, on a faint fill.
    private func pathLine(_ label: String, _ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text((path as NSString).abbreviatingWithTildeInPath).font(.subheadline.monospaced()).lineLimit(1).truncationMode(.head).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: radius).fill(Color.secondary.opacity(0.08)))
    }

    private func fieldLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// Nothing to show, said once: an icon, what it is, what to do, and the button that does it.
    private func emptyState<Action: View>(_ icon: String, _ title: String, _ detail: String, tint: Color = .secondary, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.scaled(32, weight: .light)).foregroundStyle(tint).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                .frame(maxWidth: 380)
            action().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A message with its icon on a faint fill of its colour.
    private func notice(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.subheadline).padding(10)
        .background(RoundedRectangle(cornerRadius: radius).fill(tint.opacity(0.12)))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 2)
    }

    private func badge(_ text: String, _ icon: String, _ tint: Color) -> some View { Badge(text: text, icon: icon, tint: tint) }

    // MARK: Actions

    private func create() {
        if model.useProject() { dismiss() }
    }

    private func useRepo() {
        guard model.canUseRepo else { return }
        Task { if await model.useRepo() { dismiss() } }
    }

    /// The footer's Change…: the folder panel over the sheet, which then shows the new path or why it was refused.
    private func changeProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.projectsPath)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.changeProjectsFolder(to: url.path) }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { dismiss(); Task { await model.choose(folder: url.path) } }
    }
}
