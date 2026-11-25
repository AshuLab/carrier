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
    @Environment(\.pieceTheme) var theme
    let mode: ProjectSheetMode
    let model: ProjectsModel
    let recent: [RecentFolder]
    var openProject: (String) -> Void = { _ in }
    var newSession: NewSessionModel?
    /// Opens the Health tab of Settings, for the reason `gh` gives when it blocks the repositories.
    var openHealth: () -> Void = {}

    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var highlightedId: String?
    @State var problem: String?
    @State private var dropping = false
    @State private var loadedRecent: [RecentFolder] = []
    @State var github = ProjectSheetGithub(defaultParent: "")
    @State var checkTask: Task<Void, Never>?
    @State var capabilities: Set<ControlClient.Capability> = []
    @State var creating = false
    @State var form = NewProjectForm(defaultParent: "")
    @State var making = false
    @State private var loadedOnce = false
    @FocusState private var fieldFocused: Bool
    @FocusState var nameFocused: Bool

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
            VStack(spacing: Tokens.Space.none) {
                VStack(alignment: .leading, spacing: Tokens.Space.s14) {
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
                        .buttonStyle(.link).scaledFont(12)
                    }
                }
                .padding(.horizontal, Tokens.Space.s24)
                .padding(.top, Tokens.Space.s22)
                .padding(.bottom, Tokens.Space.s16)

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
        HStack(spacing: Tokens.Space.s12) {
            Glyph(.folderPlus, size: 16).foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(.tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(mode.title).scaledFont(16, weight: .semibold)
                Text(mode.subtitle).scaledFont(12).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Tokens.Space.s12) {
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
        .padding(.horizontal, Tokens.Space.s20)
        .padding(.vertical, Tokens.Space.s12)
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

    func activate(_ item: ProjectSheetResult) {
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

    private func addFolder(_ path: String) {
        problem = nil
        if let newSession {
            dismiss()
            Task { await newSession.choose(folder: path) }
            return
        }
        Task {
            switch await model.add(folder: path) {
            case .added(let addedPath), .existing(let addedPath):
                dismiss()
                openProject(addedPath)
            case nil:
                problem = model.failure ?? model.problems.first?.text ?? "That folder cannot be added"
            }
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
        Task {
            let outcome = await applyDroppedProjectPaths(paths) { path in
                let result = await model.add(folder: path)
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
}
