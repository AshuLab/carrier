import CarrierCore
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Price for \(row.model)").font(.scaled(15).weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text("The cost on this page follows what you set here. Nothing is guessed.").font(.scaled(12)).foregroundStyle(.secondary)
            }
            Picker("Price", selection: $draft.mode) {
                Text("$0.00 local").tag(UsageOverrideDraft.Mode.local)
                Text("Catalog model").tag(UsageOverrideDraft.Mode.alias)
                Text("Custom rates").tag(UsageOverrideDraft.Mode.custom)
                if row.overridden { Text("Clear").tag(UsageOverrideDraft.Mode.clear) }
            }
            .pickerStyle(.segmented).labelsHidden()
            fields
            if let refusal { ProblemLine(text: refusal) }
            HStack {
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save") { Task { await save() } }.buttonStyle(PrimaryCapsuleButtonStyle()).keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(20).frame(width: 480)
        .onChange(of: draft) { refusal = nil }
    }

    @ViewBuilder private var fields: some View {
        switch draft.mode {
        case .local:
            Text("Counts every token of this model as free, like a model running on your Mac.").font(.scaled(12)).foregroundStyle(.secondary)
        case .clear:
            Text("Goes back to the price table. If the model is not in it, it shows as unpriced again.").font(.scaled(12)).foregroundStyle(.secondary)
        case .alias:
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses the rates of").font(.scaled(12)).foregroundStyle(.secondary)
                ChoicePopUp(label: "Catalog model", options: [("", "Choose a model")] + catalog.map { ($0, $0) }, selection: $draft.alias)
                problem(errors[.alias])
            }
        case .custom:
            VStack(alignment: .leading, spacing: 8) {
                Text("US dollars per million tokens").font(.scaled(12)).foregroundStyle(.secondary)
                rate("Input", "required", $draft.input, .input)
                rate("Cached read", "optional", $draft.cachedInput, .cachedInput)
                rate("Cache write", "optional", $draft.cacheWrite, .cacheWrite)
                rate("Output", "required", $draft.output, .output)
            }
        }
    }

    private func rate(_ title: String, _ hint: String, _ text: Binding<String>, _ field: UsageOverrideDraft.Field) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).frame(width: 110, alignment: .leading)
                TextField(hint, text: text).settingsField(width: 120).environment(\.settingsInvalid, errors[field] != nil)
                    .accessibilityLabel("\(title) dollars per million tokens")
            }
            problem(errors[field]).padding(.leading, 110)
        }
    }

    @ViewBuilder private func problem(_ text: String?) -> some View {
        if let text { ProblemLine(text: text, font: .scaled(11)) }
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
