import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The Roles page of Settings (docs/specs/agents-in-settings.md), two kinds of screen, each a place of the window's history (‹ ›) as the Providers and
/// Dictation pages have: the first (whether the roles are set up, and the three roles of an epic joined by a rail) and one for each role, with its
/// Who, Persona, Skills and When it runs out of tokens groups. It reads `engine.json`, `providers.json` and the Agent Forge registry (`rolesPage`, tested
/// in `RolesPageTests`); a role's screen sends one field of one role as it changes (`editRole` and the other requests of `EngineConfigChange`: the engine writes `engine.json`,
/// and `carrier config` does when none answers, `src/config/role-edit.ts`). The page has no automated test; what its screens send is `RoleEdits.swift` (`RoleEditsTests`).
/// An extra reviewer's screen is the same as the Reviewer's with its name and type, and Remove: editable when the engine announces `extraReviewers` (`canEditExtras`), else shown only (`ExtraReviewerScreen`).
struct RolesTabView: View {
    /// Where the page is: nothing for the first screen, or the path of a role (`RoleSlot.name`).
    var place = SettingsPlace(.roles)
    var go: (SettingsPlace) -> Void = { _ in }
    /// The engine's hello lists `extraReviewers`: an extra reviewer can be added, changed and removed.
    var canEditExtras = false
    @ObservedObject private var start = StartController.shared
    @State private var page: RolesPage?
    /// why the last change was refused, in words and under the group it was made in (`who`, `persona`, `tokens`, `remove`); nothing was written
    @State var problems: [String: String] = [:]
    /// Switch automatically turned on for a role that has no first step yet: nothing is written until it has one
    @State var switchedOn: Set<RoleSlot> = []
    /// the Lead reviewer's switch is on in the page and the file has no role yet: what is chosen waits here until the role is whole
    @State var turningOnLead = false
    @State var leadDraft = LeadReviewerDraft()
    /// Add a reviewer was chosen: what is chosen waits here, as the lead's does, until the reviewer has what the engine needs to write it whole. nil on any other screen.
    @State var newReviewer: NewExtraReviewer?
    @State var confirmingRemove = false
    /// the icon of each account by the harness it runs
    @State var icons: [String: String] = [:]
    let catalog = ModelCatalog.shared
    let providers = AppHealth.providers

    private var role: RoleSlot? { place.path.first.flatMap(RoleSlot.init(name:)) }

    var body: some View {
        SettingsPageBody {
            if let page {
                if let newReviewer, place.path.first == RoleSlot.draftPlaceName {
                    let row = newReviewer.row(in: page)
                    detail(row, role: .draft, page: page.adding(row))
                } else if let role, let row = page.rows.first(where: { $0.slot == role }) {
                    if row.slot.isExtra, canEditExtras == false {
                        ExtraReviewerScreen(row: row, page: page, icons: icons, open: open)
                    } else {
                        detail(turningOnLead && role == .lead ? leadDraft.shown(in: row) : row, role: role, page: page)
                    }
                } else {
                    first(page)
                }
                ReloadNote(ReloadStatus.shared)
            } else {
                Label(Copy.engineConfigUnreadable(), icon: .warningFilled)
                    .scaledFont(12).foregroundStyle(.orange)
            }
        }
        .id(place.path.first)
        .preference(key: SettingsTitleKey.self, value: title)
        .writingToolsBehavior(.disabled)
        .onAppear(perform: load)
        // which accounts can work now is the Providers page's answer, asked again here so the picker does not offer one that was signed out
        .task { await providers.load() }
        .onChange(of: start.configExists) { load() }
        // what a screen said or was waiting for (a refusal, the lead reviewer being turned on) belongs to that screen
        .onChange(of: place) {
            problems = [:]
            turningOnLead = false
            leadDraft = LeadReviewerDraft()
            // leaving the reviewer being added drops it
            if place.path.first != RoleSlot.draftPlaceName { newReviewer = nil }
        }
        .alert(Copy.rolesRemoveAlert(name: shownRow?.title() ?? ""), isPresented: $confirmingRemove) {
            Button(Copy.rolesRemoveCancel(), role: .cancel) {}
            Button(Copy.rolesRemoveConfirm(), role: .destructive) { remove() }
        } message: {
            Text(Copy.rolesRemoveMessage())
        }
        // back from Terminal or an editor, where the config or the registry may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    /// What the toolbar says of a role's screen: its name and, under it, the model, the effort and who it works as.
    private var title: SettingsTitle? { shownRow.map { SettingsTitle(text: $0.title(), subtitle: $0.headline()) } }

    /// The role the open screen is of, as it is shown: with what is chosen for the Lead reviewer being turned on, or the reviewer being added.
    private var shownRow: RoleRow? {
        guard let page else { return nil }
        if let newReviewer, place.path.first == RoleSlot.draftPlaceName { return newReviewer.row(in: page) }
        guard let role, let row = page.rows.first(where: { $0.slot == role }) else { return nil }
        return turningOnLead && role == .lead ? leadDraft.shown(in: row) : row
    }

    func open(_ role: RoleSlot) { go(SettingsPlace(.roles, path: [role.name])) }

    private func load() {
        let providers = try? Data(contentsOf: URL(fileURLWithPath: CarrierPlaces().providers))
        problems = [:]
        icons = accountIcons(providersJSON: providers)
        page = currentConfig().flatMap { rolesPage(config: $0, providers: providers, bots: forgeBots(registry: currentForgeRegistry())) }
    }

    /// Sends the change, then reads the file back so the page shows what is there, whether it was saved or refused.
    func save(_ change: RoleChange, role: RoleSlot) async {
        await save([change], role: role)
    }

    /// Several changes of one pick are one request: the engine writes them together or not at all.
    func save(_ changes: [RoleChange], role: RoleSlot) async {
        if role == .lead, turningOnLead { await fillLead(changes) } else if role == .draft { _ = await fillNew { draft in changes.forEach { draft.apply($0) } } } else { _ = await saveDetails(role.edit(changes), group: "who") }
    }

    /// The Persona and failover groups, a name, a type and Remove send through here, then read the file back; true when it was saved.
    func saveDetails(_ change: EngineConfigChange, group: String) async -> Bool {
        let result = await saveToEngine(change)
        load()
        problems = result.problem.map { [group: $0] } ?? [:]
        return result == .saved
    }

    /// A choice for the role being turned on: kept in the draft, and sent only when identity, provider and model are all there.
    private func fillLead(_ changes: [RoleChange]) async {
        changes.forEach { leadDraft.apply($0) }
        guard leadDraft.isComplete else { return }
        let result = await saveToEngine(.leadReviewer(leadDraft))
        if result == .saved {
            turningOnLead = false
            leadDraft = LeadReviewerDraft()
        }
        load()
        problems = result.problem.map { ["who": $0] } ?? [:]
    }

    /// A choice for the reviewer being added: kept in the draft, and sent whole only when it has a name, a type, an identity, an account and a model. Once the engine has written it the person
    /// is on its own screen; when the engine refuses it (a name another reviewer has) the draft stays, with the engine's words.
    func fillNew(_ change: (inout NewExtraReviewer) -> Void) async -> Bool {
        guard var next = newReviewer else { return true }
        change(&next)
        newReviewer = next
        guard let request = next.request else { return true }
        let result = await saveToEngine(.addExtraReviewer(request))
        load()
        problems = result.problem.map { ["who": $0] } ?? [:]
        if result == .saved {
            // the engine gave it its key; its name is unique among the reviewers
            let added = page?.rows.first { $0.name == request.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            newReviewer = nil
            go(added.map { SettingsPlace(.roles, path: [$0.slot.name]) } ?? SettingsPlace(.roles))
        }
        return result == .saved
    }

    private func setLeadSwitch(on: Bool, row: RoleRow) {
        leadDraft = LeadReviewerDraft()
        problems = [:]
        if on {
            turningOnLead = true
        } else if row.off {
            turningOnLead = false
        } else {
            turningOnLead = false
            Task { _ = await saveDetails(.leadReviewer(nil), group: "who") }
        }
    }

    /// Remove, once the alert said what it does: the other reviewers stay as they were and the window goes back to Roles.
    private func remove() {
        guard let change = role?.removal else { return }
        Task { if await saveDetails(change, group: "remove") { go(SettingsPlace(.roles)) } }
    }

    /// Add a reviewer: the screen of a reviewer that is not in the file yet.
    private func add() {
        newReviewer = NewExtraReviewer()
        problems = [:]
        go(SettingsPlace(.roles, path: [RoleSlot.draftPlaceName]))
    }

    /// The first screen: whether the roles are set up, the roles of an epic and Add a reviewer.
    @ViewBuilder private func first(_ page: RolesPage) -> some View {
        let readiness = rolesReadiness(page)
        let offer = ExtraReviewerOffer(canEdit: canEditExtras, page: page)
        SettingsGroup(title: "") { RolesStatusCard(readiness: readiness, open: open) }
        SettingsGroup(id: EpicRail.groupID, title: EpicRail.group, footer: page.rows.contains { $0.slot.isExtra } ? Copy.rolesRailFoot() : nil) {
            EpicRail(page: page, readiness: readiness, icons: icons, open: open)
            // only an engine that announces `extraReviewers` can write one
            if offer.showsAdd {
                SettingsTabRow(title: Copy.rolesAddReviewer(), detail: offer.addDetail()) {
                    Button(action: add) { Label(Copy.rolesAddReviewer(), icon: .plus) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(offer.canAdd == false)
                }
            }
        }
    }

    private func detail(_ row: RoleRow, role: RoleSlot, page: RolesPage) -> some View {
        // a Group and not a stack: the groups below are sections of the page's form
        Group {
            if row.hasSwitch {
                SettingsGroup(title: "", footer: turningOnLead ? leadDraft.hint() : nil) {
                    SettingsTabRow(id: "use-a-lead-reviewer", title: Copy.rolesUseLead(), detail: row.switchDetail(), first: true) {
                        Toggle(Copy.rolesUseLead(), isOn: Binding(get: { row.usable(turningOn: turningOnLead) }, set: { setLeadSwitch(on: $0, row: row) }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            SettingsGroup(title: "") {
                RoleHero(row: row, page: page, icons: icons)
                RoleFlowStrip(current: row.slot, rows: page.rows, open: open)
            }
            Group {
                who(row, role: role, page: page)
                // the reviewer being added has no persona, steps or skills until the engine has written it
                if role != .draft {
                    persona(row, role: role)
                    skills(row)
                    tokens(row, role: role, page: page)
                    if row.slot.isExtra { removal(row) }
                }
            }
            // while the lead reviewer is off the rest of its page is shown, dimmed and not usable
            .opacity(row.usable(turningOn: turningOnLead) ? 1 : 0.4).disabled(row.usable(turningOn: turningOnLead) == false)
        }
    }
}

/// The skill of a stage as a value that is not editable yet: its name in the box of a field, with "Default" before it.
struct SkillValue: View {
    let skill: String
    var chip = Copy.rolesDefault()

    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            StatusChip(text: chip, tint: .secondary)
            Text(skill).scaledFont(11.5, design: .monospaced).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s5).frame(width: 150, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.rolesSkill())
        .accessibilityValue(Copy.rolesSkillValue(skill: skill))
    }
}
