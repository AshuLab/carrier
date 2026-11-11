import AppKit
import CarrierCore
import SwiftUI

/// The Agents page of Settings (docs/specs/agents-in-settings.md): the three roles of every epic in a list, and for the chosen one its Who,
/// Details and When it runs out of tokens cards. It reads `config.json`, `providers.json` and the Agent Forge registry (`agentsPage`, tested
/// in `AgentsPageTests`); the Who card writes one field of one role as it changes (`saveGlobalRole`, tested in `GlobalRoleSaveTests`). The page has no
/// automated test.
struct AgentsTabView: View {
    @ObservedObject private var start = StartController.shared
    @State private var page: AgentsPage?
    @State private var selection: AgentRole = .author
    /// why the last change was refused, in words; nothing was written
    @State private var problem: String?
    /// Switch automatically turned on for a role that has no first step yet: nothing is written until it has one
    @State private var switchedOn: Set<AgentRole> = []
    /// the Lead reviewer's switch is on in the page and the file has no role yet: what is chosen waits here until the role is whole
    @State private var turningOnLead = false
    @State private var leadDraft = LeadReviewerDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let page {
                HStack(alignment: .top, spacing: 16) {
                    list(page).frame(width: 300)
                    if let row = page.rows.first(where: { $0.role == selection }) { detail(turningOnLead && row.role == .leadReviewer ? leadDraft.shown(in: row) : row, page: page).frame(maxWidth: .infinity, alignment: .topLeading) }
                }
                if let note = page.sharedNote { Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
                if let note = page.bots.note { Text(note).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
                Text("Carrier reads this when it starts.").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            } else {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .onAppear(perform: load)
        .onChange(of: start.configExists) { load() }
        // back from Terminal or an editor, where the config or the registry may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    private func load() {
        let providers = try? Data(contentsOf: URL(fileURLWithPath: currentCarrierFolder() + "/providers.json"))
        problem = nil
        page = currentConfig().flatMap { agentsPage(config: $0, providers: providers, bots: forgeBots(registry: currentForgeRegistry())) }
    }

    /// Writes the change, then reads the file back so the page shows what is there, whether it was saved or refused.
    private func save(_ change: RoleChange, role: AgentRole, page: AgentsPage) -> RoleSave {
        if role == .leadReviewer, turningOnLead { return fillLead(change, page: page) }
        let result = saveGlobalRole(change, role: role, path: configFilePath(), accounts: page.accounts, bots: page.bots.names)
        let reason: String?
        switch result {
        case .saved: reason = nil
        case .refused(let why), .failed(let why): reason = why
        }
        load()
        problem = reason
        return result
    }

    /// The Details and failover cards write through here (`saveGlobalPersona`, `saveGlobalFailover`; tested in `RoleDetailsSaveTests`), then read the file back.
    private func saveDetails(_ result: RoleSave) -> Bool {
        load()
        if case .refused(let why) = result { problem = why } else if case .failed(let why) = result { problem = why }
        return result == .saved
    }

    /// A choice for the role being turned on: kept in the draft, and written only when identity, provider and model are all there.
    private func fillLead(_ change: RoleChange, page: AgentsPage) -> RoleSave {
        leadDraft.apply(change)
        guard leadDraft.isComplete else { return .saved }
        let result = turnLeadReviewerOn(leadDraft, path: configFilePath(), accounts: page.accounts, bots: page.bots.names)
        if result == .saved {
            turningOnLead = false
            leadDraft = LeadReviewerDraft()
        }
        load()
        if case .refused(let why) = result { problem = why } else if case .failed(let why) = result { problem = why }
        return result
    }

    private func setLeadSwitch(on: Bool, row: RoleRow) {
        leadDraft = LeadReviewerDraft()
        problem = nil
        if on {
            turningOnLead = true
        } else if row.off {
            turningOnLead = false
        } else {
            turningOnLead = false
            let result = turnLeadReviewerOff(path: configFilePath())
            load()
            if case .refused(let why) = result { problem = why } else if case .failed(let why) = result { problem = why }
        }
    }

    private func list(_ page: AgentsPage) -> some View {
        SettingsTabCard {
            ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                Button { selection = row.role } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).fontWeight(.medium)
                        Text(row.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                    .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .background(row.role == selection ? Color.themeAccent.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Divider().opacity(index == 0 ? 0 : 1) }
                .accessibilityAddTraits(row.role == selection ? .isSelected : [])
            }
        }
    }

    private func detail(_ row: RoleRow, page: AgentsPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if row.hasSwitch {
                SettingsTabCard {
                    SettingsTabRow(title: "Use a lead reviewer", detail: row.switchDetail, first: true) {
                        Toggle("Use a lead reviewer", isOn: Binding(get: { row.usable(turningOn: turningOnLead) }, set: { setLeadSwitch(on: $0, row: row) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                if turningOnLead, let hint = leadDraft.hint { Text(hint).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
            }
            VStack(alignment: .leading, spacing: 12) {
                SettingsGroup(title: "Who") {
                    SettingsTabRow(title: "Identity", detail: row.identityDetail, first: true) { identityPicker(row, page: page) }
                    CreateBotRow()
                    SettingsTabRow(title: "Provider", detail: row.providerMissing ? "Not an account of providers.json" : "An account from Providers") {
                        picker("Provider", selection: row.fields.provider ?? "", options: page.accounts) {
                            _ = save(.provider($0), role: row.role, page: page)
                        }
                    }
                    SettingsTabRow(title: "Model", detail: "") {
                        ModelField(model: row.fields.model ?? "") { save(.model($0), role: row.role, page: page) == .saved }
                            .id(row.role)
                    }
                    SettingsTabRow(title: "Effort", detail: "How hard it thinks") {
                        picker("Effort", selection: row.fields.effort ?? "", options: roleEfforts, none: "Default") {
                            _ = save(.effort($0.isEmpty ? nil : $0), role: row.role, page: page)
                        }
                    }
                    if let problem { Text(problem).font(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.vertical, 8) }
                }
                SettingsGroup(title: "Details") {
                    SettingsTabRow(title: "Persona name", detail: "Optional, one line up to 40 characters", first: true) {
                        CommitField(label: "Persona name", text: row.fields.persona?.name ?? "", width: 220, mono: false) {
                            saveDetails(saveGlobalPersona(name: blankIsNil($0), prompt: row.fields.persona?.prompt, role: row.role, path: configFilePath()))
                        }
                        .id(row.role)
                    }
                    SettingsTabRow(title: "Persona prompt", detail: "Optional instructions") {
                        CommitField(label: "Persona prompt", text: row.fields.persona?.prompt ?? "", width: 220, mono: false) {
                            saveDetails(saveGlobalPersona(name: row.fields.persona?.name, prompt: blankIsNil($0), role: row.role, path: configFilePath()))
                        }
                        .id(row.role)
                    }
                }
                SettingsGroup(title: "When it runs out of tokens") {
                    let on = row.steps.isEmpty == false || switchedOn.contains(row.role)
                    SettingsTabRow(title: "Switch automatically", detail: "Usage limit, rate limit or service down", first: true) {
                        Toggle("Switch automatically", isOn: Binding(get: { on }, set: { now in
                            if now { switchedOn.insert(row.role) } else {
                                switchedOn.remove(row.role)
                                _ = saveDetails(saveGlobalFailover(first: nil, second: nil, role: row.role, path: configFilePath(), accounts: page.accounts))
                            }
                        })).labelsHidden().toggleStyle(.switch)
                    }
                    if on {
                        stepRow("First", detail: "Provider and model", step: row.steps.first, row: row, page: page, index: 0)
                        stepRow("Then", detail: "Optional", step: row.steps.dropFirst().first, row: row, page: page, index: 1)
                    }
                    if row.steps.count > 2 {
                        Text("The file has \(row.steps.count - 2) more step\(row.steps.count == 3 ? "" : "s"), kept and tried in order.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
            }
            // while the lead reviewer is off the rest of its page is shown, dimmed and not usable
            .opacity(row.usable(turningOn: turningOnLead) ? 1 : 0.4).disabled(row.usable(turningOn: turningOnLead) == false)
        }
    }

    private func blankIsNil(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// A step of the role's failover: a provider and, optionally, a model. Then can be taken back to None; First needs a provider before anything is written.
    private func stepRow(_ title: String, detail: String, step: FailoverStep?, row: RoleRow, page: AgentsPage, index: Int) -> some View {
        func write(_ own: FailoverStep?) -> Bool {
            let first = index == 0 ? own : row.steps.first
            let second = index == 1 ? own : row.steps.dropFirst().first
            return saveDetails(saveGlobalFailover(first: first, second: second, role: row.role, path: configFilePath(), accounts: page.accounts))
        }
        return SettingsTabRow(title: title, detail: detail) {
            HStack(spacing: 8) {
                picker(title, selection: step?.provider ?? "", options: page.accounts, none: index == 0 ? "Choose…" : "None") { provider in
                    _ = write(provider.isEmpty ? nil : FailoverStep(provider: provider, model: step?.model))
                }
                if let step {
                    CommitField(label: "\(title) model", text: step.model ?? "", width: 160, mono: true, prompt: "Account’s model") {
                        write(FailoverStep(provider: step.provider, model: $0))
                    }
                    .id(row.role.rawValue + title + step.provider)
                }
            }
        }
    }

    /// The bots of the registry and the person's own login; a profile that is no longer there stays, marked, and picking it again is a no-op.
    private func identityPicker(_ row: RoleRow, page: AgentsPage) -> some View {
        let current: String
        switch row.identity {
        case .forge(let bot): current = "bot:" + bot
        case .gh: current = "gh"
        case .missing, .unset: current = "keep"
        }
        return Picker("Identity", selection: Binding(get: { current }, set: { choice in
            if choice == "gh" { _ = save(.gh, role: row.role, page: page) }
            else if choice.hasPrefix("bot:") { _ = save(.bot(String(choice.dropFirst(4))), role: row.role, page: page) }
        })) {
            if current == "keep" { Text(row.fields.profile.map { "\($0) (missing)" } ?? "Not set").tag("keep") }
            ForEach(page.bots.names, id: \.self) { Text($0).tag("bot:" + $0) }
            Text("Your gh login").tag("gh")
        }
        .labelsHidden().fixedSize()
    }

    /// A name that is no longer declared stays in the list, marked, so it is seen and refused when chosen again, not dropped.
    private func picker(_ title: String, selection: String, options: [String], none: String? = nil, set: @escaping (String) -> Void) -> some View {
        Picker(title, selection: Binding(get: { selection }, set: set)) {
            if let none { Text(none).tag("") }
            if selection.isEmpty == false, options.contains(selection) == false { Text("\(selection) (missing)").tag(selection) }
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden().fixedSize()
    }
}

/// A text saved when the person presses Return or leaves the field; what the file refuses is put back.
private struct CommitField: View {
    let label: String
    let text: String
    let width: CGFloat
    let mono: Bool
    var prompt = ""
    let commit: (String) -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(label: String, text: String, width: CGFloat, mono: Bool, prompt: String = "", commit: @escaping (String) -> Bool) {
        self.label = label
        self.text = text
        self.width = width
        self.mono = mono
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField(label, text: $draft, prompt: Text(prompt)).textFieldStyle(.roundedBorder)
            .font(mono ? .scaled(11.5, design: .monospaced) : .body).frame(width: width)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel(label)
    }

    private func save() {
        guard draft != text else { return }
        if commit(draft) == false { draft = text }
    }
}

/// The model, saved when the person presses Return or leaves the field; what the file refuses is put back.
private struct ModelField: View {
    let model: String
    let commit: (String) -> Bool
    @State private var text: String
    @FocusState private var focused: Bool

    init(model: String, commit: @escaping (String) -> Bool) {
        self.model = model
        self.commit = commit
        _text = State(initialValue: model)
    }

    var body: some View {
        TextField("Model", text: $text).textFieldStyle(.roundedBorder).font(.scaled(11.5, design: .monospaced)).frame(width: 220)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel("Model")
    }

    private func save() {
        guard text != model else { return }
        if commit(text) == false { text = model }
    }
}
