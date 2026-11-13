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
    /// Whether providers.json has this account: what the fields show is read from it, and an account it does not have has nothing to edit.
    private let inFile: Bool

    init(account: ProviderAccount, harness: String, store: ProvidersStore, close: @escaping () -> Void) {
        self.account = account
        self.harness = harness
        self.store = store
        self.close = close
        let current = (try? ProvidersFile.current().read()).flatMap { $0 }
        let stored = accountDraft(named: account.name, in: current)
        inFile = stored != nil
        let draft = stored ?? AccountDraft()
        _draft = State(initialValue: draft)
        _saved = State(initialValue: draft)
    }

    private var problems: [String: String] { draftProblems(draft, harness: harness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if inFile == false {
                // never a blank form that would write over an account it did not read
                Label("\(account.title) is not in providers.json, so there is nothing to edit.", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                Button("Close") { close() }.buttonStyle(SecondaryCapsuleButtonStyle())
            } else {
                SettingsGroup(title: "Edit \(account.title)") {
                    field("Display name", "displayName", "What the app shows instead of \(account.name)", first: true) {
                        TextField(account.name, text: $draft.displayName).settingsField(width: 240)
                    }
                    field("Binary path", "command", "Empty runs \(harness) from the PATH") {
                        TextField("/opt/homebrew/bin/\(harness)", text: $draft.command).settingsField(width: 240)
                    }
                    if harness != "agy" {
                        field("Config folder", "configDir", harness == "claude" ? "CLAUDE_CONFIG_DIR; empty is this Mac's login" : "CODEX_HOME; empty is this Mac's login", hint: "Any path; one that does not start with / or ~/ is taken from your home folder") {
                            TextField("~/.\(harness)-work", text: $draft.configDir).settingsField(width: 240)
                        }
                        field("Auto-compact after", "autoCompact", "Tokens in the conversation before the CLI compacts it. Use default is the CLI's own") {
                            // the steps are ours; a value already in the file that is not one of them stays in the list, so opening the editor never changes it
                            let steps = (harness == "claude" ? ["auto"] : []) + ["100000", "200000", "400000", "600000", "800000", "1000000"]
                            let values = [""] + (draft.autoCompact.isEmpty || steps.contains(draft.autoCompact) ? steps : steps + [draft.autoCompact])
                            NativePopUp(
                                items: values.map { $0.isEmpty ? "Use default" : Int($0).map { $0.formatted() } ?? $0 },
                                selection: Binding(get: { values.firstIndex(of: draft.autoCompact) ?? 0 }, set: { draft.autoCompact = values[$0] })
                            )
                            .accessibilityLabel("Auto-compact after").frame(width: 160)
                        }
                        field("Launch arguments", "launchArgs", "One per line, added to the ones Carrier passes") {
                            TextEditor(text: $draft.launchArgs).font(.scaled(11.5, design: .monospaced))
                                .scrollContentBackground(.hidden).padding(4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                                // the size goes last, around the padding, so the row grows with the box and the box does not spill over its neighbours
                                .frame(width: 240, height: 70)
                        }
                    }
                    if harness == "claude" {
                        field("Compact idle threads", "idleCompaction", "Use default passes nothing") {
                            let cases = IdleCompaction.allCases.filter { $0 != .always || draft.idle == .always }
                            NativePopUp(
                                items: cases.map(\.title),
                                selection: Binding(get: { cases.firstIndex(of: draft.idle) ?? 0 }, set: { draft.idle = cases[$0] })
                            )
                            .accessibilityLabel("Compact idle threads").frame(width: 160)
                        }
                    }
                }
                if let problem = store.editProblem { ProblemLine(text: problem) }
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        Task { if await store.remove(name: account.name) { close() } }
                    } label: { Label("Remove", systemImage: "trash") }
                    .disabled(store.busy)
                    .help("Removes \(account.name) from providers.json; refused while a role or a chat names it")
                    Spacer()
                    Button { store.dismissProblem(); close() } label: { Label("Cancel", systemImage: "xmark") }.disabled(store.busy)
                    Button {
                        Task { if await store.save(name: account.name, draft: draft) { close() } }
                    } label: { Label("Save", systemImage: "checkmark") }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(problems.isEmpty == false || draft == saved || store.busy)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .padding(.top, 10)
            }
        }
        // the system's writing tools have nothing to do with a path or an argument, and their button sits on the arguments box
        .writingToolsBehavior(.disabled)
    }

    private func field<Control: View>(
        _ title: String, _ key: String, _ detail: String, hint: String? = nil, first: Bool = false, @ViewBuilder control: () -> Control
    ) -> some View {
        SettingsTabRow(title: title, detail: [detail, hint].compactMap { $0 }.joined(separator: ". "), first: first, roomy: true, problem: problems[key]) { control() }
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
                    TextField("\(harness)-work", text: $name).settingsField(width: 240)
                }
                SettingsTabRow(
                    title: "Config folder",
                    detail: (harness == "claude" ? "CLAUDE_CONFIG_DIR of this login" : "CODEX_HOME of this login") + ". Any path; one that does not start with / or ~/ is taken from your home folder"
                ) {
                    TextField("~/.\(harness)-work", text: $folder).settingsField(width: 240)
                }
            }
            if let message = problem ?? store.editProblem { ProblemLine(text: message) }
            HStack(spacing: 10) {
                Spacer()
                Button { store.dismissProblem(); close() } label: { Label("Cancel", systemImage: "xmark") }.disabled(store.busy)
                Button {
                    Task { if await store.addAccount(name: name, harness: harness, configDir: folder) { close() } }
                } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(name.isEmpty || problem != nil || store.busy)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .padding(.top, 10)
        }
        .writingToolsBehavior(.disabled)
    }
}
