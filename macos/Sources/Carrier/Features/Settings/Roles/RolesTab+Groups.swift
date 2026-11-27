import CarrierCore
import CarrierUI
import SwiftUI

// The groups of a role's screen (Who, Persona, Skills, When it runs out of tokens and, for an extra reviewer, Remove), which RolesTab.swift puts together. Every field of one sends its own request
// as it changes (`RoleEdits.swift`), an extra reviewer's pointing at it by its key; a refusal is shown under its group.

extension RolesTabView {
    /// The words of a refusal, under the group it came from.
    @ViewBuilder func refusal(_ group: String) -> some View {
        if let text = problems[group] { ProblemLine(text: text, size: 11).textSelection(.enabled).padding(.vertical, Tokens.Space.s8) }
    }

    /// Who signs and, for an extra reviewer, what it is called and what it looks at; then its model.
    func who(_ row: RoleRow, role: RoleSlot, page: RolesPage) -> some View {
        SettingsGroup(id: "who", title: Copy.rolesGroupWho(), footer: newReviewer?.hint() ?? identityFooter(row, page: page)) {
            if row.slot.isExtra {
                SettingsTabRow(title: Copy.rolesExtraNameTitle(), detail: Copy.rolesExtraNameDetail(), first: true) {
                    CommitField(label: Copy.rolesExtraNameTitle(), text: row.name ?? "", width: settingsSelectWidth, mono: false, prompt: Copy.rolesNewReviewer()) { await rename(role, to: $0) }
                        .id(row.id)
                }
                SettingsTabRow(title: Copy.rolesExtraTypeTitle(), detail: Copy.rolesExtraTypeDetail()) {
                    CommitField(label: Copy.rolesExtraTypeTitle(), text: row.type ?? "", width: settingsSelectWidth, mono: true) { await retype(role, to: $0) }
                        .id(row.id)
                }
            }
            SettingsTabRow(id: "identity", title: Copy.rolesIdentity(), detail: row.identityDetail(), first: row.slot.isExtra == false) {
                HStack(spacing: Tokens.Space.s8) {
                    identityPicker(row, role: role, page: page)
                    openIdentity(row)
                }
            }
            SettingsTabRow(id: "model", title: Copy.rolesModel(), detail: row.providerMissing ? Copy.rolesModelNotAccount() : Copy.rolesModelDetail()) {
                ModelPickerButton(
                    provider: row.fields.provider, model: row.fields.model, effort: row.fields.effort,
                    accounts: pickerAccounts(page: page, current: [row.fields.provider]), catalog: catalog
                ) { pick in
                    switch pick {
                    case .account(let account, let model):
                        // the model belongs to the account's provider: written together, in one save
                        let changes = (account != row.fields.provider ? [RoleChange.provider(account)] : []) + (model.map { [RoleChange.model($0)] } ?? [])
                        if changes.isEmpty == false { Task { await save(changes, role: role) } }
                    case .effort(let level): Task { await save(.effort(level.isEmpty ? nil : level), role: role) }
                    case .none, .inherit: break
                    }
                }
            }
            refusal("who")
        }
    }

    /// A name or a type: kept in the draft of a reviewer being added, else sent pointing at the reviewer by its key. false puts the text back.
    private func rename(_ role: RoleSlot, to name: String) async -> Bool {
        if role == .draft { return await fillNew { $0.name = name } }
        guard let change = role.renamed(name) else { return false }
        return await saveDetails(change, group: "who")
    }

    private func retype(_ role: RoleSlot, to type: String) async -> Bool {
        if role == .draft { return await fillNew { $0.type = type } }
        guard let change = role.retyped(type) else { return false }
        return await saveDetails(change, group: "who")
    }

    func persona(_ row: RoleRow, role: RoleSlot) -> some View {
        SettingsGroup(id: "persona", title: Copy.rolesGroupPersona()) {
            SettingsTabRow(id: "persona-name", title: Copy.rolesPersonaName(), detail: Copy.rolesPersonaNameDetail(), first: true) {
                CommitField(label: Copy.rolesPersonaName(), text: row.fields.persona?.name ?? "", width: settingsSelectWidth, mono: false, prompt: Copy.rolesNone()) {
                    await saveDetails(role.persona(name: blankIsNil($0), prompt: row.fields.persona?.prompt), group: "persona")
                }
                .id(row.id)
            }
            SettingsStackedRow(id: "persona-prompt", title: Copy.rolesPersonaPrompt(), detail: Copy.rolesPersonaPromptDetail()) {
                CommitEditor(label: Copy.rolesPersonaPrompt(), text: row.fields.persona?.prompt ?? "", prompt: Copy.rolesNone()) {
                    await saveDetails(role.persona(name: row.fields.persona?.name, prompt: blankIsNil($0)), group: "persona")
                }
                .id(row.id)
            }
            refusal("persona")
        }
    }

    /// What the engine runs in each stage of the role, as the engine has it today: shown and not changeable yet (a later version of the engine reads
    /// it from the config). `RolesReadinessTests` keeps `RoleSlot.stages` equal to what `src/prompts` invokes. An extra reviewer runs the Reviewer's.
    func skills(_ row: RoleRow) -> some View {
        SettingsGroup(id: "skills", title: Copy.rolesGroupSkills(), footer: Copy.rolesSkillsFooter()) {
            ForEach(row.slot.stages()) { stage in
                SettingsTabRow(
                    id: stage.id, title: stage.title, detail: stage.detail,
                    note: Copy.rolesRunsAs(invocation: skillInvocation(stage.skill, icon: row.fields.provider.flatMap { icons[$0] }))
                ) {
                    SkillValue(skill: stage.skill, chip: row.slot.isExtra ? Copy.rolesSameAsReviewer() : Copy.rolesDefault())
                }
            }
        }
    }

    func tokens(_ row: RoleRow, role: RoleSlot, page: RolesPage) -> some View {
        SettingsGroup(id: "when-it-runs-out-of-tokens", title: Copy.rolesGroupTokens()) {
            // the lead or an extra reviewer with no steps of its own runs the Reviewer's, which this screen shows as such; its own steps are what it declares
            let own = row.ownSteps ? row.steps : []
            let inherits = row.ownSteps == false && switchedOn.contains(role) == false
            let on = own.isEmpty == false || switchedOn.contains(role)
            if row.ownSteps == false {
                // "Same as Reviewer" on: no steps of its own; off: the steps below, and the first one written gives it its own
                SettingsTabRow(title: Copy.rolesSameAsReviewer(), detail: Copy.rolesTakesReviewerSteps(steps: row.steps.isEmpty ? Copy.rolesNone() : row.steps.map(\.text).joined(separator: ", ")), first: true) {
                    Toggle(Copy.rolesSameAsReviewer(), isOn: Binding(get: { inherits }, set: { now in
                        if now { switchedOn.remove(role) } else { switchedOn.insert(role) }
                    })).labelsHidden().toggleStyle(.switch)
                }
            } else {
                SettingsTabRow(id: "switch-automatically", title: Copy.rolesSwitch(), detail: Copy.rolesSwitchDetail(), first: true) {
                    Toggle(Copy.rolesSwitch(), isOn: Binding(get: { on }, set: { now in
                        if now { switchedOn.insert(role) } else {
                            switchedOn.remove(role)
                            Task { _ = await saveDetails(role.failover(first: nil, second: nil), group: "tokens") }
                        }
                    })).labelsHidden().toggleStyle(.switch)
                }
            }
            if on {
                stepRow(Copy.rolesTryFirst(), detail: Copy.rolesTryFirstDetail(), step: own.first, own: own, role: role, page: page, index: 0)
                stepRow(Copy.rolesThenTry(), detail: Copy.rolesOptional(), step: own.dropFirst().first, own: own, role: role, page: page, index: 1)
            }
            if own.count > 2 {
                Text(Copy.rolesMoreSteps(count: own.count - 2))
                    .scaledFont(11).foregroundStyle(.secondary).padding(.vertical, Tokens.Space.s8)
            }
            refusal("tokens")
        }
    }

    /// Remove <name>, the last row of an extra reviewer's screen: it asks first (the alert of `RolesTabView`), says running epics keep it, and takes out the entry and nothing else.
    func removal(_ row: RoleRow) -> some View {
        SettingsGroup(title: "") {
            SettingsTabRow(title: Copy.rolesRemoveTitle(name: row.title()), detail: Copy.rolesRemoveDetail(), first: true) {
                Button(role: .destructive) { confirmingRemove = true } label: { Label(Copy.rolesRemoveButton(), icon: .trash) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
            refusal("remove")
        }
    }

    /// What is said under Identity where the person chooses it, not only on the first screen: that Author and Reviewer sign as one account, and why the
    /// list of bots is empty (no registry, or one that does not read).
    private func identityFooter(_ row: RoleRow, page: RolesPage) -> String? {
        let shared = row.slot == .lead || row.slot.isExtra ? nil : page.sharedNote
        let lines = [shared, page.bots.note].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func blankIsNil(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// A step of the role's failover: a provider and, optionally, a model. Then can be taken back to None; First needs a provider before anything is written.
    private func stepRow(_ title: String, detail: String, step: FailoverStep?, own steps: [FailoverStep], role: RoleSlot, page: RolesPage, index: Int) -> some View {
        func write(_ own: FailoverStep?) {
            let first = index == 0 ? own : steps.first
            let second = index == 1 ? own : steps.dropFirst().first
            Task { _ = await saveDetails(role.failover(first: first, second: second), group: "tokens") }
        }
        return SettingsTabRow(title: title, detail: detail) {
            ModelPickerButton(
                provider: step?.provider, model: step?.model, effort: step?.effort, accounts: pickerAccounts(page: page, current: [step?.provider]), catalog: catalog,
                effortFallback: (label: Copy.rolesAsTheRole(), detail: Copy.rolesAsTheRoleDetail()), allowsDefaultModel: true, noneTitle: index == 1 ? Copy.rolesNoSecondStep() : nil, placeholder: index == 0 ? Copy.rolesChoose() : Copy.rolesNone()
            ) { pick in
                switch pick {
                case .account(let account, let model): write(FailoverStep(provider: account, model: model, effort: step?.effort))
                case .none: write(nil)
                case .inherit: break
                case .effort(let level):
                    // a level goes with a provider: with none yet there is nothing to write it on
                    if let step { write(FailoverStep(provider: step.provider, model: step.model, effort: level.isEmpty ? nil : level)) }
                }
            }
        }
    }

    /// The accounts the picker offers: the ones that can work now, and the one the role already names.
    private func pickerAccounts(page: RolesPage, current: [String?]) -> [PickerAccount] {
        let reply: HostProviders? = if case .reply(let reply) = providers.outcome { reply } else { nil }
        return CarrierCore.pickerAccounts(reply, declared: page.accounts, icons: icons, current: current.compactMap { $0 })
    }

    /// The chevron of the Identity row: the identity's own screen, where it can sign and which roles sign as it; none while the role has no identity the registry knows.
    @ViewBuilder private func openIdentity(_ row: RoleRow) -> some View {
        if let key = row.identity.key {
            Button { go(SettingsPlace(.identities, path: [key])) } label: { Glyph(.chevronRight, size: 13, bold: true) }
                .buttonStyle(HoverTextButtonStyle(tint: nil)).accessibilityLabel(Copy.identitiesOpenIdentity()).help(Copy.identitiesOpenIdentity())
        }
    }

    /// The bots of the registry and the person's own login; a profile that is no longer there stays, marked, and picking it again is a no-op.
    private func identityPicker(_ row: RoleRow, role: RoleSlot, page: RolesPage) -> some View {
        let current: String
        switch row.identity {
        case .forge(let bot): current = "bot:" + bot
        case .gh: current = "gh"
        case .missing, .unset: current = "keep"
        }
        var values: [String] = [], items: [String] = []
        if current == "keep" {
            values.append("keep")
            items.append(row.fields.profile.map { Copy.rolesMissingProfile(profile: $0) } ?? Copy.rolesNotSet())
        }
        values += page.bots.names.map { "bot:" + $0 }
        items += page.bots.names
        values.append("gh")
        items.append(Copy.rolesIdentityGh())
        let index = Binding<Int>(
            get: { values.firstIndex(of: current) ?? 0 },
            set: { next in
                let choice = values[next]
                if choice == "gh" { Task { await save(.gh, role: role) } }
                else if choice.hasPrefix("bot:") { Task { await save(.bot(String(choice.dropFirst(4))), role: role) } }
            }
        )
        return SelectMenu(items: items, selection: index).accessibilityLabel(Copy.rolesIdentity())
    }
}
