import CarrierCore
import SwiftUI

/// A role's screen in a repo (`SettingsPlace(.watching, path: [repo, role])`), the Agents page's own screen for what a repo can set: its picture and who it
/// works as, its place in an epic, Who (Identity and Model) and Persona. A field left on "Same as everywhere" is not written to the repo and shows what it
/// follows; one the repo sets says Own, and Reset to Agents takes all of them out. Each field is sent as it changes (`editRepoRole`, which the engine writes, `src/config/role-edit.ts`);
/// the file is read again after each one, so `row` and `mine` are what it holds.
struct RepoRoleScreen: View {
    /// The role as the repo has it (the repo's own fields over the global ones), as Agents draws a role.
    let row: RoleRow
    /// Its own fields and the global ones it follows.
    let mine: RepoRoleRow
    let page: AgentsPage
    let profiles: [String]
    let accounts: [String]
    let icons: [String: String]
    /// Writes the repo's own fields of the role, nil taking them all out.
    let save: (RoleFields?) async -> RoleSave
    let open: (AgentRole) -> Void
    @State private var problem: String?
    private let catalog = ModelCatalog.shared
    private let providers = AppHealth.providers

    var body: some View {
        Group {
            SettingsGroup(title: "") {
                RoleHero(row: row, page: page, icons: icons)
                RoleFlowStrip(current: row.role, rows: page.rows, open: open)
            }
            SettingsGroup(id: "who", title: Copy.agentsGroupWho(), footer: mine.isOwn ? nil : Copy.watchingRoleWhoFooter(role: row.title())) {
                SettingsTabRow(title: Copy.agentsIdentity(), detail: Copy.watchingIdentityDetail(), first: true) { identityPicker }
                SettingsTabRow(id: "model", title: Copy.agentsModel(), detail: Copy.agentsModelDetail()) { modelPicker }
                if let problem { ProblemLine(text: problem, size: 11).textSelection(.enabled).padding(.vertical, Tokens.Space.s8) }
            }
            SettingsGroup(id: "persona", title: Copy.agentsGroupPersona()) {
                SettingsTabRow(id: "persona-name", title: Copy.agentsPersonaName(), detail: Copy.agentsPersonaNameDetail(), first: true) {
                    CommitField(label: Copy.agentsPersonaName(), text: mine.own.persona?.name ?? "", width: settingsSelectWidth, mono: false, prompt: mine.inherited.persona?.name ?? Copy.agentsSameAsEverywhere()) {
                        await commit(persona: RolePersona(name: blankIsNil($0), prompt: mine.own.persona?.prompt))
                    }
                    .id(row.role)
                }
                SettingsStackedRow(id: "persona-prompt", title: Copy.agentsPersonaPrompt(), detail: Copy.agentsPersonaPromptDetail()) {
                    CommitEditor(label: Copy.agentsPersonaPrompt(), text: mine.own.persona?.prompt ?? "", prompt: mine.inherited.persona?.prompt ?? Copy.agentsSameAsEverywhere()) {
                        await commit(persona: RolePersona(name: mine.own.persona?.name, prompt: blankIsNil($0)))
                    }
                    .id(row.role)
                }
            }
            if mine.isOwn {
                SettingsGroup(title: "") {
                    SettingsTabRow(title: Copy.watchingResetTitle(), detail: Copy.watchingResetDetail(role: row.title()), first: true) {
                        Button { Task { problem = await save(nil).problem } } label: { Label(Copy.watchingResetTitle(), icon: .refresh) }.controlSize(.small)
                    }
                }
            }
        }
        .writingToolsBehavior(.disabled)
        // a refusal belongs to the role it happened on
        .onChange(of: row.role) { problem = nil }
        .task { await providers.load() }
    }

    /// Writes `fields` as the repo's own; nothing set at all is nothing written. false, with the reason shown, when it was refused.
    private func commit(_ fields: RoleFields) async -> Bool {
        let result = await save(fields.isEmpty ? nil : fields)
        problem = result.problem
        return result == .saved
    }

    private func commit(persona: RolePersona) async -> Bool {
        var fields = mine.own
        fields.persona = persona.name == nil && persona.prompt == nil ? nil : persona
        return await commit(fields)
    }

    private func blankIsNil(_ text: String) -> String? { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text }

    /// The profiles of the file; the first choice is the global one, which writes nothing.
    private var identityPicker: some View {
        let inherited = mine.inherited.profile
        var items = [inherited.map { Copy.watchingSameAs(profile: $0) } ?? Copy.agentsSameAsEverywhere()] + profiles
        if let own = mine.own.profile, profiles.contains(own) == false { items.append(Copy.agentsMissingProfile(profile: own)) }
        let index = Binding<Int>(
            get: { mine.own.profile.flatMap { own in profiles.firstIndex(of: own).map { $0 + 1 } ?? items.count - 1 } ?? 0 },
            set: { next in
                var fields = mine.own
                fields.profile = next == 0 ? nil : (profiles.indices.contains(next - 1) ? profiles[next - 1] : mine.own.profile)
                Task { _ = await commit(fields) }
            }
        )
        return SelectMenu(items: items, selection: index).accessibilityLabel(Copy.agentsIdentity())
    }

    /// The provider, the model and the reasoning of the role, from the one panel Agents has; what is left alone follows the global role.
    private var modelPicker: some View {
        let reply: HostProviders? = if case .reply(let reply) = providers.outcome { reply } else { nil }
        let followed = mine.inherited
        let own = mine.own
        return ModelPickerButton(
            provider: own.provider, model: own.model, effort: own.effort,
            accounts: pickerAccounts(reply, declared: accounts, icons: icons, current: [own.provider ?? followed.provider].compactMap { $0 }), catalog: catalog,
            effortFallback: (
                label: Copy.agentsSameAsEverywhere(),
                detail: followed.effort.map { Copy.watchingFollowsDetail(effort: $0) } ?? Copy.watchingFollowsNone()
            ),
            inherited: PickerInherited(provider: followed.provider, model: followed.model, effort: followed.effort, follows: Copy.watchingAgentsPage())
        ) { pick in
            var fields = own
            switch pick {
            case .account(let account, let model):
                fields.provider = account
                fields.model = model
            case .effort(let level): fields.effort = level.isEmpty ? nil : level
            case .inherit:
                fields.provider = nil
                fields.model = nil
            case .none: return
            }
            Task { _ = await commit(fields) }
        }
    }
}
