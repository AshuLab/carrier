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
    /// the icon of each account by the harness it runs
    @State private var icons: [String: String] = [:]
    private let catalog = ModelCatalog.shared
    private let providers = AppHealth.providers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let page {
                flow(page)
                if let row = page.rows.first(where: { $0.role == selection }) { detail(turningOnLead && row.role == .leadReviewer ? leadDraft.shown(in: row) : row, page: page).frame(maxWidth: .infinity, alignment: .topLeading) }
                ReloadNote().padding(.horizontal, 4)
                if let note = page.sharedNote { Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
                if let note = page.bots.note { Text(note).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
            } else {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .writingToolsBehavior(.disabled)
        .onAppear(perform: load)
        // which accounts can work now is the Providers page's answer, asked again here so the picker does not offer one that was signed out
        .task { await providers.load() }
        .onChange(of: start.configExists) { load() }
        // back from Terminal or an editor, where the config or the registry may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    private func load() {
        let providers = try? Data(contentsOf: URL(fileURLWithPath: currentCarrierFolder() + "/providers.json"))
        problem = nil
        icons = accountIcons(providersJSON: providers)
        page = currentConfig().flatMap { agentsPage(config: $0, providers: providers, bots: forgeBots(registry: currentForgeRegistry())) }
    }

    /// Writes the change, then reads the file back so the page shows what is there, whether it was saved or refused.
    private func save(_ change: RoleChange, role: AgentRole, page: AgentsPage) -> RoleSave {
        save([change], role: role, page: page)
    }

    /// Several changes of one pick are one write and one ask of the engine.
    private func save(_ changes: [RoleChange], role: AgentRole, page: AgentsPage) -> RoleSave {
        if role == .leadReviewer, turningOnLead { return fillLead(changes, page: page) }
        let result = saveGlobalRole(changes, role: role, path: configFilePath(), accounts: page.accounts, bots: page.bots.names)
        load()
        problem = result.problem
        return result
    }

    /// The Details and failover cards write through here (`saveGlobalPersona`, `saveGlobalFailover`; tested in `RoleDetailsSaveTests`), then read the file back.
    private func saveDetails(_ result: RoleSave) -> Bool {
        load()
        problem = result.problem
        return result.isWritten
    }

    /// A choice for the role being turned on: kept in the draft, and written only when identity, provider and model are all there.
    private func fillLead(_ changes: [RoleChange], page: AgentsPage) -> RoleSave {
        changes.forEach { leadDraft.apply($0) }
        guard leadDraft.isComplete else { return .saved }
        let result = turnLeadReviewerOn(leadDraft, path: configFilePath(), accounts: page.accounts, bots: page.bots.names)
        if result.isWritten {
            turningOnLead = false
            leadDraft = LeadReviewerDraft()
        }
        load()
        problem = result.problem
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
            problem = result.problem
        }
    }

    /// The three roles side by side in the order an epic goes through them, an arrow between each pair, and the chosen one is the page below.
    private func flow(_ page: AgentsPage) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                // the author and the reviewer go back and forth until the review passes: a double arrow; the lead reviewer comes after them
                if index > 0 {
                    Image(systemName: index == 1 ? "arrow.left.arrow.right" : "arrow.right").font(.scaled(12, weight: .semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                roleCard(row)
            }
        }
    }

    private func roleCard(_ row: RoleRow) -> some View {
        let chosen = row.role == selection
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { selection = row.role } label: {
            HStack(spacing: 10) {
                RoleTile(provider: row.fields.provider, icons: icons, off: row.off)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).fontWeight(.medium)
                    listLines(row)
                }
                Spacer(minLength: 0)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.secondary.opacity(chosen ? 0.18 : 0.07)))
            .overlay { if chosen { shape.strokeBorder(Color.themeAccent, lineWidth: 1.5) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Under a role's name in the list, what answers the question the list is for: the model and how hard it thinks, in the text colour, and under it
    /// the account and the identity it works as.
    @ViewBuilder private func listLines(_ row: RoleRow) -> some View {
        if row.off {
            Text("Off").font(.caption).foregroundStyle(.secondary)
        } else {
            let model = row.fields.model.flatMap { $0.isEmpty ? nil : $0 }
            let effort = row.fields.effort.flatMap { $0.isEmpty ? nil : $0 }
            (Text(model ?? "No model").fontWeight(.medium).foregroundStyle(model == nil ? Color.secondary : Color.primary)
                + Text(effort.map { "  \u{00b7}  \($0)" } ?? "").foregroundStyle(.secondary))
                .font(.caption).lineLimit(1)
            Text([row.fields.provider, row.fields.profile].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: "  \u{00b7}  "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func detail(_ row: RoleRow, page: AgentsPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if row.hasSwitch {
                SettingsTabCard {
                    SettingsTabRow(title: "Use a lead reviewer", detail: row.switchDetail, first: true) {
                        Toggle("Use a lead reviewer", isOn: Binding(get: { row.usable(turningOn: turningOnLead) }, set: { setLeadSwitch(on: $0, row: row) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                if turningOnLead, let hint = leadDraft.hint { Text(hint).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4) }
            }
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup(title: "Who") {
                    SettingsTabRow(title: "Identity", detail: row.identityDetail, first: true) { identityPicker(row, page: page) }
                    CreateBotRow()
                    SettingsTabRow(title: "Model", detail: row.providerMissing ? "Not an account of providers.json" : "Provider, model and how hard it thinks") {
                        ModelPickerButton(
                            provider: row.fields.provider, model: row.fields.model, effort: row.fields.effort,
                            accounts: pickerAccounts(page: page, current: [row.fields.provider]), catalog: catalog
                        ) { pick in
                            switch pick {
                            case .account(let account, let model):
                                // the model belongs to the account's provider: written together, in one save
                                let changes = (account != row.fields.provider ? [RoleChange.provider(account)] : []) + (model.map { [RoleChange.model($0)] } ?? [])
                                if changes.isEmpty == false { _ = save(changes, role: row.role, page: page) }
                            case .effort(let level): _ = save(.effort(level.isEmpty ? nil : level), role: row.role, page: page)
                            case .none, .inherit: break
                            }
                        }
                    }
                    if let problem { ProblemLine(text: problem, font: .caption).textSelection(.enabled).padding(.vertical, 8) }
                }
                SettingsGroup(title: "Details") {
                    SettingsTabRow(title: "Persona name", detail: "Optional, one line up to 40 characters", first: true) {
                        CommitField(label: "Persona name", text: row.fields.persona?.name ?? "", width: 220, mono: false, prompt: "None") {
                            saveDetails(saveGlobalPersona(name: blankIsNil($0), prompt: row.fields.persona?.prompt, role: row.role, path: configFilePath()))
                        }
                        .id(row.role)
                    }
                    SettingsStackedRow(title: "Persona prompt", detail: "Optional instructions") {
                        CommitEditor(label: "Persona prompt", text: row.fields.persona?.prompt ?? "", prompt: "None") {
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
                        stepRow("First", detail: "Provider, model and reasoning", step: row.steps.first, row: row, page: page, index: 0)
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
            ModelPickerButton(
                provider: step?.provider, model: step?.model, effort: step?.effort, accounts: pickerAccounts(page: page, current: [step?.provider]), catalog: catalog,
                effortFallback: (label: "As the role", detail: "Keeps the reasoning the role was running with."), allowsDefaultModel: true, noneTitle: index == 1 ? "No second step" : nil, placeholder: index == 0 ? "Choose…" : "None"
            ) { pick in
                switch pick {
                case .account(let account, let model): _ = write(FailoverStep(provider: account, model: model, effort: step?.effort))
                case .none: _ = write(nil)
                case .inherit: break
                case .effort(let level):
                    // a level goes with a provider: with none yet there is nothing to write it on
                    if let step { _ = write(FailoverStep(provider: step.provider, model: step.model, effort: level.isEmpty ? nil : level)) }
                }
            }
        }
    }

    /// The accounts the picker offers: the ones that can work now, and the one the role already names.
    private func pickerAccounts(page: AgentsPage, current: [String?]) -> [PickerAccount] {
        let reply: HostProviders? = if case .reply(let reply) = providers.outcome { reply } else { nil }
        return CarrierCore.pickerAccounts(reply, declared: page.accounts, icons: icons, current: current.compactMap { $0 })
    }

    /// The bots of the registry and the person's own login; a profile that is no longer there stays, marked, and picking it again is a no-op.
    private func identityPicker(_ row: RoleRow, page: AgentsPage) -> some View {
        let current: String
        switch row.identity {
        case .forge(let bot): current = "bot:" + bot
        case .gh: current = "gh"
        case .missing, .unset: current = "keep"
        }
        var values: [String] = [], items: [String] = []
        if current == "keep" {
            values.append("keep")
            items.append(row.fields.profile.map { "\($0) (missing)" } ?? "Not set")
        }
        values += page.bots.names.map { "bot:" + $0 }
        items += page.bots.names
        values.append("gh")
        items.append("Your gh login")
        let index = Binding<Int>(
            get: { values.firstIndex(of: current) ?? 0 },
            set: { next in
                let choice = values[next]
                if choice == "gh" { _ = save(.gh, role: row.role, page: page) }
                else if choice.hasPrefix("bot:") { _ = save(.bot(String(choice.dropFirst(4))), role: row.role, page: page) }
            }
        )
        return NativePopUp(items: items, selection: index).accessibilityLabel("Identity").frame(width: 220)
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
        TextField(label, text: $draft, prompt: Text(prompt))
            .font(mono ? .scaled(11.5, design: .monospaced) : .body).settingsField(width: width, focused: $focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel(label)
    }

    private func save() {
        guard draft != text else { return }
        if commit(draft) == false { draft = text }
    }
}

/// A text of several lines saved when the person leaves it (a return is a new line here, so there is no key that saves); what the file refuses is
/// put back. In the box of `settingsField`, with the prompt shown while it is empty.
private struct CommitEditor: View {
    let label: String
    let text: String
    var prompt = ""
    let commit: (String) -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(label: String, text: String, prompt: String = "", commit: @escaping (String) -> Bool) {
        self.label = label
        self.text = text
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextEditor(text: $draft).font(.body).scrollContentBackground(.hidden).frame(height: 96)
            .overlay(alignment: .topLeading) {
                if draft.isEmpty { Text(prompt).foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false) }
            }
            .settingsField(focused: $focused)
            // the system's writing tools (and its "Write with Siri" button, which sits on the box) have nothing to do with an instruction for an agent
            .writingToolsBehavior(.disabled)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel(label)
    }

    private func save() {
        guard draft != text else { return }
        if commit(draft) == false { draft = text }
    }
}
