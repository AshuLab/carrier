import AppKit
import CarrierCore
import SwiftUI

/// The Agents page of Settings (docs/specs/agents-in-settings.md): the three roles of every epic in a list, and for the chosen one its Who,
/// Details and When it runs out of tokens cards. This slice only reads `config.json`, `providers.json` and the Agent Forge registry
/// (`agentsPage`, tested in `AgentsPageTests`); the page has no automated test.
struct AgentsTabView: View {
    @ObservedObject private var start = StartController.shared
    @State private var page: AgentsPage?
    @State private var selection: AgentRole = .author

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let page {
                HStack(alignment: .top, spacing: 16) {
                    list(page).frame(width: 300)
                    if let row = page.rows.first(where: { $0.role == selection }) { detail(row, page: page).frame(maxWidth: .infinity, alignment: .topLeading) }
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
        page = currentConfig().flatMap { agentsPage(config: $0, providers: providers, bots: forgeBots(registry: currentForgeRegistry())) }
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
                    SettingsTabRow(title: "Use a lead reviewer", detail: row.off ? "Off: the file has no lead reviewer" : row.what, first: true) {
                        Toggle("Use a lead reviewer", isOn: .constant(row.off == false)).labelsHidden().toggleStyle(.switch).disabled(true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SettingsGroup(title: "Who") {
                    SettingsTabRow(title: "Identity", detail: row.identityDetail, first: true) { value(row.fields.profile, missing: row.identity == .missing) }
                    SettingsTabRow(title: "Provider", detail: row.providerMissing ? "Not an account of providers.json" : "An account from Providers") {
                        value(row.fields.provider, missing: row.providerMissing)
                    }
                    SettingsTabRow(title: "Model", detail: "") { value(row.fields.model, mono: true) }
                    SettingsTabRow(title: "Effort", detail: "How hard it thinks") { value(row.fields.effort, unset: "Default") }
                }
                SettingsGroup(title: "Details") {
                    SettingsTabRow(title: "Persona", detail: personaLine(row.fields.persona), first: true) { EmptyView() }
                }
                SettingsGroup(title: "When it runs out of tokens") {
                    SettingsTabRow(title: "Switch automatically", detail: "Usage limit, rate limit or service down", first: true) {
                        Text(row.steps.isEmpty ? "Off" : "On").foregroundStyle(.secondary)
                    }
                    SettingsTabRow(title: "First", detail: "Provider and model") { value(row.steps.first?.text, unset: "None") }
                    SettingsTabRow(title: "Then", detail: "Optional") { value(row.steps.dropFirst().first?.text, unset: "None") }
                    if row.steps.count > 2 {
                        Text("The file has \(row.steps.count - 2) more step\(row.steps.count == 3 ? "" : "s"), kept and tried in order.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
            }
            // while the lead reviewer is off the rest of its page is shown, dimmed and not usable
            .opacity(row.off ? 0.4 : 1).disabled(row.off)
        }
    }

    private func value(_ text: String?, unset: String = "Not set", missing: Bool = false, mono: Bool = false) -> some View {
        let shown = text.map { missing ? "\($0) (missing)" : $0 } ?? unset
        return Text(shown).font(mono ? .scaled(11.5, design: .monospaced) : .callout).foregroundStyle(missing ? Color.orange : Color.secondary)
            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
    }

    private func personaLine(_ persona: RolePersona?) -> String {
        guard let persona, persona.name != nil || persona.prompt != nil else { return "None. Optional name and instructions" }
        return [persona.name, persona.prompt].compactMap { $0 }.joined(separator: " · ")
    }
}
