import CarrierCore
import SwiftUI

/// The editor of one account on the Providers page and the form of Add account (docs/specs/providers-in-settings.md), each a screen of the page's
/// form: Save (or Add) is the toolbar's, through `SettingsSave`, and leaving the screen is the window's back. The rules and the writing are
/// `CarrierCore/ProvidersEdit.swift`'s, tested in `ProvidersFileTests`; these views only show the fields, the problem of each in words and
/// Remove. The views have no automated test.
struct AccountEditor: View {
    let account: ProviderAccount
    let harness: String
    let store: ProvidersStore
    let close: () -> Void
    @Environment(\.settingsSave) private var saver
    @State private var owner = UUID()
    /// Which of the two pickers that open in a popover is open.
    @State private var picking: Picking?
    @State private var draft: AccountDraft
    @State private var saved: AccountDraft
    private enum Picking { case icon, color }
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

    /// Eight 30 pt tiles with 8 pt between them: what the icon and the color pickers of the popovers are made of.
    private static let tile: CGFloat = 30, gap: CGFloat = 8, columns = 8
    static let gridWidth = CGFloat(columns) * tile + CGFloat(columns - 1) * gap
    /// One width for every control of the form, the selects' own, so the fields, the pop-ups and the box end on the same line.
    static let controlWidth = settingsSelectWidth

    private var problems: [String: String] { draftProblems(draft, harness: harness) }

    private var canSave: Bool { problems.isEmpty && draft != saved }

    var body: some View {
        // a Group and not a stack: the groups are sections of the page's form
        Group {
            if inFile == false {
                // never a blank form that would write over an account it did not read
                SettingsGroup(title: "") {
                    Label("\(account.title) is not in providers.json, so there is nothing to edit.", systemImage: "exclamationmark.triangle.fill").font(.scaled(12)).foregroundStyle(.orange)
                }
            } else {
                SettingsGroup(title: "Name") {
                    field("Display name", "displayName", "What the app shows instead of \(account.name)", first: true) {
                        TextField("", text: $draft.displayName, prompt: Text(account.name)).settingsField(width: Self.controlWidth)
                    }
                    if store.identityEditable {
                        field("Label", "label", "Short, for tabs, chips and the message box. Empty uses the display name") {
                            TextField("", text: $draft.label, prompt: Text(account.name)).settingsField(width: Self.controlWidth)
                        }
                        field("Icon", "icon", "The tool's mark by default") { pickerButton(.icon) }
                        field("Color", "color", "Tints the mark wherever it shows") { pickerButton(.color) }
                    } else {
                        // the installed carrier would refuse the whole file with these keys in it, so they are not offered until it is updated
                        SettingsTabRow(title: "Label, icon and color", detail: "The installed carrier does not know them yet. Update it (brew upgrade carrier) and restart the chat host to set them", roomy: true) {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                    }
                }
                SettingsGroup(title: "Where it runs") {
                    field("Binary path", "command", "Empty runs \(harness) from the PATH", first: true) {
                        TextField("", text: $draft.command, prompt: Text("/opt/homebrew/bin/\(harness)")).settingsField(width: Self.controlWidth)
                    }
                    if harness != "agy" {
                        field("Config folder", "configDir", harness == "claude" ? "CLAUDE_CONFIG_DIR; empty is this Mac's login" : "CODEX_HOME; empty is this Mac's login", hint: "Any path; one that does not start with / or ~/ is taken from your home folder") {
                            TextField("", text: $draft.configDir, prompt: Text("~/.\(harness)-work")).settingsField(width: Self.controlWidth)
                        }
                    }
                }
                if harness != "agy" {
                    SettingsGroup(title: "Advanced") {
                        field("Auto-compact after", "autoCompact", "Tokens in the conversation before the CLI compacts it. Use default is the CLI's own", first: true) {
                            // the steps are ours; a value already in the file that is not one of them stays in the list, so opening the editor never changes it
                            let steps = (harness == "claude" ? ["auto"] : []) + ["100000", "200000", "400000", "600000", "800000", "1000000"]
                            let values = [""] + (draft.autoCompact.isEmpty || steps.contains(draft.autoCompact) ? steps : steps + [draft.autoCompact])
                            SelectMenu(
                                items: values.map { $0.isEmpty ? "Use default" : Int($0).map { $0.formatted() } ?? $0 },
                                selection: Binding(get: { values.firstIndex(of: draft.autoCompact) ?? 0 }, set: { draft.autoCompact = values[$0] })
                            )
                            .accessibilityLabel("Auto-compact after").frame(width: Self.controlWidth)
                        }
                        field("Launch arguments", "launchArgs", "One per line, added to the ones Carrier passes") {
                            TextEditor(text: $draft.launchArgs).font(.scaled(11.5, design: .monospaced))
                                .scrollContentBackground(.hidden).padding(4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                                // the size goes last, around the padding, so the row grows with the box and the box does not spill over its neighbours
                                .frame(width: Self.controlWidth, height: 70)
                        }
                        if harness == "claude" {
                            field("Compact idle threads", "idleCompaction", "Use default passes nothing") {
                                let cases = IdleCompaction.allCases.filter { $0 != .always || draft.idle == .always }
                                SelectMenu(
                                    items: cases.map(\.title),
                                    selection: Binding(get: { cases.firstIndex(of: draft.idle) ?? 0 }, set: { draft.idle = cases[$0] })
                                )
                                .accessibilityLabel("Compact idle threads").frame(width: Self.controlWidth)
                            }
                        }
                    }
                }
                if let problem = store.editProblem { SettingsGroup(title: "") { ProblemLine(text: problem) } }
                if problems["configDir"] == nil, draft.configDir != saved.configDir, let note = store.sharedFolderNote(configDir: draft.configDir, harness: harness, except: account.name) {
                    SettingsGroup(title: "") { Label(note, systemImage: "info.circle").font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                SettingsGroup(title: "") {
                    SettingsTabRow(title: "Remove account", detail: "Removes \(account.name) from providers.json; refused while a role or a chat names it", first: true) {
                        Button(role: .destructive) {
                            Task { if await store.remove(name: account.name) { ProviderIdentityStore.shared.reload(); close() } }
                        } label: { Label("Remove…", systemImage: "trash") }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
        }
        // the system's writing tools have nothing to do with a path or an argument, and their button sits on the arguments box
        .writingToolsBehavior(.disabled)
        .onAppear(perform: publish)
        .onChange(of: draft) { publish() }
        .onChange(of: saved) { publish() }
        .onDisappear { saver?.clear(owner) }
    }

    /// Save is the toolbar's: on while something changed and nothing is wrong, and it writes what the fields hold now.
    private func publish() {
        guard inFile else { return saver?.clear(owner) ?? () }
        let draft = draft
        saver?.set(owner, title: "Save", enabled: canSave) {
            Task { if await store.save(name: account.name, draft: draft) { ProviderIdentityStore.shared.reload(); close() } }
        }
    }

    /// The icon or the color as it is now and a button that opens its choices in a popover, so the form is not three screens tall.
    private func pickerButton(_ kind: Picking) -> some View {
        HStack(spacing: 10) {
            if kind == .icon {
                iconGlyph(draft.icon).foregroundStyle(draft.color?.color ?? Color.primary).frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            } else if let color = draft.color {
                Circle().fill(color.color).frame(width: 18, height: 18)
            } else {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 18, height: 18)
            }
            Button("Change…") { picking = kind }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                .accessibilityLabel(kind == .icon ? "Change the icon" : "Change the color")
                .popover(isPresented: Binding(get: { picking == kind }, set: { if $0 == false { picking = nil } }), arrowEdge: .bottom) {
                    Group { if kind == .icon { iconPicker } else { colorPicker } }.padding(14)
                }
        }
    }

    private var grid: [GridItem] { Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.gap), count: Self.columns) }

    /// The tool's own mark, then each glyph and the first letter, in the color chosen below so the choice is seen as it will look.
    private var iconPicker: some View {
        let choices: [AccountIcon?] = [nil] + AccountIcon.offered(palette: store.paletteEditable) + stored(draft.icon, in: AccountIcon.offered(palette: store.paletteEditable))
        let tint = draft.color?.color ?? Color.primary
        return LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
            ForEach(choices, id: \.self) { choice in
                let on = draft.icon == choice
                Button { draft.icon = choice } label: {
                    iconGlyph(choice).foregroundStyle(tint).frame(width: Self.tile, height: Self.tile)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(iconName(choice)).accessibilityLabel(iconName(choice)).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(width: Self.gridWidth, alignment: .leading)
    }

    /// A value already in the file that this host does not offer (a later icon with an older host) stays on the list, so opening the editor never changes it.
    private func stored<Value: Equatable>(_ value: Value?, in offered: [Value]) -> [Value?] {
        guard let value, offered.contains(value) == false else { return [] }
        return [value]
    }

    @ViewBuilder private func iconGlyph(_ choice: AccountIcon?) -> some View {
        if let symbol = choice?.symbol {
            Image(systemName: symbol).font(.scaled(15, weight: .medium))
        } else if choice == .letter {
            Text(String(account.name.prefix(1)).uppercased()).font(.scaled(13, weight: .bold))
        } else {
            ProviderMark(name: providerIconName(harness: harness), size: 16)
        }
    }

    private func iconName(_ choice: AccountIcon?) -> String {
        switch choice {
        case nil: "The tool's mark"
        case .letter: "First letter"
        case let named?: named.rawValue.capitalized
        }
    }

    private var colorPicker: some View {
        let choices: [AccountColor?] = [nil] + AccountColor.offered(palette: store.paletteEditable) + stored(draft.color, in: AccountColor.offered(palette: store.paletteEditable))
        return LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
            ForEach(choices, id: \.self) { swatch($0) }
        }
        .frame(width: Self.gridWidth, alignment: .leading)
    }

    private func swatch(_ choice: AccountColor?) -> some View {
        let on = draft.color == choice
        let name = choice?.rawValue.capitalized ?? "None"
        return Button { draft.color = choice } label: {
            Group {
                if let choice {
                    Circle().fill(choice.color)
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1.5).overlay(Image(systemName: "slash.circle").font(.scaled(9)).foregroundStyle(.secondary))
                }
            }
            .frame(width: 20, height: 20).padding(5)
            .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(on ? 1 : 0))
            .frame(width: Self.tile, height: Self.tile)
        }
        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func field<Control: View>(
        _ title: String, _ key: String, _ detail: String, hint: String? = nil, first: Bool = false, @ViewBuilder control: () -> Control
    ) -> some View {
        SettingsTabRow(title: title, detail: [detail, hint].compactMap { $0 }.joined(separator: ". "), first: first, roomy: true, problem: problems[key]) { control() }
            .accessibilityElement(children: .contain)
    }
}

/// Add account: a name and a config folder, for Claude Code or Codex. A screen of the page like the editor: Add is the toolbar's.
struct AddAccountForm: View {
    let harness: String
    let store: ProvidersStore
    let close: () -> Void
    @Environment(\.settingsSave) private var saver
    @State private var owner = UUID()
    @State private var name = ""
    @State private var folder = ""

    private var problem: String? {
        if name.isEmpty == false, let wrong = nameProblem(name) { return wrong }
        var draft = AccountDraft()
        draft.configDir = folder
        return draftProblems(draft, harness: harness)["configDir"]
    }

    var body: some View {
        Group {
            SettingsGroup(title: "Add account") {
                SettingsTabRow(title: "Name", detail: "Lowercase letters, digits and hyphens", first: true) {
                    TextField("", text: $name, prompt: Text("\(harness)-work")).settingsField(width: AccountEditor.controlWidth)
                }
                SettingsTabRow(
                    title: "Config folder",
                    detail: (harness == "claude" ? "CLAUDE_CONFIG_DIR of this login" : "CODEX_HOME of this login") + ". Any path; one that does not start with / or ~/ is taken from your home folder"
                ) {
                    TextField("", text: $folder, prompt: Text("~/.\(harness)-work")).settingsField(width: AccountEditor.controlWidth)
                }
            }
            if let message = problem ?? store.editProblem { SettingsGroup(title: "") { ProblemLine(text: message) } }
            if let note = store.sharedFolderNote(configDir: folder, harness: harness) {
                SettingsGroup(title: "") { Label(note, systemImage: "info.circle").font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .writingToolsBehavior(.disabled)
        .onAppear(perform: publish)
        .onChange(of: name) { publish() }
        .onChange(of: folder) { publish() }
        .onDisappear { saver?.clear(owner) }
    }

    private func publish() {
        let (name, folder) = (name, folder)
        saver?.set(owner, title: "Add", enabled: name.isEmpty == false && problem == nil) {
            Task { if await store.addAccount(name: name, harness: harness, configDir: folder) { close() } }
        }
    }
}
