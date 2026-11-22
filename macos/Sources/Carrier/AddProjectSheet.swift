import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// The shared sheet for choosing a folder or project (docs/specs/projects.md, "Add project"): one search/path field, suggested recent
/// folders, a pasted GitHub address or a search over the person's repositories (cloned with the host, the list showing the clone), drag and drop,
/// keyboard navigation, Open a folder… and New project…, which swaps the sheet for a form (a name and where it is made). Driven by `ProjectSheetMode`:
/// in Settings a choice acts at once; in New session (`newSession` is the draft) a choice only fills its plan, and nothing is cloned or written until the
/// first message is sent.
struct AddProjectSheet: View {
    let mode: ProjectSheetMode
    let model: ProjectsModel
    let recent: [RecentFolder]
    var openProject: (String) -> Void = { _ in }
    var newSession: NewSessionModel?
    /// Opens the Health tab of Settings, for the reason `gh` gives when it blocks the repositories.
    var openHealth: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlightedId: String?
    @State private var problem: String?
    @State private var dropping = false
    @State private var loadedRecent: [RecentFolder] = []
    @State private var github = ProjectSheetGithub(defaultParent: "")
    @State private var checkTask: Task<Void, Never>?
    @State private var capabilities: Set<ControlClient.Capability> = []
    @State private var creating = false
    @State private var form = NewProjectForm(defaultParent: "")
    @State private var making = false
    @State private var loadedOnce = false
    @FocusState private var fieldFocused: Bool
    @FocusState private var nameFocused: Bool

    /// ponytail: five pages of thirty are read, the newest pushes; a person with more types the address or searches for it, which the check below handles.
    private static let listedPages = 5

    private var effectiveRecent: [RecentFolder] { recent.isEmpty ? loadedRecent : recent }

    private var state: ProjectSheetState {
        var known = github
        known.defaultParent = newSession?.projectsPath ?? model.projectsPath
        known.watched = newSession?.watched
        return projectSheetState(mode: mode, query: query, recent: effectiveRecent, projects: model.rows, github: known)
    }

    var body: some View {
        if creating { newProjectForm } else { chooser }
    }

    private var chooser: some View {
        let current = state
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    TextField("", text: $query, prompt: Text(mode.fieldPlaceholder))
                        .settingsField(icon: .search, focused: $fieldFocused)
                        .autocorrectionDisabled()
                        .writingToolsBehavior(.disabled)
                        .accessibilityLabel(mode.title)
                        .onSubmit {
                            if let item = highlightedOrFirst(in: current) {
                                activate(item)
                            }
                        }
                        .onKeyPress(.downArrow) { move(1, in: current, proxy: proxy) }
                        .onKeyPress(.upArrow) { move(-1, in: current, proxy: proxy) }
                        .onKeyPress(.escape) {
                            dismiss()
                            return .handled
                        }
                    if let problem {
                        ProblemLine(text: problem)
                    } else if let notice = current.notice {
                        ProblemLine(text: notice, announces: false)
                    }
                    if let gh = newSession?.ghState, gh.blocks {
                        HealthFixButton(tool: .gh, state: gh)
                        Button("Open Health in Settings") {
                            dismiss()
                            openHealth()
                        }
                        .buttonStyle(.link).font(.scaled(12))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

                SettingsDivider()

                resultsList(current)

                SettingsDivider()

                footer
            }
            .frame(width: 580, height: 460)
            .overlay { if dropping { dropVeil } }
            .onDrop(of: [.fileURL], isTargeted: $dropping) { handleDrop($0) }
            .onAppear {
                fieldFocused = true
                highlightedId = current.firstResult?.id
            }
            .onChange(of: query) {
                problem = nil
                highlightedId = state.firstResult?.id
                checkPastedRepository()
            }
            .onChange(of: current.items.map(\.id)) { _, ids in
                if let currentId = highlightedId, ids.contains(currentId) { return }
                highlightedId = ids.first
            }
            .onKeyPress(.downArrow) { move(1, in: current, proxy: proxy) }
            .onKeyPress(.upArrow) { move(-1, in: current, proxy: proxy) }
            .onKeyPress(.return) {
                guard let item = highlightedOrFirst(in: current) else { return .ignored }
                activate(item)
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .task {
                // Back from New project… shows the chooser again: what was read stays
                guard loadedOnce == false else { return }
                loadedOnce = true
                let host = SocketChatHost()
                newSession?.openPicker()
                if recent.isEmpty {
                    let active = (try? await host.list(archived: false)) ?? []
                    let archived = (try? await host.list(archived: true)) ?? []
                    let combined = active + archived
                    if combined.isEmpty == false {
                        loadedRecent = recentFolders(combined)
                    }
                }
                await loadRepositories(host)
            }
        }
    }

    // MARK: Header & Footer

    private var header: some View {
        HStack(spacing: 12) {
            Glyph(.folderPlus, size: 16).foregroundStyle(Color.themeAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.scaled(16, weight: .semibold))
                Text(mode.subtitle).font(.scaled(12)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: openFolderPanel) {
                Label("Open a folder…", icon: .folderPlus).labelStyle(.titleAndIcon)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
            .help("Open a folder on this Mac (\u{2318}O)")
            if mode.actsAtOnce || newSession?.hostCreates == true {
                Button("New project…") {
                    form = NewProjectForm(defaultParent: newSession?.projectsPath ?? model.projectsPath)
                    problem = nil
                    creating = true
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .help(mode.actsAtOnce ? "Make an empty git folder and add it as a project" : "Work in a new empty git folder, made when you send the first message")
            }
            Spacer(minLength: 8)
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: New project

    /// The form of New project…: a name (a plain folder name) and where it is made, `<projects folder>/local/<name>` with Choose… for this one only. Create asks the
    /// host to make the folder and register it, then closes the sheet and opens the project's page; a name whose folder is there is refused with the reason and nothing is written.
    private var newProjectForm: some View {
        let reason = form.problem(taken: model.isTaken)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Glyph(.folderPlus, size: 16).foregroundStyle(Color.themeAccent)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New project").font(.scaled(16, weight: .semibold))
                        Text(mode.actsAtOnce ? "An empty git folder, added as a project." : "An empty git folder, made when you send the first message.").font(.scaled(12)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").sectionLabel()
                    TextField("", text: $form.name, prompt: Text("my-project"))
                        .settingsField(icon: .folder, focused: $nameFocused)
                        .autocorrectionDisabled()
                        .writingToolsBehavior(.disabled)
                        .accessibilityLabel("Name of the new project")
                        .onSubmit(createProject)
                        .onChange(of: form.name) { problem = nil }
                    Text("Letters, numbers, dots and dashes").font(.scaled(11)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.actsAtOnce ? "Create in" : "Will be created in").sectionLabel()
                    HStack(spacing: 8) {
                        Text(form.destinationLine().dropFirst("Creates ".count))
                            .font(.scaled(11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(form.folder)
                        if mode.actsAtOnce {
                            Button("Choose…", action: chooseNewProjectParent)
                                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                                .accessibilityLabel("Choose where the new project is made")
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let line = problem ?? reason { ProblemLine(text: line) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            SettingsDivider()
            HStack(spacing: 12) {
                Button("Back") {
                    problem = nil
                    creating = false
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(mode.actsAtOnce ? "Create" : "Use this project", action: createProject)
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(form.canCreate(taken: model.isTaken) == false || making)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 580, height: 460)
        .onAppear { nameFocused = true }
    }

    private func createProject() {
        guard form.canCreate(taken: model.isTaken), making == false else { return }
        if let newSession {
            newSession.choose(newProject: form.name)
            dismiss()
            return
        }
        making = true
        problem = nil
        let name = form.name
        let parent = form.chosenParent
        Task {
            defer { making = false }
            do {
                let folder = try await model.createProject(name, into: parent)
                dismiss()
                openProject(folder)
            } catch ControlError.remote(let words) {
                problem = words
            } catch {
                problem = hostNotRunning
            }
        }
    }

    /// The folder panel for the folder this one project is made in (the default is left as it is); refused for a folder inside Carrier's own.
    private func chooseNewProjectParent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: form.parent)
        panel.prompt = "Choose"
        panel.message = "Choose the folder the new project is made in"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let refusal = projectsFolderRefusal(url.path, carrierFolder: currentCarrierFolder()) {
            problem = refusal
            return
        }
        problem = nil
        form.chosenParent = url.path
    }

    // MARK: Results

    @ViewBuilder private func resultsList(_ current: ProjectSheetState) -> some View {
        if current.items.isEmpty {
            let emptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            EmptyStateView(
                icon: emptyQuery ? .folder : .search,
                title: emptyQuery ? "No recent folders" : "Nothing matches",
                line: emptyQuery
                    ? "Paste a GitHub address, type a path starting with ~ or /, drop folders here, or choose Open a folder… below."
                    : "Nothing in your recent folders or repositories matches. Paste a GitHub address, or type a path starting with ~ or / to add any folder."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(current.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = section.title {
                                Text(title)
                                    .sectionLabel()
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 2)
                            }
                            ForEach(section.items) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    resultRow(item, highlighted: highlightedId == item.id)
                                    if item.destination != nil, highlightedId == item.id || section.id == "path" { destinationLine(item) }
                                }
                                .id(item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resultRow(_ item: ProjectSheetResult, highlighted: Bool) -> some View {
        HoverRow(
            action: { activate(item) },
            fill: highlighted ? Color.themeAccent.opacity(0.16) : nil
        ) { hovering in
            HStack(spacing: 12) {
                ProjectIcon(tile: item.tile)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.scaled(13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let chip = item.chip { StatusChip(text: chip, tint: .secondary) }
                    }
                    Text(item.detail)
                        .font(.scaled(11, design: item.kind.isRepository ? .default : .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(item.kind.isRepository ? .tail : .middle)
                }
                Spacer(minLength: 8)
                if item.pushed.isEmpty == false {
                    Text(item.pushed).font(.scaled(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
                actionBadge(item.actionTitle, active: (hovering || highlighted) && item.isEnabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .disabled(item.isEnabled == false)
        .accessibilityLabel(item.problem.map { "\(item.title), \($0)" } ?? "\(item.title), \(item.detail)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    /// Where a clone goes, with Choose… to change it for this clone only; a repository the login cannot see says so in orange instead.
    @ViewBuilder private func destinationLine(_ item: ProjectSheetResult) -> some View {
        if let problem = item.problem {
            ProblemLine(text: problem).padding(.horizontal, 10).padding(.bottom, 4)
        } else if let destination = item.destination, case .cloneRepo(let repo, _) = item.kind {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(destination.line)
                        .font(.scaled(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(destination.parent + "/" + repo)
                    if destination.canChoose {
                        Button("Choose…") { chooseParent(for: repo, current: destination.parent) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .accessibilityLabel("Choose where \(repo) is cloned")
                    }
                    Spacer(minLength: 0)
                }
                if let watch = item.watch, let newSession { watchChoice(watch, newSession) }
            }
            .padding(.horizontal, 10).padding(.bottom, 4)
        }
    }

    /// "Let Carrier watch this repo": on by default, a choice of the plan acted on once the first message was prepared; off, with the reason, when it cannot be on.
    private func watchChoice(_ watch: ProjectSheetWatch, _ newSession: NewSessionModel) -> some View {
        let on = watch.problem == nil && newSession.watch
        return HStack(spacing: 8) {
            Toggle("Let Carrier watch this repo", isOn: Binding(get: { on }, set: { newSession.watch = $0 }))
                .toggleStyle(.switch).controlSize(.small).font(.scaled(11))
                .disabled(watch.problem != nil)
            if let reason = watch.problem { Text(reason).font(.scaled(11)).foregroundStyle(.orange).lineLimit(2) }
            Spacer(minLength: 0)
        }
    }

    private func actionBadge(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.scaled(11, weight: .semibold))
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(active ? Color.accentGlass : Color.primary.opacity(0.08)))
    }

    // MARK: Drop Veil

    private var dropVeil: some View {
        VStack(spacing: 4) {
            Glyph(.folderPlus, size: 22).foregroundStyle(Color.themeAccent)
            Text(mode.actsAtOnce ? "Drop folders to add" : "Drop a folder to work in").font(.scaled(14, weight: .semibold))
            Text(mode.actsAtOnce ? "Folders are added to your projects; files are refused" : "The folder fills the plan; nothing is written").font(.scaled(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.themeAccent.opacity(0.14)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.themeAccent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .padding(8)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: Actions & Keyboard

    private func highlightedOrFirst(in current: ProjectSheetState) -> ProjectSheetResult? {
        if let highlightedId, let found = current.items.first(where: { $0.id == highlightedId }) {
            return found
        }
        return current.firstResult
    }

    private func move(_ step: Int, in current: ProjectSheetState, proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = current.items.map(\.id)
        guard ids.isEmpty == false else { return .ignored }
        let index = highlightedId.flatMap(ids.firstIndex(of:))
        let next = index.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        highlightedId = ids[next]
        proxy.scrollTo(ids[next])
        return .handled
    }

    private func activate(_ item: ProjectSheetResult) {
        guard item.isEnabled else { return }
        if let newSession {
            dismiss()
            Task { await newSession.choose(item) }
            return
        }
        switch item.kind {
        case .addPath(let path):
            addFolder(path)
        case .suggestedFolder(let folder):
            addFolder(folder.path)
        case .existingProject(let project):
            dismiss()
            openProject(project.path)
        case .cloneRepo(let repo, let parent):
            clone(repo, into: parent)
        }
    }

    // MARK: GitHub

    /// The person's repositories, page by page, and what the host can do; the host's own words when it cannot list them.
    private func loadRepositories(_ host: SocketChatHost) async {
        let found = (try? await host.capabilities()) ?? []
        capabilities = found
        // a host that did not answer is not one that is older: the clone itself says so
        if found.isEmpty == false { github.canClone = found.contains(newSession == nil ? .projects : .repoBranches) }
        guard found.contains(.githubRepos) else { return }
        for page in 1...Self.listedPages {
            do {
                let loaded = try await host.githubRepos(page: page)
                github.repos += loaded.repos.filter { isRepoName($0.name) }
                if loaded.hasMore == false { return }
            } catch ControlError.remote(let words) {
                github.listingProblem = words
                return
            } catch {
                return
            }
        }
    }

    /// A pasted address that is not in the person's repositories is looked up on GitHub once typing pauses, so a repository the login cannot see says so
    /// before Clone is pressed.
    private func checkPastedRepository() {
        checkTask?.cancel()
        guard let repo = repoReference(query), capabilities.contains(.repoBranches),
            github.repos.contains(where: { $0.name.lowercased() == repo.lowercased() }) == false
        else { return }
        let key = repo.lowercased()
        switch github.visibility[key] {
        case .visible, .notVisible, .problem: return
        case .checking, nil: break
        }
        github.visibility[key] = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard Task.isCancelled == false else { return }
            do {
                _ = try await SocketChatHost().repoBranches(repo)
                github.visibility[key] = .visible
            } catch ControlError.remote(let words) {
                github.visibility[key] = isRepoNotVisible(words) ? .notVisible : .problem(words)
            } catch {
                github.visibility[key] = nil
            }
        }
    }

    private func clone(_ repo: String, into parent: String?) {
        problem = nil
        Task {
            do {
                try await model.startClone(repo, into: parent)
                dismiss()
            } catch ControlError.remote(let words) {
                problem = words
            } catch {
                problem = hostNotRunning
            }
        }
    }

    /// The system's folder panel for the folder this one clone goes in (the default is left as it is); refused for a folder inside Carrier's own.
    private func chooseParent(for repo: String, current: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: current)
        panel.prompt = "Choose"
        panel.message = "Choose the folder \(repo) is cloned into"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let refusal = projectsFolderRefusal(url.path, carrierFolder: currentCarrierFolder()) {
            problem = refusal
            return
        }
        problem = nil
        github.chosenParents[repo.lowercased()] = url.path
    }

    private func addFolder(_ path: String) {
        problem = nil
        if let newSession {
            dismiss()
            Task { await newSession.choose(folder: path) }
            return
        }
        switch model.add(folder: path) {
        case .added(let addedPath), .existing(let addedPath):
            dismiss()
            openProject(addedPath)
        case nil:
            problem = model.failure ?? model.problems.first?.text ?? "That folder cannot be added"
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = mode.openPanelPrompt
        panel.message = mode.openPanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolder(url.path)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard fileProviders.isEmpty == false else { return false }
        let total = fileProviders.count
        var loaded: [Int: URL] = [:]
        var remaining = total
        let lock = NSLock()
        for (index, provider) in fileProviders.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                let collected: [URL]? = lock.withLock {
                    if let url { loaded[index] = url }
                    remaining -= 1
                    guard remaining == 0 else { return nil }
                    return (0..<total).compactMap { loaded[$0] }
                }
                guard let urls = collected else { return }
                Task { @MainActor in
                    applyDrop(urls.map(\.path))
                }
            }
        }
        return true
    }

    private func applyDrop(_ paths: [String]) {
        problem = nil
        if newSession != nil, let first = paths.first {
            addFolder(first)
            return
        }
        let outcome = applyDroppedProjectPaths(paths) { path in
            let result = model.add(folder: path)
            return (result, model.failure ?? model.problems.first?.text)
        }
        switch outcome {
        case .open(let path):
            dismiss()
            openProject(path)
        case .addedMultiple:
            dismiss()
        case .refused(let message):
            problem = message
        }
    }
}
