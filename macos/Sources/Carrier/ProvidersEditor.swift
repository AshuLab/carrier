import CarrierCore
import SwiftUI

/// The editor of one account on the Providers page and the form of Add account (docs/specs/providers-in-settings.md). The rules and the
/// writing are `CarrierCore/ProvidersEdit.swift`'s, tested in `ProvidersFileTests`; these views only show the fields, the problem of each in
/// words and the buttons. The views have no automated test.
struct AccountEditor: View {
    let account: ProviderAccount
    let harness: String
    let store: ProvidersStore
    let close: () -> Void
    @State private var draft: AccountDraft
    @State private var saved: AccountDraft

    init(account: ProviderAccount, harness: String, store: ProvidersStore, close: @escaping () -> Void) {
        self.account = account
        self.harness = harness
        self.store = store
        self.close = close
        let current = (try? ProvidersFile.current().read()).flatMap { $0 }
        let draft = accountDraft(named: account.name, in: current) ?? AccountDraft()
        _draft = State(initialValue: draft)
        _saved = State(initialValue: draft)
    }

    private var problems: [String: String] { draftProblems(draft, harness: harness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(title: "Edit \(account.name)") {
                field("Display name", "displayName", "What the app shows instead of \(account.name)", first: true) {
                    TextField(account.name, text: $draft.displayName).frame(width: 240)
                }
                field("Binary path", "command", "Empty runs \(harness) from the PATH") {
                    TextField("/opt/homebrew/bin/\(harness)", text: $draft.command).frame(width: 240)
                }
                if harness != "agy" {
                    field("Config folder", "configDir", harness == "claude" ? "CLAUDE_CONFIG_DIR; empty is this Mac's login" : "CODEX_HOME; empty is this Mac's login") {
                        TextField("~/.\(harness)-work", text: $draft.configDir).frame(width: 240)
                    }
                    field("Auto-compact after", "autoCompact", harness == "claude" ? "\"auto\" or 100000 to 1000000 tokens; empty is the CLI's own" : "A token count; empty is the CLI's own") {
                        TextField(harness == "claude" ? "auto" : "tokens", text: $draft.autoCompact).frame(width: 140)
                    }
                    field("Launch arguments", "launchArgs", "One per line, added to the ones Carrier passes") {
                        TextEditor(text: $draft.launchArgs).font(.scaled(11.5, design: .monospaced)).frame(width: 240, height: 54)
                            .scrollContentBackground(.hidden).padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    }
                }
                if harness == "claude" {
                    field("Compact idle threads", "idleCompaction", "Use default passes nothing") {
                        Picker("Compact idle threads", selection: $draft.idle) {
                            ForEach(IdleCompaction.allCases.filter { $0 != .always || draft.idle == .always }, id: \.self) { Text($0.title) }
                        }
                        .labelsHidden().frame(width: 140)
                    }
                }
            }
            if let problem = store.editProblem { Text(problem).font(.callout).foregroundStyle(.red) }
            HStack(spacing: 10) {
                Button("Remove", role: .destructive) {
                    Task { if await store.remove(name: account.name) { close() } }
                }
                .help("Removes \(account.name) from providers.json; refused while a role or a chat names it")
                Spacer()
                Button("Cancel") { store.dismissProblem(); close() }
                Button("Save") {
                    Task { if await store.save(name: account.name, draft: draft) { close() } }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(problems.isEmpty == false || draft == saved)
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule)
        }
    }

    private func field<Control: View>(_ title: String, _ key: String, _ detail: String, first: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        SettingsTabRow(title: title, detail: problems[key] ?? detail, first: first) { control().textFieldStyle(.roundedBorder) }
            .foregroundStyle(problems[key] == nil ? Color.primary : Color.red)
            .accessibilityElement(children: .contain)
    }
}

/// Add account: a name and a config folder, for Claude Code or Codex.
struct AddAccountForm: View {
    let harness: String
    let store: ProvidersStore
    let close: () -> Void
    @State private var name = ""
    @State private var folder = ""

    private var problem: String? {
        if name.isEmpty == false, let wrong = nameProblem(name) { return wrong }
        var draft = AccountDraft()
        draft.configDir = folder
        return draftProblems(draft, harness: harness)["configDir"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(title: "Add account") {
                SettingsTabRow(title: "Name", detail: "Lowercase letters, digits and hyphens", first: true) {
                    TextField("\(harness)-work", text: $name).textFieldStyle(.roundedBorder).frame(width: 240)
                }
                SettingsTabRow(title: "Config folder", detail: harness == "claude" ? "CLAUDE_CONFIG_DIR of this login" : "CODEX_HOME of this login") {
                    TextField("~/.\(harness)-work", text: $folder).textFieldStyle(.roundedBorder).frame(width: 240)
                }
            }
            if let message = problem ?? store.editProblem { Text(message).font(.callout).foregroundStyle(.red) }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { store.dismissProblem(); close() }
                Button("Add") {
                    Task { if await store.addAccount(name: name, harness: harness, configDir: folder) { close() } }
                }
                .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(name.isEmpty || problem != nil)
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule)
        }
    }
}
