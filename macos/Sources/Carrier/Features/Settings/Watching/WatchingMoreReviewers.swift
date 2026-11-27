import CarrierCore
import CarrierUI
import SwiftUI

/// What a repo's screen needs to change its extra reviewers; none while the engine does not announce `extraReviewers`, and the group is then only shown.
struct ExtrasEditor {
    /// the repo's own map, as the file has it
    let own: [RepoExtraReviewer]
    /// the map of Roles, which Own list starts as a copy of
    let roles: [RepoExtraReviewer]
    let profiles: [String]
    let accounts: [String]
    /// Sends the request and reads the file again, so what is shown is what the engine left; the reason is in the result when it refused.
    let save: (EngineConfigChange) async -> RoleSave
    /// Sends the repo's list as `change` makes it from the list the file has when this request's turn comes, after the edits made before it: a second edit made fast does not start from the screen's older
    /// copy. nil when `change` gives no list (a name another entry has, a draft that is not whole) and nothing was sent.
    let edit: (@escaping @MainActor (RepoOwnList) -> RepoOwnList?) async -> RoleSave?
}

/// More reviewers here (spec "Watching"): the choice of Same as everywhere, Own list or None, each written by the engine as it is chosen (`setRepoExtraReviewers`), and with Own list a group for each
/// entry (name, type, identity, model and effort, and Remove) and Add a reviewer while there are fewer than three. What each change sends is `RepoOwnList`: the whole map every time. A reviewer being
/// added waits as a draft, with what it still needs, and is sent whole once it has all of it. An Own list that would start empty (Roles has no extra reviewer) writes nothing until its first entry.
struct RepoMoreReviewers: View {
    let repo: String
    /// what the file says: no key, a map or `{}`
    let extras: RepoExtraReviewers
    /// the ones that run in the repo, for the read-only group and the two states that are not an own list
    let reviewers: [RoleRow]
    let page: RolesPage
    let icons: [String: String]
    let editor: ExtrasEditor?
    @State private var problem: String?
    @State private var draft: RepoExtraReviewer?
    /// the entry whose Remove was pressed, and the state chosen while the own list has entries: each asks first
    @State private var removing: RepoExtraReviewer?
    @State private var leaving: RepoExtraReviewers?
    /// Own list was chosen while Roles has no reviewer to copy: nothing is in the file yet
    @State private var starting = false
    private let catalog = ModelCatalog.shared
    private let providers = AppHealth.providers

    /// What the screen shows: the file's state, or Own list while it waits for its first entry.
    private var shown: RepoExtraReviewers { starting && extras != .ownList ? .ownList : extras }

    var body: some View {
        Group {
            SettingsGroup(
                id: "more-reviewers-here", title: Copy.watchingGroupMore(), footer: shown.footer(editable: editor != nil),
                accessory: { if editor == nil { StatusChip(text: extras.title(), tint: .secondary) } }
            ) {
                if let editor {
                    SettingsTabRow(title: Copy.watchingMoreChoiceTitle(), detail: Copy.watchingMoreChoiceDetail(), first: true) {
                        ChoicePopUp(
                            label: Copy.watchingGroupMore(), options: RepoExtraReviewers.allCases.map { ($0, $0.title()) },
                            selection: Binding(get: { shown }, set: { choose($0, editor) })
                        )
                    }
                }
                if shown == .ownList, let editor {
                    if editor.own.isEmpty { SettingsTabRow(title: Copy.watchingOwnEmpty(), detail: "") { EmptyView() } }
                    if draft == nil {
                        let offer = ExtraReviewerOffer(canEdit: true, count: editor.own.count)
                        SettingsTabRow(title: Copy.rolesAddReviewer(), detail: offer.addDetail()) {
                            Button { draft = .draft } label: { Label(Copy.rolesAddReviewer(), icon: .plus) }
                                .controlSize(.small).disabled(offer.canAdd == false)
                        }
                    }
                } else {
                    ForEach(Array(reviewers.enumerated()), id: \.element.id) { index, reviewer in
                        SettingsTabRow(
                            title: reviewer.title(), detail: reviewer.headline(), first: index == 0 && editor == nil, leading: AnyView(roleAvatar(reviewer, page: page, icons: icons, size: 30))
                        ) {
                            HStack(spacing: Tokens.Space.s4) {
                                if let type = reviewer.type { StatusChip(text: Copy.rolesExtraType(type: type), tint: .secondary) }
                                if extras == .sameAsEverywhere { StatusChip(text: Copy.watchingMoreFromRoles(), tint: .secondary) }
                            }
                        }
                    }
                    if reviewers.isEmpty {
                        SettingsTabRow(title: extras == .noExtras ? Copy.watchingMoreOnlyReviewer() : Copy.watchingMoreNoneInRoles(), detail: "", first: editor == nil) { EmptyView() }
                    }
                }
                if let problem { ProblemLine(text: problem, size: 11).textSelection(.enabled).padding(.vertical, Tokens.Space.s8) }
            }
            if shown == .ownList, let editor {
                ForEach(editor.own) { entry in entryGroup(entry, editor: editor) }
                if let draft { draftGroup(draft, editor: editor) }
            }
        }
        .id(repo)
        .onChange(of: extras) { starting = false }
        .task { await providers.load() }
        .alert(Copy.rolesRemoveAlert(name: removing.map(name) ?? ""), isPresented: Binding(get: { removing != nil }, set: { if $0 == false { removing = nil } }), presenting: removing) { entry in
            Button(Copy.rolesRemoveCancel(), role: .cancel) {}
            Button(Copy.rolesRemoveConfirm(), role: .destructive) { if let editor { remove(entry.key, editor: editor) } }
        } message: { _ in
            Text(Copy.watchingOwnRemoveDetail() + (editor?.own.count == 1 ? " " + Copy.watchingOwnRemoveLast() : ""))
        }
        .alert(Copy.watchingOwnDropAlert(), isPresented: Binding(get: { leaving != nil }, set: { if $0 == false { leaving = nil } }), presenting: leaving) { state in
            Button(Copy.rolesRemoveCancel(), role: .cancel) {}
            Button(Copy.watchingOwnDropConfirm(), role: .destructive) { if let editor { choose(state, editor, confirmed: true) } }
        } message: { _ in
            Text(Copy.watchingOwnDropMessage())
        }
    }

    /// An entry's name, "New reviewer" while it has none.
    private func name(_ entry: RepoExtraReviewer) -> String { entry.name.isEmpty ? Copy.rolesNewReviewer() : entry.name }

    // MARK: the choice

    /// Leaving an own list that has entries takes them out of the file, so it asks first (`confirmed`); the other choices write at once.
    private func choose(_ state: RepoExtraReviewers, _ editor: ExtrasEditor, confirmed: Bool = false) {
        if shown == .ownList, state != .ownList, editor.own.isEmpty == false, confirmed == false {
            leaving = state
            return
        }
        draft = nil
        problem = nil
        guard let change = state.choosing(repo: repo, roles: editor.roles) else {
            starting = true
            return
        }
        starting = false
        Task { problem = await editor.save(change).problem }
    }

    // MARK: an entry

    private func entryGroup(_ entry: RepoExtraReviewer, editor: ExtrasEditor) -> some View {
        SettingsGroup(title: name(entry)) {
            fields(
                name: entry.name, type: entry.type, profile: entry.profile, provider: entry.provider, model: entry.model, effort: entry.effort, editor: editor,
                edit: { await apply($0, to: entry.key, editor: editor) }
            )
            SettingsTabRow(title: Copy.watchingOwnRemoveTitle(name: name(entry)), detail: Copy.watchingOwnRemoveDetail()) {
                Button(role: .destructive) { removing = entry } label: { Label(Copy.watchingOwnRemoveButton(), icon: .trash) }.controlSize(.small)
            }
        }
        .id(entry.key)
    }

    private func draftGroup(_ draft: RepoExtraReviewer, editor: ExtrasEditor) -> some View {
        SettingsGroup(title: Copy.rolesNewReviewer(), footer: RepoOwnList(editor.own).hint(for: draft)) {
            fields(
                name: draft.name, type: draft.type, profile: draft.profile, provider: draft.provider, model: draft.model, effort: draft.effort, editor: editor,
                edit: { await fill($0, editor: editor) }
            )
            SettingsTabRow(title: Copy.watchingOwnDiscard(), detail: Copy.watchingOwnDiscardDetail()) {
                Button { self.draft = nil } label: { Text(Copy.watchingOwnDiscard()) }.controlSize(.small)
            }
        }
    }

    /// The five fields of an entry, the draft's as well; each reports the change it makes and says whether it went through (a text that was refused goes back).
    private func fields(
        name: String, type: String, profile: String, provider: String, model: String, effort: String?, editor: ExtrasEditor, edit: @escaping (RepoReviewerEdit) async -> Bool
    ) -> some View {
        Group {
            SettingsTabRow(title: Copy.rolesExtraNameTitle(), detail: Copy.rolesExtraNameDetail(), first: true) {
                CommitField(label: Copy.rolesExtraNameTitle(), text: name, width: settingsSelectWidth, mono: false, prompt: Copy.rolesNewReviewer()) { await edit(.name($0)) }
            }
            SettingsTabRow(title: Copy.rolesExtraTypeTitle(), detail: Copy.rolesExtraTypeDetail()) {
                CommitField(label: Copy.rolesExtraTypeTitle(), text: type, width: settingsSelectWidth, mono: true) { await edit(.type($0)) }
            }
            SettingsTabRow(title: Copy.rolesIdentity(), detail: Copy.watchingIdentityDetail()) { identityMenu(profile, profiles: editor.profiles, edit: edit) }
            SettingsTabRow(title: Copy.rolesModel(), detail: Copy.rolesModelDetail()) { modelPicker(provider: provider, model: model, effort: effort, accounts: editor.accounts, edit: edit) }
        }
    }

    /// The profiles of the file; one the entry has that the file does not, or none yet, is the first item and picking it again changes nothing.
    private func identityMenu(_ profile: String, profiles: [String], edit: @escaping (RepoReviewerEdit) async -> Bool) -> some View {
        let known = profiles.contains(profile)
        let lead = known ? [] : [profile.isEmpty ? Copy.rolesNotSet() : Copy.rolesMissingProfile(profile: profile)]
        let index = Binding<Int>(
            get: { known ? (profiles.firstIndex(of: profile) ?? 0) + lead.count : 0 },
            set: { next in
                guard next >= lead.count else { return }
                Task { _ = await edit(.profile(profiles[next - lead.count])) }
            }
        )
        return SelectMenu(items: lead + profiles, selection: index).accessibilityLabel(Copy.rolesIdentity())
    }

    private func modelPicker(provider: String, model: String, effort: String?, accounts: [String], edit: @escaping (RepoReviewerEdit) async -> Bool) -> some View {
        let reply: HostProviders? = if case .reply(let reply) = providers.outcome { reply } else { nil }
        return ModelPickerButton(
            provider: provider.isEmpty ? nil : provider, model: model.isEmpty ? nil : model, effort: effort,
            accounts: pickerAccounts(reply, declared: accounts, icons: icons, current: [provider]), catalog: catalog
        ) { pick in
            switch pick {
            case .account(let account, let chosen):
                if account != provider || chosen != nil { Task { _ = await edit(.account(provider: account, model: chosen)) } }
            case .effort(let level): Task { _ = await edit(.effort(level.isEmpty ? nil : level)) }
            case .none, .inherit: break
            }
        }
    }

    // MARK: what a change sends

    /// An entry's field: the whole map goes out with it, built when the request's turn comes. A name another entry has is not sent.
    private func apply(_ edit: RepoReviewerEdit, to key: String, editor: ExtrasEditor) async -> Bool {
        guard let result = await editor.edit({ $0.applying(edit, to: key) }) else {
            if case .name(let name) = edit { problem = Copy.watchingOwnNameTaken(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return false
        }
        problem = result.problem
        return result == .saved
    }

    /// A choice for the reviewer being added: kept in the draft, and sent only when it is whole.
    private func fill(_ edit: RepoReviewerEdit, editor: ExtrasEditor) async -> Bool {
        guard let current = draft else { return true }
        let next = current.applying(edit)
        draft = next
        guard let result = await editor.edit({ $0.adding(next) }) else { return true }
        problem = result.problem
        if result == .saved { draft = nil }
        return result == .saved
    }

    private func remove(_ key: String, editor: ExtrasEditor) {
        Task { if let result = await editor.edit({ $0.removing(key) }) { problem = result.problem } }
    }
}
