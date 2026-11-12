import AppKit
import CarrierCore
import SwiftUI

/// The Repos page: which repos Carrier watches (the `repos` of `config.json`, CarrierCore/RepoList.swift), each with how its last
/// check went. Add from the gh login's list, stop watching with a question first. Saved like the Behavior tab: every change is written
/// as it is made, and nothing restarts Carrier, which reads the file when it starts.
struct ReposTabView: View {
    private let timeChanges = TimeFormatChanges()
    let state: ConnectionState?
    /// Open Agents: the page of the global roles, which every repo inherits.
    let openAgents: () -> Void
    @ObservedObject private var start = StartController.shared
    @State private var saved: [String] = []
    @State private var draft: [String] = []
    @State private var unreadable = false
    /// the file as `load` read it, for the roles on a repo's page
    @State private var configData: Data?
    @State private var failure: String?
    @State private var note: String?
    /// the repo whose ✕ was pressed
    @State private var removing: String?
    @State private var adding = false
    /// the repo whose page is on the right
    @State private var selection: String?
    /// the role whose form is open on that page
    @State private var roleSelection = RepoRoleSelection()
    private let doctor = AppHealth.doctor
    @ObservedObject private var setup = SetupController.shared

    private var path: String { configFilePath() }

    private var engine: String { engineFolder() }

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = state { return snapshot }
        return nil
    }

    var body: some View {
        let problem = reposProblem(draft)
        let rows = repoRows(draft: draft, saved: saved, snapshot: snapshot)
        let chosen = rows.first { $0.name == selection } ?? rows.first
        VStack(alignment: .leading, spacing: 12) {
            if unreadable {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if rows.isEmpty == false {
                        SettingsTabCard {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                RepoRowView(row: row, first: index == 0, engine: engine, selected: row.name == chosen?.name) {
                                    removing = row.name
                                }
                                .onTapGesture {
                                    selection = row.name
                                    roleSelection = RepoRoleSelection()
                                }
                            }
                        }
                    }
                    Button("＋ Add repo…") { adding = true }.disabled(unreadable)
                }
                .frame(width: 300)
                detail(chosen)
            }
            if let problem, unreadable == false { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
            Group {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                } else if let note {
                    Label(note, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                } else {
                    Text("Saved as you change it. Carrier reads this list when it starts.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .onAppear(perform: load)
        // the doctor runs when the page opens and on Check again, never in the background
        .task { runDoctor() }
        .onChange(of: start.configExists) { load() }
        // a file that is there but unreadable may be fixed in another app: look again when Carrier is back in front (only then, so no edit is lost)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if unreadable { load() } }
        .onChange(of: draft) {
            note = nil
            autosave()
        }
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
            .themed()
        }
    }

    /// Not awaited: the card says it is running. The store ignores a run while one is running and runs only with a `config.json`.
    private func runDoctor() {
        let settings = setup.settings, configExists = start.configExists
        // a fixture has no `carrier` to find: any path will do, the run answers with the golden output
        let carrier = setup.carrier ?? (CommandLine.arguments.contains("--fixture") ? "/fixture/carrier" : nil)
        Task { await doctor.check(settings: settings, carrier: carrier, environment: ProcessInfo.processInfo.environment, configExists: configExists) }
    }

    /// The chosen repo's page.
    @ViewBuilder private func detail(_ row: RepoRow?) -> some View {
        if let row {
            VStack(alignment: .leading, spacing: 12) {
                Text(row.name).font(.headline)
                RepoStatusCard(status: repoStatus(row, engine: engine, cloneExists: FileManager.default.fileExists(atPath: row.clonePath(engine: engine))))
                let roles = configData.flatMap { repoRoles(json: $0, repo: row.name) }
                RepoChecksCard(
                    checks: repoChecks(repo: row.name, roles: roles?.rows ?? [], doctor: doctor.state), checking: doctor.state == .running, again: runDoctor,
                    useAnotherIdentity: { roleSelection.useAnotherIdentity(on: $0) }, openAgents: openAgents
                )
                if let roles {
                    RepoRolesCard(
                        rows: roles.rows, editing: $roleSelection.editing, profiles: roles.profiles, accounts: declaredAccounts(providersJSON: providersData), refusal: refusal,
                        save: { role, fields in saveRole(fields, role: role, repo: row.name) }, openAgents: openAgents
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text("Add a repo to see its page.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var providersData: Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("providers.json"))
    }

    private var refusal: String? {
        if case .refused(let reason) = doctor.state { return "Carrier refuses the config: \(reason)" }
        return nil
    }

    /// Writes the role, then reads the file back and asks the doctor, whose reason is shown when the engine refuses what was written.
    private func saveRole(_ fields: RoleFields?, role: AgentRole, repo: String) -> RoleSave {
        let result = saveRepoRole(fields, role: role, repo: repo, path: path, accounts: declaredAccounts(providersJSON: providersData))
        if result == .saved {
            load()
            runDoctor()
        }
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let names = configRepoNames(json: data) else {
            unreadable = true
            configData = nil
            saved = []
            draft = []
            note = nil
            failure = nil
            return
        }
        unreadable = false
        configData = data
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

    /// Writes the list as soon as it changes, when the engine would accept it.
    private func autosave() {
        guard unreadable == false, draft != saved, reposProblem(draft) == nil else { return }
        if write() { note = "Saved" }
    }
}

/// Status: the epics and the last check (or that Carrier reads the repo when it starts), the clone with Reveal and the repo on GitHub with Open.
private struct RepoStatusCard: View {
    let status: RepoStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATUS").font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary).padding(.leading, 14).padding(.top, 8)
            SettingsTabCard {
                if let note = status.note {
                    SettingsTabRow(title: "Epics and last check", detail: note, first: true) { EmptyView() }
                } else {
                    SettingsTabRow(title: "Epics", detail: status.epics ?? "", first: true) { EmptyView() }
                    SettingsTabRow(title: "Last check", detail: status.lastCheck ?? "") { EmptyView() }
                }
                SettingsTabRow(title: "Clone", detail: status.clone, mono: true) {
                    if status.canRevealClone {
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.clonePath)]) }
                    }
                }
                SettingsTabRow(title: "On GitHub", detail: status.gitHubURL.map { "github.com\($0.path)" } ?? "") {
                    if let url = status.gitHubURL { Button("Open") { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
}

/// Ready for Carrier: the four checks of the doctor for this repo, each ok, failed with its reason or waiting.
private struct RepoChecksCard: View {
    let checks: RepoChecks
    let checking: Bool
    let again: () -> Void
    let useAnotherIdentity: (RepoCheckRow) -> Void
    let openAgents: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("READY FOR CARRIER").font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if checking { ProgressView().controlSize(.small) }
                Button("Check again", action: again).disabled(checking)
            }
            .padding(.horizontal, 14).padding(.top, 8)
            SettingsTabCard {
                ForEach(Array(checks.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 10) {
                        mark(row.status).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title).fontWeight(.medium)
                            if let detail = row.detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            if let fix = row.fix, row.status != .ok { Text("Fix: \(fix)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 8)
                        if row.anotherIdentity != nil {
                            Button("Use another identity") { useAnotherIdentity(row) }
                            Button("Open Agents", action: openAgents)
                        }
                    }
                    .padding(.vertical, 10).frame(minHeight: 46)
                    .overlay(alignment: .top) { Divider().opacity(index == 0 ? 0 : 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            if let note = checks.note { Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14) }
        }
    }

    private func mark(_ status: RepoCheckRow.Status) -> some View {
        let (symbol, color, label): (String, Color, String) = switch status {
        case .ok: ("checkmark", .green, "Ready")
        case .warn: ("exclamationmark", .yellow, "Warning")
        case .fail: ("xmark", .orange, "Failed")
        case .waiting: ("ellipsis", .gray, "Waiting")
        }
        return Image(systemName: symbol).font(.scaled(10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(color)).accessibilityLabel(label)
    }
}

/// Who works here: each role with what it inherits from the global roles, or the repo's own, and the form to change or reset it. Each field
/// of the form is its own override: left on "Same as everywhere" it is not written.
private struct RepoRolesCard: View {
    let rows: [RepoRoleRow]
    @Binding var editing: AgentRole?
    let profiles: [String]
    let accounts: [String]
    /// why the doctor refused the config after the last save
    let refusal: String?
    let save: (AgentRole, RoleFields?) -> RoleSave
    let openAgents: () -> Void
    @State private var draft = RoleFields()
    @State private var problem: String?

    var body: some View {
        SettingsGroup(title: "Who works here") {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SettingsTabRow(title: row.title, detail: row.isOwn ? "Default: \(row.inherited.text)" : row.value.text, first: index == 0) {
                    HStack(spacing: 8) {
                        Text(row.isOwn ? row.value.text : "Same as everywhere").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.trailing)
                        Button("Change") { editing = row.role }.disabled(editing == row.role)
                        if row.isOwn { Button("Reset") { finish(save(row.role, nil)) } }
                    }
                }
                if editing == row.role { form(row) }
            }
            SettingsTabRow(title: "Defaults", detail: "Every repo follows the roles of Agents unless it has its own") { Button("Open Agents", action: openAgents) }
            if let note = signatureNote(rows) { Text(note).font(.caption).foregroundStyle(.secondary).padding(.vertical, 8) }
            if let refusal { Text(refusal).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.vertical, 8) }
            if editing == nil, let problem { Text(problem).font(.caption).foregroundStyle(.orange).padding(.vertical, 8) }
        }
        // the form opens from Change here or from a failed sign check above; either way it starts from the role's own fields
        .onChange(of: editing) { _, role in
            guard let row = rows.first(where: { $0.role == role }) else { return }
            draft = row.own
            problem = nil
        }
    }

    private func finish(_ result: RoleSave) {
        switch result {
        case .saved:
            editing = nil
            problem = nil
        case .refused(let reason), .failed(let reason):
            problem = reason
        }
    }

    private func form(_ row: RepoRoleRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            choice("Identity", $draft.profile, options: profiles, inherited: row.inherited.profile)
            choice("Provider", $draft.provider, options: accounts, inherited: row.inherited.provider)
            LabeledContent("Model") {
                TextField(row.inherited.model ?? "Model", text: Binding(get: { draft.model ?? "" }, set: { draft.model = $0 })).textFieldStyle(.roundedBorder)
            }
            choice("Effort", $draft.effort, options: roleEfforts, inherited: row.inherited.effort)
            LabeledContent("Persona name") {
                TextField(row.inherited.persona?.name ?? "Name", text: persona(\.name)).textFieldStyle(.roundedBorder)
            }
            LabeledContent("Persona prompt") {
                TextField(row.inherited.persona?.prompt ?? "Prompt", text: persona(\.prompt), axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { editing = nil }
                Button("Save") { finish(save(row.role, draft)) }.buttonStyle(PrimaryCapsuleButtonStyle())
            }
        }
        .padding(.vertical, 10)
    }

    /// A name that is no longer declared stays in the list, marked, so it is seen and refused on saving and not dropped.
    private func choice(_ title: String, _ value: Binding<String?>, options: [String], inherited: String?) -> some View {
        LabeledContent(title) {
            Picker(title, selection: value) {
                Text("Same as everywhere" + (inherited.map { " (\($0))" } ?? "")).tag(String?.none)
                ForEach(options, id: \.self) { Text($0).tag(String?.some($0)) }
                if let own = value.wrappedValue, options.contains(own) == false { Text("\(own) (missing)").tag(String?.some(own)) }
            }
            .labelsHidden()
        }
    }

    private func persona(_ field: WritableKeyPath<RolePersona, String?>) -> Binding<String> {
        Binding(
            get: { draft.persona?[keyPath: field] ?? "" },
            set: {
                var next = draft.persona ?? RolePersona()
                next[keyPath: field] = $0
                draft.persona = next
            }
        )
    }
}

private struct RepoRowView: View {
    let row: RepoRow
    let first: Bool
    let engine: String
    let selected: Bool
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
                Text(tildePath(clone)).font(.scaled(11, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                chips
            }
            Spacer(minLength: 8)
            Menu { actions(clone: clone, cloned: cloned) } label: {
                Image(systemName: "ellipsis").font(.scaled(15, weight: .semibold))
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
        // the menu's `maxHeight: .infinity` centres it in the row; without this the row takes all the height the page offers
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu { actions(clone: clone, cloned: cloned) }
        .padding(.vertical, 12)
        .background(selected ? Color.themeAccent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        Button(role: .destructive, action: remove) { Label("Stop watching…", systemImage: "trash") }
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
