import AppKit
import CarrierCore
import SwiftUI

/// The Repos tab: which repos Carrier watches (the `repos` of `config.json`, CarrierCore/RepoList.swift), each with how its last
/// check went. Add from the gh login's list, stop watching with a question first. Saved like the Behavior tab: the engine reads
/// the file when it starts, so with Carrier running "Save and restart" also restarts it.
struct ReposTabView: View {
    let state: ConnectionState?
    @ObservedObject private var start = StartController.shared
    @ObservedObject private var setup = SetupController.shared
    @AppStorage(confirmStopKey) private var asksBeforeStop = true
    @State private var saved: [String] = []
    @State private var draft: [String] = []
    @State private var unreadable = false
    @State private var failure: String?
    @State private var note: String?
    /// the repo whose ✕ was pressed
    @State private var removing: String?
    @State private var confirmingRestart = false
    @State private var restarting = false
    @State private var adding = false

    private var path: String { configFilePath() }

    private var engine: String { engineFolder() }

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = state { return snapshot }
        return nil
    }

    var body: some View {
        let dirty = draft != saved
        let problem = reposProblem(draft)
        let footer = behaviorFooter(state: state, dirty: dirty, valid: problem == nil, startMissing: startMissing(setup.settings), noun: "list")
        VStack(alignment: .leading, spacing: 12) {
            if unreadable {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let note { SavedNote(text: note) }
            SettingsTabCard {
                ForEach(Array(repoRows(draft: draft, saved: saved, snapshot: snapshot).enumerated()), id: \.element.id) { index, row in
                    RepoRowView(row: row, first: index == 0, onlyOne: draft.count == 1, engine: engine) { removing = row.name }
                }
            }
            if let problem, unreadable == false { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
            if confirmingRestart, let warning = restartWarning(epics: snapshot?.runningEpics ?? 0, asks: asksBeforeStop) {
                ConfirmationCard(text: warning, confirm: "Restart and interrupt", cancel: { confirmingRestart = false }) { confirmingRestart = false; saveAndRestart() }
            }
            HStack(spacing: 8) {
                Button("＋ Add repo…") { adding = true }.disabled(unreadable)
                Spacer()
                if restarting || start.starting { ProgressView().controlSize(.small) }
                Button("Revert") { draft = saved; removing = nil }.disabled(dirty == false || restarting)
                if footer.offersRestart {
                    Button("Save only") { if write() { note = "Saved. Carrier keeps the old list until it restarts." } }
                        .disabled(footer.canSave == false || restarting)
                    Button("Save and restart") { restartPressed() }
                        .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(footer.canRestart == false || restarting).help(footer.message)
                } else {
                    Button("Save") { if write() { note = "Saved. Carrier uses it the next time it starts." } }
                        .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(footer.canSave == false)
                }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .onAppear(perform: load)
        .onChange(of: start.configExists) { load() }
        .onChange(of: draft) { note = nil }
        .alert(
            "Stop watching \(removing ?? "")?",
            isPresented: Binding(get: { removing.map { draft.contains($0) } ?? false }, set: { if $0 == false { removing = nil } })
        ) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Stop watching", role: .destructive) {
                if let name = removing { draft.removeAll { $0 == name } }
                removing = nil
            }
        } message: {
            Text(removing.map { removalText(repoEpics($0, snapshot: snapshot)) } ?? "")
        }
        .sheet(isPresented: $adding) {
            AddReposSheet(watched: draft) { names in
                draft += names
                adding = false
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let names = configRepoNames(json: data) else {
            unreadable = true
            return
        }
        unreadable = false
        saved = names
        draft = names
    }

    /// Writes the file, read again just now so a save from the Behavior tab in between is not lost; false (with the reason shown)
    /// when it could not.
    private func write() -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), let updated = applyingRepos(draft, to: data) else {
            failure = "The config file could not be read or the list is not valid."
            return false
        }
        do {
            try updated.write(to: url, options: .atomic)
            failure = nil
            saved = draft
            return true
        } catch {
            FileHandle.standardError.write(Data("carrier: saving \(url.path) failed: \(error)\n".utf8))
            failure = "Could not save the config file: \(error.localizedDescription)"
            return false
        }
    }

    /// Asks first only when it would interrupt epics (and the General switch is on).
    private func restartPressed() {
        if restartWarning(epics: snapshot?.runningEpics ?? 0, asks: asksBeforeStop) == nil { saveAndRestart() } else { confirmingRestart = true }
    }

    private func saveAndRestart() {
        guard write() else { return }
        restarting = true
        StartController.shared.restart { ok in
            restarting = false
            if ok { note = "Carrier restarted with the new list" }
            else { failure = "Saved, but Carrier did not come up again. See the alert or the start log in General." }
        }
    }
}

private struct RepoRowView: View {
    let row: RepoRow
    let first: Bool
    let onlyOne: Bool
    let engine: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let clone = row.clonePath(engine: engine)
        let cloned = FileManager.default.fileExists(atPath: clone)
        HStack(alignment: .top, spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text(row.line).font(.caption).foregroundStyle(row.health == .error ? Color.red : Color.secondary).lineLimit(2)
                Text(tildePath(clone)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                chips
            }
            Spacer(minLength: 8)
            Menu { actions(clone: clone, cloned: cloned) } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0)))
                    .contentShape(Circle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .frame(maxHeight: .infinity)
            .onHover { hovering = $0 }
            .accessibilityLabel("Actions for \(row.name)")
        }
        .contextMenu { actions(clone: clone, cloned: cloned) }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().opacity(first ? 0 : 1) }
    }

    /// The same items in the row's menu and in its right-click menu.
    @ViewBuilder private func actions(clone: String, cloned: Bool) -> some View {
        Button { if let url = row.gitHubURL { NSWorkspace.shared.open(url) } } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: clone)]) } label: {
            Label(cloned ? "Reveal clone in Finder" : "Reveal clone in Finder (not cloned yet)", systemImage: "folder")
        }
        .disabled(cloned == false)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.name, forType: .string)
        } label: { Label("Copy owner/name", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive, action: remove) { Label("Stop watching…", systemImage: "trash") }.disabled(onlyOne)
    }

    /// The owner dim, the name in bold.
    private var title: AttributedString {
        var owner = AttributedString(row.owner + "/")
        owner.foregroundColor = Color.secondary
        var repo = AttributedString(row.repo)
        repo.font = Font.body.weight(.semibold)
        return owner + repo
    }

    /// The GitHub mark with the repo's health as a dot on its corner.
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.14)).frame(width: 34, height: 34)
                .overlay { GitHubMark.image.renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18) }
            Circle().fill(color).frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                .offset(x: 3, y: 3)
        }
        .accessibilityElement().accessibilityLabel(health)
    }

    @ViewBuilder private var chips: some View {
        let epics = row.epics
        if row.isNew || epics?.isNone == false {
            HStack(spacing: 6) {
                if row.isNew { chip("new", .green) }
                if let epics {
                    if epics.running > 0 { chip("\(epics.running) running", .green) }
                    if epics.queued > 0 { chip("\(epics.queued) queued", .blue) }
                    if epics.needsYou > 0 { chip("\(epics.needsYou) needs you", .orange) }
                }
            }
            .padding(.top, 4)
        }
    }

    private func chip(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.17)))
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

/// "Add repos from GitHub": the engine's list of what the gh login can push to, with search and checkboxes. It asks when it
/// opens, off the main thread (gh can take seconds).
private struct AddReposSheet: View {
    let watched: [String]
    let add: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var list: AvailableReposList?
    @State private var loadingMore = false
    @State private var query = ""
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add repos from GitHub").font(.headline)
                Text("The repos your gh login can push to. Archived ones are left out.").font(.caption).foregroundStyle(.secondary)
            }
            if let list, list.blocked == false { TextField("Search", text: $query).textFieldStyle(.roundedBorder) }
            content
            if let list, list.blocked == false, list.hasMore { loadMore(list) }
            HStack {
                Text(selected.isEmpty ? "" : "\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button(selected.count > 1 ? "Add \(selected.count) repos" : "Add repo") { add(chosen) }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18).frame(width: 520, height: 500)
        .onAppear {
            DispatchQueue.global().async {
                let loaded = loadAvailableRepos(socketPath: controlSocketPath())
                DispatchQueue.main.async { var first = AvailableReposList(); first.apply(loaded); list = first }
            }
        }
    }

    /// Asks for the next page; what is loaded stays, and a failure is said under the list.
    private func loadNextPage() {
        guard let current = list, loadingMore == false else { return }
        loadingMore = true
        DispatchQueue.global().async {
            let loaded = loadAvailableRepos(socketPath: controlSocketPath(), page: current.nextPage)
            DispatchQueue.main.async {
                var next = list ?? current
                next.apply(loaded)
                list = next
                loadingMore = false
            }
        }
    }

    private func loadMore(_ list: AvailableReposList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Partial list: \(list.repos.count) repos so far, and there are more. Search only looks at these.").font(.caption).foregroundStyle(.secondary)
            if let problem = list.problem, let text = availableReposMessage(problem) {
                Text("\(text.title). \(text.detail)").font(.caption).foregroundStyle(.red)
            }
            Button(loadingMore ? "Loading…" : "Load more") { loadNextPage() }.buttonStyle(.glass).disabled(loadingMore)
        }
    }

    /// The ticked repos in the order of the engine's list.
    private var chosen: [String] {
        (list?.repos ?? []).map(\.name).filter(selected.contains)
    }

    @ViewBuilder private var content: some View {
        switch list {
        case nil:
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)).frame(height: 34) }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity).accessibilityLabel("Loading your repos")
        case let list? where list.blocked == false:
            let groups = repoGroups(list.repos, watched: watched, selected: selected, query: query)
            if groups.isEmpty {
                message("No repo matches “\(query)”", "Only repos your gh login can push to are listed.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            Text(group.owner.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary).padding(.top, 10).padding(.bottom, 2)
                            ForEach(group.choices) { choice in choiceRow(choice) }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
            }
        case let list?:
            let text = list.problem.flatMap(availableReposMessage)
            message(text?.title ?? "", text?.detail ?? "")
        }
    }

    private func choiceRow(_ choice: RepoChoice) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { choice.watched || selected.contains(choice.name) },
                set: { if $0 { selected.insert(choice.name) } else { selected.remove(choice.name) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    if choice.detail.isEmpty == false { Text(choice.detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.checkbox).disabled(choice.disabled)
            Spacer(minLength: 8)
            if choice.isPrivate {
                Text("private").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.vertical, 6).opacity(choice.disabled ? 0.5 : 1)
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
    }
}
