import CarrierCore
import CarrierUI
import SwiftUI

/// An extra reviewer's screen (`agents.extraReviewers`), read only: the engine that is running does not announce `extraReviewers` (the requests that write one), so every field is shown as a value.
/// With the capability the Roles page draws it as it draws the Reviewer's, editable (`RolesTab+Groups.swift`).
/// It is the Reviewer's screen with its three differences: the failover steps and the skills say "Same as Reviewer" when the entry has none of its own.
struct ExtraReviewerScreen: View {
    let row: RoleRow
    let page: RolesPage
    let icons: [String: String]
    let open: (RoleSlot) -> Void

    var body: some View {
        Group {
            SettingsGroup(title: "") {
                RoleHero(row: row, page: page, icons: icons)
                RoleFlowStrip(current: row.slot, rows: page.rows, open: open)
            }
            SettingsGroup(title: Copy.rolesGroupWho(), footer: Copy.rolesExtraReadOnly()) {
                SettingsTabRow(title: Copy.rolesIdentity(), detail: row.identityDetail(), first: true) { value(row.fields.profile) }
                SettingsTabRow(title: Copy.rolesModel(), detail: row.providerMissing ? Copy.rolesModelNotAccount() : Copy.rolesModelDetail()) {
                    value([row.fields.provider, row.fields.model, row.fields.effort].compactMap { $0 }.joined(separator: " \u{00b7} "))
                }
            }
            SettingsGroup(title: Copy.rolesGroupPersona()) {
                SettingsTabRow(title: Copy.rolesPersonaName(), detail: Copy.rolesPersonaNameDetail(), first: true) { value(row.fields.persona?.name) }
                SettingsStackedRow(title: Copy.rolesPersonaPrompt(), detail: Copy.rolesPersonaPromptDetail()) {
                    Text(row.fields.persona?.prompt ?? Copy.rolesNone()).scaledFont(13).foregroundStyle(.secondary)
                        .lineLimit(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SettingsGroup(title: Copy.rolesGroupTokens()) { steps }
            SettingsGroup(title: Copy.rolesGroupSkills(), footer: Copy.rolesSkillsFooter()) {
                ForEach(row.slot.stages()) { stage in
                    SettingsTabRow(
                        title: stage.title, detail: stage.detail,
                        note: Copy.rolesRunsAs(invocation: skillInvocation(stage.skill, icon: row.fields.provider.flatMap { icons[$0] }))
                    ) {
                        SkillValue(skill: stage.skill, chip: Copy.rolesSameAsReviewer())
                    }
                }
            }
        }
    }

    /// Its own steps, or the Reviewer's with the words that say they are the Reviewer's.
    @ViewBuilder private var steps: some View {
        if row.ownSteps {
            if row.steps.isEmpty {
                SettingsTabRow(title: Copy.rolesSwitch(), detail: Copy.rolesSwitchDetail(), first: true) { value(Copy.rolesNone()) }
            }
            ForEach(Array(row.steps.enumerated()), id: \.offset) { index, step in
                SettingsTabRow(title: index == 0 ? Copy.rolesTryFirst() : Copy.rolesThenTry(), detail: Copy.rolesTryFirstDetail(), first: index == 0) { value(step.text) }
            }
        } else {
            let reviewerSteps = row.steps.isEmpty ? Copy.rolesNone() : row.steps.map(\.text).joined(separator: ", ")
            SettingsTabRow(title: Copy.rolesStepsTitle(), detail: Copy.rolesTakesReviewerSteps(steps: reviewerSteps), first: true) {
                StatusChip(text: Copy.rolesSameAsReviewer(), tint: .secondary)
            }
        }
    }

    /// A value that cannot be changed: quiet text at the end of the row, "None" when there is nothing to show.
    private func value(_ text: String?) -> some View {
        Text(text.flatMap { $0.isEmpty ? nil : $0 } ?? Copy.rolesNone()).scaledFont(12).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.middle).textSelection(.enabled).frame(maxWidth: 260, alignment: .trailing)
    }
}
