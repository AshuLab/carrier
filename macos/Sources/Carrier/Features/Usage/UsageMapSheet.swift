import CarrierCore
import CarrierUI
import SwiftUI

/// `Unpriced · Map`: prices a model as `$0.00` local, as a catalog model, or with rates of its own; `Clear` goes back to the table. The form is
/// checked by `UsageOverrideDraft` before the host is asked, and what was typed stays when the host refuses.
struct MapSheet: View {
    let row: UsageModelRow
    let catalog: [String]
    let store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UsageOverrideDraft
    @State private var attempted = false
    @State private var saving = false
    @State private var refusal: String?

    init(row: UsageModelRow, catalog: [String], store: UsageStore) {
        self.row = row
        self.catalog = catalog
        self.store = store
        _draft = State(initialValue: UsageOverrideDraft(mode: catalog.isEmpty ? .custom : .alias))
    }

    private var errors: [UsageOverrideDraft.Field: String] { attempted ? draft.check(model: row.model, catalog: catalog).errors : [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s14) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(Copy.usageMapTitle(model: row.model)).scaledFont(15, weight: .semibold).lineLimit(1).truncationMode(.middle)
                Text(Copy.usageMapLine()).scaledFont(12).foregroundStyle(.secondary)
            }
            Picker(Copy.usageMapPrice(), selection: $draft.mode) {
                Text(Copy.usageMapLocal()).tag(UsageOverrideDraft.Mode.local)
                Text(Copy.usageMapCatalog()).tag(UsageOverrideDraft.Mode.alias)
                Text(Copy.usageMapCustom()).tag(UsageOverrideDraft.Mode.custom)
                if row.overridden { Text(Copy.usageMapClear()).tag(UsageOverrideDraft.Mode.clear) }
            }
            .pickerStyle(.segmented).labelsHidden()
            fields
            if let refusal { ProblemLine(text: refusal) }
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(Copy.usageMapCancel()) { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction).disabled(saving)
                Button(Copy.usageMapSave()) { Task { await save() } }.buttonStyle(PrimaryCapsuleButtonStyle()).keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(Tokens.Space.s20).frame(width: 480)
        .onChange(of: draft) { refusal = nil }
    }

    @ViewBuilder private var fields: some View {
        switch draft.mode {
        case .local:
            Text(Copy.usageMapLocalDetail()).scaledFont(12).foregroundStyle(.secondary)
        case .clear:
            Text(Copy.usageMapClearDetail()).scaledFont(12).foregroundStyle(.secondary)
        case .alias:
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(Copy.usageMapAliasLead()).scaledFont(12).foregroundStyle(.secondary)
                ChoicePopUp(label: Copy.usageMapCatalog(), options: [("", Copy.usageErrorChoose())] + catalog.map { ($0, $0) }, selection: $draft.alias)
                problem(errors[.alias])
            }
        case .custom:
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                Text(Copy.usageMapPerMillion()).scaledFont(12).foregroundStyle(.secondary)
                rate(Copy.usageMapInput(), Copy.usageMapRequired(), $draft.input, .input)
                rate(Copy.usageMapCachedRead(), Copy.usageMapOptional(), $draft.cachedInput, .cachedInput)
                rate(Copy.usageMapCacheWrite(), Copy.usageMapOptional(), $draft.cacheWrite, .cacheWrite)
                rate(Copy.usageMapOutput(), Copy.usageMapRequired(), $draft.output, .output)
            }
        }
    }

    private func rate(_ title: String, _ hint: String, _ text: Binding<String>, _ field: UsageOverrideDraft.Field) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack {
                Text(title).frame(width: 110, alignment: .leading)
                TextField(hint, text: text).settingsField(width: 120).environment(\.settingsInvalid, errors[field] != nil)
                    .accessibilityLabel(Copy.usageMapRateLabel(rate: title))
            }
            problem(errors[field]).padding(.leading, Tokens.Space.s110)
        }
    }

    @ViewBuilder private func problem(_ text: String?) -> some View {
        if let text { ProblemLine(text: text, size: 11) }
    }

    private func save() async {
        attempted = true
        guard let override = draft.check(model: row.model, catalog: catalog).override else { return }
        saving = true
        refusal = await store.override(override)
        saving = false
        if refusal == nil { dismiss() }
    }
}
