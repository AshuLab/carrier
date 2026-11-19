import AppKit
import CarrierCore
import SwiftUI

/// The Agents page of Settings (docs/specs/agents-in-settings.md), two kinds of screen, each a place of the window's history (‹ ›) as the Providers and
/// Dictation pages have: the first (whether the roles are set up, and the three roles of an epic joined by a rail) and one for each role, with its
/// Who, Persona, Skills and When it runs out of tokens groups. It reads `engine.json`, `providers.json` and the Agent Forge registry (`agentsPage`, tested
/// in `AgentsPageTests`); a role's screen writes one field of one role as it changes (`saveGlobalRole`, tested in `GlobalRoleSaveTests`). The page has no
/// automated test.
struct AgentsTabView: View {
    /// Where the page is: nothing for the first screen, or the path of a role (`AgentRole.rawValue`).
    var place = SettingsPlace(.agents)
    var go: (SettingsPlace) -> Void = { _ in }
    @ObservedObject private var start = StartController.shared
    @State private var page: AgentsPage?
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

    private var role: AgentRole? { place.path.first.flatMap(AgentRole.init(rawValue:)) }

    var body: some View {
        SettingsPageBody {
            if let page {
                if let role, let row = page.rows.first(where: { $0.role == role }) {
                    detail(turningOnLead && row.role == .leadReviewer ? leadDraft.shown(in: row) : row, page: page)
                } else {
                    first(page)
                }
                ReloadNote()
            } else {
                Label("The engine is not configured: engine.json in the Carrier folder is missing or is not a JSON object.", icon: .warningFilled)
                    .font(.scaled(12)).foregroundStyle(.orange)
            }
        }
        .id(role)
        .preference(key: SettingsTitleKey.self, value: title)
        .writingToolsBehavior(.disabled)
        .onAppear(perform: load)
        // which accounts can work now is the Providers page's answer, asked again here so the picker does not offer one that was signed out
        .task { await providers.load() }
        .onChange(of: start.configExists) { load() }
        // what a screen said or was waiting for (a refusal, the lead reviewer being turned on) belongs to that screen
        .onChange(of: place) {
            problem = nil
            turningOnLead = false
            leadDraft = LeadReviewerDraft()
        }
        // back from Terminal or an editor, where the config or the registry may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    /// What the toolbar says of a role's screen: its name and, under it, the model, the effort and who it works as.
    private var title: SettingsTitle? {
        guard let role, let row = page?.rows.first(where: { $0.role == role }) else { return nil }
        return SettingsTitle(text: row.title, subtitle: (turningOnLead && role == .leadReviewer ? leadDraft.shown(in: row) : row).headline)
    }

    private func open(_ role: AgentRole) { go(SettingsPlace(.agents, path: [role.rawValue])) }

    private func load() {
        let providers = try? Data(contentsOf: URL(fileURLWithPath: CarrierPlaces().providers))
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

    /// The Persona and failover groups write through here (`saveGlobalPersona`, `saveGlobalFailover`; tested in `RoleDetailsSaveTests`), then read the file back.
    private func saveDetails(_ result: RoleSave) -> Bool {
        load()
        problem = result.problem
        return result == .saved
    }

    /// A choice for the role being turned on: kept in the draft, and written only when identity, provider and model are all there.
    private func fillLead(_ changes: [RoleChange], page: AgentsPage) -> RoleSave {
        changes.forEach { leadDraft.apply($0) }
        guard leadDraft.isComplete else { return .saved }
        let result = turnLeadReviewerOn(leadDraft, path: configFilePath(), accounts: page.accounts, bots: page.bots.names)
        if result == .saved {
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

    /// The first screen: whether the roles are set up, the three roles of an epic, and the bots they work as.
    @ViewBuilder private func first(_ page: AgentsPage) -> some View {
        let readiness = agentsReadiness(page)
        SettingsGroup(title: "") { AgentsStatusCard(readiness: readiness, open: open) }
        SettingsGroup(title: EpicRail.group) { EpicRail(page: page, readiness: readiness, icons: icons, open: open) }
        SettingsGroup(title: "Identities", footer: page.bots.note ?? "A bot is the GitHub account a role works as. Every role can pick one.") {
            CreateBotRow()
        }
    }

    private func detail(_ row: RoleRow, page: AgentsPage) -> some View {
        // a Group and not a stack: the groups below are sections of the page's form
        Group {
            if row.hasSwitch {
                SettingsGroup(title: "", footer: turningOnLead ? leadDraft.hint : nil) {
                    SettingsTabRow(title: "Use a lead reviewer", detail: row.switchDetail, first: true) {
                        Toggle("Use a lead reviewer", isOn: Binding(get: { row.usable(turningOn: turningOnLead) }, set: { setLeadSwitch(on: $0, row: row) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            SettingsGroup(title: "") {
                RoleHero(row: row, page: page, icons: icons)
                RoleFlowStrip(current: row.role, rows: page.rows, open: open)
            }
            Group {
                SettingsGroup(title: "Who", footer: identityFooter(row, page: page)) {
                    SettingsTabRow(title: "Identity", detail: row.identityDetail, first: true) { identityPicker(row, page: page) }
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
                    if let problem { ProblemLine(text: problem, font: .scaled(11)).textSelection(.enabled).padding(.vertical, 8) }
                }
                SettingsGroup(title: "Persona") {
                    SettingsTabRow(title: "Persona name", detail: "Optional, one line up to 40 characters", first: true) {
                        CommitField(label: "Persona name", text: row.fields.persona?.name ?? "", width: settingsSelectWidth, mono: false, prompt: "None") {
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
                skills(row)
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
                        stepRow("Try first", detail: "Provider, model and reasoning", step: row.steps.first, row: row, page: page, index: 0)
                        stepRow("Then try", detail: "Optional", step: row.steps.dropFirst().first, row: row, page: page, index: 1)
                    }
                    if row.steps.count > 2 {
                        Text("The file has \(row.steps.count - 2) more step\(row.steps.count == 3 ? "" : "s"), kept and tried in order.")
                            .font(.scaled(11)).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
            }
            // while the lead reviewer is off the rest of its page is shown, dimmed and not usable
            .opacity(row.usable(turningOn: turningOnLead) ? 1 : 0.4).disabled(row.usable(turningOn: turningOnLead) == false)
        }
    }

    /// What the engine runs in each stage of the role, as the engine has it today: shown and not changeable yet (a later version of the engine reads
    /// it from the config). `AgentsReadinessTests` keeps `AgentRole.stages` equal to what `src/prompts` invokes.
    @ViewBuilder private func skills(_ row: RoleRow) -> some View {
        if row.role.stages.isEmpty {
            SettingsGroup(title: "Skills") {
                SettingsTabRow(title: "Not used by the engine yet", detail: "The Lead reviewer has no stage today, so there is no skill to choose.", first: true) {
                    StatusChip(text: "Soon", tint: .secondary)
                }
            }
        } else {
            SettingsGroup(title: "Skills", footer: "Each stage runs the skill shown. Choosing another one comes with a later version of the engine.") {
                ForEach(row.role.stages) { stage in
                    SettingsTabRow(
                        title: stage.title, detail: stage.detail,
                        note: "Runs as \(skillInvocation(stage.skill, icon: row.fields.provider.flatMap { icons[$0] }))"
                    ) {
                        SkillValue(skill: stage.skill)
                    }
                }
            }
        }
    }

    /// What is said under Identity where the person chooses it, not only on the first screen: that Author and Reviewer sign as one account, and why the
    /// list of bots is empty (no registry, or one that does not read).
    private func identityFooter(_ row: RoleRow, page: AgentsPage) -> String? {
        let shared = row.role == .leadReviewer ? nil : page.sharedNote
        let lines = [shared, page.bots.note].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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
        return SelectMenu(items: items, selection: index).accessibilityLabel("Identity")
    }
}

/// The skill of a stage as a value that is not editable yet: its name in the box of a field, with "Default" before it.
private struct SkillValue: View {
    let skill: String

    var body: some View {
        HStack(spacing: 8) {
            StatusChip(text: "Default", tint: .secondary)
            Text(skill).font(.scaled(11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 5).frame(width: 150, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skill")
        .accessibilityValue("\(skill), the default; it cannot be changed yet")
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
            .font(mono ? .scaled(11.5, design: .monospaced) : .scaled(13)).settingsField(width: width, focused: $focused)
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
        TextEditor(text: $draft).font(.scaled(13)).scrollContentBackground(.hidden).frame(height: 96)
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
