import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// The shared sheet for choosing a folder or project (docs/specs/projects.md, "Add project"): one search/path field, suggested recent
/// folders, drag and drop, keyboard navigation, and Open a folder…. Driven by `ProjectSheetMode`.
struct AddProjectSheet: View {
    let mode: ProjectSheetMode
    let model: ProjectsModel
    let recent: [RecentFolder]
    let openProject: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlightedId: String?
    @State private var problem: String?
    @State private var dropping = false
    @State private var loadedRecent: [RecentFolder] = []
    @FocusState private var fieldFocused: Bool

    private var effectiveRecent: [RecentFolder] { recent.isEmpty ? loadedRecent : recent }

    private var state: ProjectSheetState {
        projectSheetState(mode: mode, query: query, recent: effectiveRecent, projects: model.rows)
    }

    var body: some View {
        let current = state
        ScrollViewReader { proxy in
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
                if recent.isEmpty {
                    let host = SocketChatHost()
                    let active = (try? await host.list(archived: false)) ?? []
                    let archived = (try? await host.list(archived: true)) ?? []
                    let combined = active + archived
                    if combined.isEmpty == false {
                        loadedRecent = recentFolders(combined)
                    }
                }
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
            Spacer(minLength: 8)
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Results

    @ViewBuilder private func resultsList(_ current: ProjectSheetState) -> some View {
        if current.items.isEmpty {
            let emptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            EmptyStateView(
                icon: emptyQuery ? .folder : .search,
                title: emptyQuery ? "No recent folders" : "No matching folders",
                line: emptyQuery
                    ? "Type a path starting with ~ or /, drop folders here, or choose Open a folder… below."
                    : "Nothing in your recent folders matches. Type a path starting with ~ or / to add any folder."
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
                                resultRow(item, highlighted: highlightedId == item.id)
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
                    Text(item.title)
                        .font(.scaled(13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.detail)
                        .font(.scaled(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                actionBadge(item.actionTitle, active: hovering || highlighted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .accessibilityLabel("\(item.title), \(item.detail)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
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
            Text("Drop folders to add").font(.scaled(14, weight: .semibold))
            Text("Folders are added to your projects; files are refused").font(.scaled(12)).foregroundStyle(.secondary)
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
        switch mode {
        case .settings:
            switch item.kind {
            case .addPath(let path):
                addFolder(path)
            case .suggestedFolder(let folder):
                addFolder(folder.path)
            case .existingProject(let project):
                dismiss()
                openProject(project.path)
            }
        }
    }

    private func addFolder(_ path: String) {
        problem = nil
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
