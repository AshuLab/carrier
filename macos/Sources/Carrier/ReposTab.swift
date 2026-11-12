import AppKit
import CarrierCore
import SwiftUI

/// The Repos page: which repos Carrier watches (the `repos` of `config.json`, CarrierCore/RepoList.swift), each with how its last
/// check went. Add from the gh login's list, stop watching with a question first. Saved like the Behavior tab: every change is written
/// as it is made, and nothing restarts Carrier.
struct ReposTabView: View {
    private let timeChanges = TimeFormatChanges()
    let state: ConnectionState?
    let canReload: Bool
    /// Open Agents: the page of the global roles, which every repo inherits.
    let openAgents: () -> Void
    @ObservedObject private var start = StartController.shared
    @State private var saved: [String] = []
    @State private var draft: [String] = []
    @State private var unreadable = false
    /// the file as `load` read it, for the roles on a repo's page
    @State private var configData: Data?
    @State private var failure: String?
    /// the last save was written and the engine did not apply it: a repo of the list is not in use, whatever the engine can do
    @State private var kept = false
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
        VStack(alignment: .leading, spacing: 14) {
            if unreadable {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    // the list and, as its last row, the way to add one; the card is there with no repo too
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows) { row in
                            RepoRowView(row: row, engine: engine, selected: row.name == chosen?.name) {
                                removing = row.name
                            }
                            .onTapGesture {
                                selection = row.name
                                roleSelection = RepoRoleSelection()
                            }
                        }
                        AddRepoRow { adding = true }.disabled(unreadable)
                    }
                    .padding(8).settingsCard()
                }
                .frame(width: 270)
                detail(chosen)
            }
            if let problem, unreadable == false { Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
            // the list is written as it changes and says nothing about it, unless it could not
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(.horizontal, 4)
            }
        }
        .buttonStyle(SecondaryCapsuleButtonStyle())
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .onAppear(perform: load)
        // the doctor runs when the page opens and on Check again, never in the background
        .task { runDoctor() }
        .onChange(of: start.configExists) { load() }
        // a file that is there but unreadable may be fixed in another app: look again when Carrier is back in front (only then, so no edit is lost)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if unreadable { load() } }
        .onChange(of: draft) {
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
            let status = repoStatus(row, engine: engine, cloneExists: FileManager.default.fileExists(atPath: row.clonePath(engine: engine)), notLoaded: settingsNote(state: state, canReload: canReload, kept: kept))
            // two distances, as the Providers page has: 4 inside a block and 14 between blocks
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 10) {
                        ProjectIcon(name: row.repo, colorKey: projectColorKey(row.name))
                        Text(row.name).font(.title3.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    if let url = status.gitHubURL {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square").labelStyle(.titleAndIcon) }
                            .buttonStyle(HoverTextButtonStyle(tint: nil))
                    }
                    if status.canRevealClone {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.clonePath)]) } label: { Label("Reveal clone", systemImage: "folder").labelStyle(.titleAndIcon) }
                            .buttonStyle(HoverTextButtonStyle(tint: nil))
                    }
                    Button(action: runDoctor) { Label(doctor.state == .running ? "Checking…" : "Check again", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                        .buttonStyle(HoverTextButtonStyle(tint: nil)).disabled(doctor.state == .running)
                }
                RepoStatusCard(row: row, status: status)
                let roles = configData.flatMap { repoRoles(json: $0, repo: row.name) }
                RepoChecksCard(
                    checks: repoChecks(repo: row.name, roles: roles?.rows ?? [], doctor: doctor.state), checking: doctor.state == .running,
                    useAnotherIdentity: { roleSelection.useAnotherIdentity(on: $0) }, openAgents: openAgents
                )
                if let roles {
                    RepoRolesCard(
                        rows: roles.rows, editing: $roleSelection.editing, profiles: roles.profiles, accounts: declaredAccounts(providersJSON: providersData), icons: accountIcons(providersJSON: providersData), refusal: refusal,
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
        let result = saveRepoRole(fields, role: role, repo: repo, path: path, accounts: declaredAccounts(providersJSON: providersData), reload: { reloadEngine() })
        keep(result)
        if result.isWritten {
            load()
            runDoctor()
        }
        return result
    }

    private func keep(_ result: RoleSave) {
        if case .notApplied = result { kept = true } else if result.isWritten { kept = false }
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let names = configRepoNames(json: data) else {
            unreadable = true
            configData = nil
            saved = []
            draft = []
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
        let result = saveConfig(path: path, unusable: "The config file could not be read or the list is not valid.", edit: { applyingRepos(draft, to: $0) }, reload: { reloadEngine() })
        failure = result.problem
        keep(result)
        if result.isWritten { saved = draft }
        return result == .saved
    }

    /// Writes the list as soon as it changes, when the engine would accept it.
    private func autosave() {
        guard unreadable == false, draft != saved, reposProblem(draft) == nil else { return }
        _ = write()
    }
}

/// Status: the epics and the last check (or when Carrier uses the repo), the clone and the repo on GitHub, as a label and its
/// value; Open on GitHub and Reveal clone are on the title's line.
private struct RepoStatusCard: View {
    let row: RepoRow
    let status: RepoStatus

    var body: some View {
        SettingsGroup(title: "Status") {
            if let note = status.note {
                fact("Epics", first: true) { Text(note) }
            } else {
                fact("Epics", first: true) { epics }
                fact("Last check", copy: status.lastCheck) { Text(status.lastCheck ?? "").foregroundStyle(row.health == .error ? Color.red : Color.primary) }
            }
            fact("Clone", copy: status.clonePath) { Text(tildePath(status.clonePath)).font(.scaled(11.5, design: .monospaced)) }
            fact("On GitHub", copy: status.gitHubURL?.absoluteString) {
                Text(status.gitHubURL.map { "github.com\($0.path)" } ?? "").font(.scaled(11.5, design: .monospaced))
            }
        }
    }

    /// What the repo has in flight, as the row used to say it, with a word for none.
    @ViewBuilder private var epics: some View {
        if let epics = row.epics, epics.isNone == false {
            HStack(spacing: 6) {
                if epics.running > 0 { RepoChip(text: "\(epics.running) running", tint: .green) }
                if epics.queued > 0 { RepoChip(text: "\(epics.queued) queued", tint: .blue) }
                if epics.needsYou > 0 { RepoChip(text: "\(epics.needsYou) needs you", tint: .orange) }
            }
        } else {
            Text("None").foregroundStyle(.secondary)
        }
    }

    private func fact<Value: View>(_ label: String, first: Bool = false, copy: String? = nil, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            if let copy, copy.isEmpty == false {
                value().lineLimit(2).truncationMode(.middle).textSelection(.enabled).copyOnHover(copy)
            } else {
                value().lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        // taller than the chip of Epics makes a row, so a row with the chip and one without are the same height
        .padding(.vertical, 9).frame(minHeight: 40)
        .overlay(alignment: .top) { if first == false { SettingsDivider() } }
        .accessibilityElement(children: .combine)
    }
}

/// Ready for Carrier: the four checks of the doctor for this repo, each ok, failed with its reason or waiting.
private struct RepoChecksCard: View {
    let checks: RepoChecks
    let checking: Bool
    let useAnotherIdentity: (RepoCheckRow) -> Void
    let openAgents: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ready for Carrier").sectionLabel().padding(.horizontal, 14).padding(.top, 8)
            SettingsTabCard {
                ForEach(Array(checks.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 10) {
                        mark(row.status).padding(.top, 1)
                        checkText(row)
                        Spacer(minLength: 8)
                        if row.anotherIdentity != nil {
                            Button("Use another identity") { useAnotherIdentity(row) }.controlSize(.small)
                            Button("Open Agents", action: openAgents).controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8).frame(minHeight: 36)
                    .overlay(alignment: .top) { if index > 0 { SettingsDivider() } }
                    .accessibilityElement(children: .combine)
                }
            }
            // while the doctor runs each row says so itself, so the note under the card would say it twice
            if let note = checks.note, checking == false { Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14) }
        }
    }

    /// The check's title with its reason and its fix under it; what is wrong and how to mend it can be copied.
    @ViewBuilder private func checkText(_ row: RepoCheckRow) -> some View {
        let text = VStack(alignment: .leading, spacing: 1) {
            Text(row.title).fontWeight(.medium)
            if let detail = row.status == .waiting && checking ? "Checking…" : row.detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let fix = row.fix, row.status != .ok { Text("Fix: \(fix)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        let copyable = row.status == .ok || row.status == .waiting ? nil : [row.detail, row.fix].compactMap { $0 }.joined(separator: "\n")
        if let copyable, copyable.isEmpty == false { text.copyOnHover(copyable) } else { text }
    }

    private func mark(_ status: RepoCheckRow.Status) -> some View {
        // a row still waiting while the doctor runs turns instead of showing the grey dots
        if status == .waiting && checking {
            return AnyView(ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Checking"))
        }
        let (symbol, color, label): (String, Color, String) = switch status {
        case .ok: ("checkmark", .green, "Ready")
        case .warn: ("exclamationmark", .yellow, "Warning")
        case .fail: ("xmark", .orange, "Failed")
        case .waiting: ("ellipsis", .gray, "Waiting")
        }
        return AnyView(StatusMark(symbol: symbol, color: color, label: label))
    }
}

/// Who works here: each role with what it inherits from the global roles, or the repo's own, and the form to change or reset it. Each field
/// of the form is its own override: left on "Same as everywhere" it is not written.
private struct RepoRolesCard: View {
    let rows: [RepoRoleRow]
    @Binding var editing: AgentRole?
    let profiles: [String]
    let accounts: [String]
    /// the icon of each account, by its harness
    let icons: [String: String]
    /// why the doctor refused the config after the last save
    let refusal: String?
    let save: (AgentRole, RoleFields?) -> RoleSave
    let openAgents: () -> Void
    @State private var draft = RoleFields()
    @State private var problem: String?
    private let catalog = ModelCatalog.shared
    private let providers = AppHealth.providers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup(title: "Who works here") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    roleRow(row, first: index == 0)
                    if editing == row.role { form(row) }
                }
                if let note = signatureNote(rows) { Text(note).font(.caption).foregroundStyle(.secondary).padding(.vertical, 8) }
                if let refusal { Text(refusal).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.vertical, 8) }
                if editing == nil, let problem { Text(problem).font(.caption).foregroundStyle(.orange).padding(.vertical, 8) }
            }
            // the roles of Agents are another page's: its own item, not a row of this group
            SettingsTabCard {
                SettingsTabRow(title: "Defaults", detail: "Every repo follows the roles of Agents unless it has its own", first: true) {
                    Button("Open Agents", action: openAgents).controlSize(.small)
                }
            }
        }
        // the form opens from Change here or from a failed sign check above; either way it starts from the role's own fields
        .onChange(of: editing) { _, role in
            guard let row = rows.first(where: { $0.role == role }) else { return }
            draft = row.own
            problem = nil
        }
    }

    /// A role: the mark of its provider, its name and what it is set to, with a label on each part; on the right whether it follows the global
    /// roles or has its own, Reset when it has, and the chevron, which sits in a slot of its own and turns down while the form is open.
    private func roleRow(_ row: RepoRoleRow, first: Bool) -> some View {
        let open = editing == row.role
        return HStack(spacing: 12) {
            RoleTile(provider: row.value.provider, icons: icons)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).fontWeight(.medium)
                roleSummary(row.value).font(.caption).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(row.isOwn ? "Own settings" : "Same as everywhere").font(.caption).foregroundStyle(row.isOwn ? Color.themeAccent : Color.secondary)
            if row.isOwn { Button("Reset") { finish(save(row.role, nil)) }.controlSize(.small) }
            Button { editing = row.role } label: {
                Image(systemName: "chevron.right").font(.scaled(11, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(HoverTextButtonStyle(tint: nil)).disabled(open)
            .accessibilityLabel("Change \(row.title)").help("Change \(row.title)")
        }
        .padding(.vertical, 12).frame(minHeight: 56)
        .overlay(alignment: .top) { if first == false { SettingsDivider() } }
        // the whole row opens the form; Reset keeps its own click
        .contentShape(Rectangle()).onTapGesture { if open == false { editing = row.role } }
        .animation(.easeOut(duration: 0.15), value: open)
    }

    private func finish(_ result: RoleSave) {
        // a role the engine did not apply is saved, but the form stays open with what was typed and says what the engine answered: Save asks again
        if result == .saved { editing = nil }
        problem = result.problem
    }

    /// The role's own fields as a grid of a label and its control, the same edges all the way down, in three blocks with more room between them
    /// than inside them: who signs, how it runs and who it plays. A field left on "Same as everywhere" is not written and shows quieter.
    private func form(_ row: RepoRoleRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                choice("Identity", $draft.profile, options: profiles, inherited: row.inherited.profile)
                spacer
                field("Model") { modelPicker(row) }
                spacer
                field("Persona name") { TextField(row.inherited.persona?.name ?? "Name", text: persona(\.name)).settingsField() }
                field("Persona prompt", top: true) {
                    TextField(row.inherited.persona?.prompt ?? "Prompt", text: persona(\.prompt), axis: .vertical).lineLimit(3...8).settingsField()
                }
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                Spacer()
                Button { editing = nil } label: { Label("Cancel", systemImage: "xmark") }
                Button { finish(save(row.role, draft)) } label: { Label("Save", systemImage: "checkmark") }.buttonStyle(PrimaryCapsuleButtonStyle())
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 14)
        .writingToolsBehavior(.disabled)
    }

    /// The provider, the model and the reasoning of the role, from the one panel the Agents page has; what is left alone follows the global role.
    private func modelPicker(_ row: RepoRoleRow) -> some View {
        let reply: HostProviders? = if case .reply(let reply) = providers.outcome { reply } else { nil }
        let followed = row.inherited
        return ModelPickerButton(
            provider: draft.provider, model: draft.model, effort: draft.effort,
            accounts: pickerAccounts(reply, declared: accounts, icons: icons, current: [draft.provider ?? followed.provider].compactMap { $0 }), catalog: catalog,
            effortFallback: (
                label: "Same as everywhere",
                detail: followed.effort.map { "Follows the global role: \($0)." } ?? "Follows the global role, which names none: the CLI's own."
            ),
            inherited: PickerInherited(provider: followed.provider, model: followed.model, effort: followed.effort), fill: true
        ) { pick in
            switch pick {
            case .account(let account, let model):
                draft.provider = account
                draft.model = model
            case .effort(let level): draft.effort = level.isEmpty ? nil : level
            case .inherit:
                draft.provider = nil
                draft.model = nil
            case .none: break
            }
        }
        .task { await providers.load() }
    }

    /// More room between the blocks of the form than between its rows.
    private var spacer: some View { GridRow { Color.clear.frame(height: 6).gridCellColumns(2) } }

    private func field<Control: View>(_ title: String, top: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        GridRow(alignment: top ? .top : .center) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 104, alignment: .leading).padding(.top, top ? 7 : 0)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The system's pop-up of the choices. The first is "Same as everywhere" with what it is now, which writes nothing; a name that is no longer
    /// declared stays in the list, marked, so it is seen and refused on saving and not dropped.
    private func choice(_ title: String, _ value: Binding<String?>, options: [String], inherited: String?) -> some View {
        var items = ["Same as everywhere" + (inherited.map { " (\($0))" } ?? "")] + options
        if let own = value.wrappedValue, options.contains(own) == false { items.append("\(own) (missing)") }
        let index = Binding<Int>(
            get: { value.wrappedValue.flatMap { own in options.firstIndex(of: own).map { $0 + 1 } ?? items.count - 1 } ?? 0 },
            set: { next in value.wrappedValue = next == 0 ? nil : (options.indices.contains(next - 1) ? options[next - 1] : value.wrappedValue) }
        )
        return field(title) { NativePopUp(items: items, selection: index).accessibilityLabel(title) }
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

/// The last row of the repo list: a dashed tile of the size of the repos' own with a plus, and the words, in the row's shape.
private struct AddRepoRow: View {
    let add: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.scaled(13, weight: .semibold))
                    .frame(width: ProjectIcon.size, height: ProjectIcon.size)
                    .overlay(RoundedRectangle(cornerRadius: ProjectIcon.radius, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).opacity(0.5))
                Text("Add repo…")
                Spacer(minLength: 4)
            }
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(hovering ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Watch another repository")
    }
}

private struct RepoRowView: View {
    let row: RepoRow
    let engine: String
    let selected: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let clone = row.clonePath(engine: engine)
        let cloned = FileManager.default.fileExists(atPath: clone)
        HStack(alignment: .center, spacing: 10) {
            tile
            Text(title).lineLimit(1).truncationMode(.middle).frame(maxHeight: .infinity, alignment: .center)
            Spacer(minLength: 4)
            // the row says who it is and whether it needs the person; the rest (the line, the epics) is on the page
            if row.isNew { RepoChip(text: "new", tint: .green) }
            if let needs = row.epics?.needsYou, needs > 0 { RepoChip(text: "\(needs)", tint: .orange).accessibilityLabel("\(needs) need you") }
            Menu { actions(clone: clone, cloned: cloned) } label: {
                Image(systemName: "ellipsis").font(.scaled(14, weight: .semibold))
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
                    .frame(width: 26, height: 26)
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
        // the row of the Providers list: rounded, neutral when chosen
        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.secondary.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The same items in the row's menu and in its right-click menu.
    @ViewBuilder private func actions(clone: String, cloned: Bool) -> some View {
        Button { if let url = row.gitHubURL { NSWorkspace.shared.open(url) } } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square").labelStyle(.titleAndIcon) }
        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: clone)]) } label: {
            Label(cloned ? "Reveal clone in Finder" : "Reveal clone in Finder (not cloned yet)", systemImage: "folder").labelStyle(.titleAndIcon)
        }
        .disabled(cloned == false)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.name, forType: .string)
        } label: { Label("Copy owner/name", systemImage: "doc.on.doc").labelStyle(.titleAndIcon) }
        Divider()
        Button(role: .destructive, action: remove) { Label("Stop watching…", systemImage: "trash").labelStyle(.titleAndIcon) }
    }

    /// The owner dim, the name in bold.
    private var title: AttributedString {
        var owner = AttributedString(row.owner + "/")
        owner.foregroundColor = Color.secondary
        var repo = AttributedString(row.repo)
        repo.font = Font.body.weight(.semibold)
        return owner + repo
    }

    /// The project's icon, the letters of the sidebar, with the repo's health as a dot on its corner.
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            ProjectIcon(name: row.repo, colorKey: projectColorKey(row.name))
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

/// A count or a flag as a small capsule. The words are the colour lightened (darkened on a light window) over a fill of the colour, so they read
/// on the card and not only against their own tint.
private struct RepoChip: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(tint.mix(with: scheme == .dark ? .white : .black, by: 0.4))
            .padding(.horizontal, 7).padding(.vertical, 1.5).background(Capsule().fill(tint.opacity(scheme == .dark ? 0.24 : 0.18)))
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
    @State private var visibility = RepoVisibility.all
    @State private var owner: String?
    @State private var hideWatched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add repos from GitHub").font(.title3.weight(.semibold))
                Text("The repos your gh login can push to. Archived ones are left out.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)
            if let list, list.blocked == false {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search repos", text: $query).settingsField(icon: "magnifyingglass")
                    filters(list)
                }
            }
            content
            if let list, list.blocked == false, list.hasMore { loadMore(list) }
            HStack {
                Text(selected.isEmpty ? "" : "\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
                Button { add(chosen) } label: { Label(selected.count > 1 ? "Add \(selected.count) repos" : "Add repo", systemImage: "plus") }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 560, height: 580)
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

    /// Visibility as chips that exclude each other, the owner as a pop-up when there is more than one, and whether the ones already watched show.
    private func filters(_ list: AvailableReposList) -> some View {
        let owners = list.repos.reduce(into: [String]()) { found, repo in
            let name = String(repo.name.split(separator: "/").first ?? "")
            if found.contains(name) == false { found.append(name) }
        }
        return HStack(spacing: 6) {
            FilterChip(title: "All", on: visibility == .all) { visibility = .all }
            FilterChip(title: "Private", icon: "lock", on: visibility == .onlyPrivate) { visibility = visibility == .onlyPrivate ? .all : .onlyPrivate }
            FilterChip(title: "Public", icon: "globe", on: visibility == .onlyPublic) { visibility = visibility == .onlyPublic ? .all : .onlyPublic }
            Spacer(minLength: 8)
            if owners.count > 1 {
                NativePopUp(
                    items: ["All owners"] + owners,
                    selection: Binding(get: { owner.flatMap { owners.firstIndex(of: $0) }.map { $0 + 1 } ?? 0 }, set: { owner = $0 == 0 ? nil : owners[$0 - 1] })
                )
                .accessibilityLabel("Owner").frame(width: 130)
            }
            FilterChip(title: "Hide watched", icon: hideWatched ? "eye.slash" : "eye", on: hideWatched) { hideWatched.toggle() }
        }
    }

    private func loadMore(_ list: AvailableReposList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Partial list: \(list.repos.count) repos so far, and there are more. Search only looks at these.").font(.caption).foregroundStyle(.secondary)
            if let problem = list.problem, let text = availableReposMessage(problem) {
                Text("\(text.title). \(text.detail)").font(.caption).foregroundStyle(.red)
            }
            Button { loadNextPage() } label: { Label(loadingMore ? "Loading…" : "Load more", systemImage: "arrow.down.circle") }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(loadingMore)
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
                ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)).frame(height: 46) }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity).accessibilityLabel("Loading your repos")
        case let list? where list.blocked == false:
            let groups = repoGroups(list.repos, watched: watched, selected: selected, query: query, visibility: visibility, owner: owner, hideWatched: hideWatched)
            if groups.isEmpty {
                message(
                    "magnifyingglass", query.isEmpty ? "No repo matches the filters" : "No repo matches “\(query)”",
                    "Only repos your gh login can push to are listed, and the filters narrow them."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groups) { group in
                            Text(group.owner).sectionLabel().padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
                            ForEach(group.choices) { choice in choiceRow(choice) }
                        }
                    }
                    .padding(8)
                }
                .settingsCard()
            }
        case let list?:
            let text = list.problem.flatMap(availableReposMessage)
            message("exclamationmark.triangle", text?.title ?? "", text?.detail ?? "")
        }
    }

    /// A repo to choose, in the shape of the repo list: its tile, the owner dim and the name bold, when it was pushed under them, `private` as a chip
    /// and a round mark at the right that fills when it is chosen. A repo already watched shows the mark filled and quiet, and cannot be chosen.
    private func choiceRow(_ choice: RepoChoice) -> some View {
        let on = choice.watched || selected.contains(choice.name)
        let parts = choice.name.split(separator: "/", maxSplits: 1).map(String.init)
        var owner = AttributedString(parts.count == 2 ? parts[0] + "/" : "")
        owner.foregroundColor = Color.secondary
        var name = AttributedString(parts.last ?? choice.name)
        name.font = Font.body.weight(.semibold)
        return Button {
            if selected.contains(choice.name) { selected.remove(choice.name) } else { selected.insert(choice.name) }
        } label: {
            HStack(spacing: 10) {
                ProjectIcon(name: parts.last ?? choice.name, colorKey: projectColorKey(choice.name))
                VStack(alignment: .leading, spacing: 1) {
                    Text(owner + name).lineLimit(1).truncationMode(.middle)
                    if choice.detail.isEmpty == false { Text(choice.detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                if choice.isPrivate { RepoChip(text: "private", tint: .gray) }
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.scaled(17))
                    .foregroundStyle(choice.watched ? Color.secondary : on ? Color.themeAccent : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected.contains(choice.name) ? Color.secondary.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(choice.disabled).opacity(choice.disabled ? 0.55 : 1)
        .accessibilityElement(children: .combine).accessibilityValue(on ? "selected" : "not selected")
    }

    private func message(_ icon: String, _ title: String, _ detail: String) -> some View {
        EmptyStateView(icon: icon, title: title, line: detail)
            .settingsCard()
    }
}
