import CarrierCore
import SwiftUI

/// The Sessions tab: what a new session starts with, the two ages of the session clock (each a number of days or Never) and whether deleting
/// asks first. An age is written to the chat's `chat.json` as it is changed (CarrierCore/SessionAges.swift); the chat host reads the file
/// each pass, so nothing is restarted. Reset puts the preferences back and writes the default ages.
struct SessionsTabView: View {
    @State private var saved = SessionAges()
    @State private var draft = SessionAges()
    /// fields whose text is not a number yet
    @State private var unparsable: Set<String> = []
    @State private var failure: String?
    /// chat.json could not be read: the ages cannot be changed until it can
    @State private var unreadable = false
    @AppStorage(AppPreferences.confirmDeleteKey) private var confirmDelete = AppPreferences.defaultConfirmDelete
    @AppStorage(AppPreferences.newSessionAgentKey) private var startAgent = ""
    @AppStorage(AppPreferences.newSessionModelKey) private var startModel = ""
    @AppStorage(AppPreferences.newSessionEffortKey) private var startEffort = ""
    @AppStorage(AppPreferences.newSessionAccessKey) private var startAccess = ""
    private let catalog = ModelCatalog.shared

    /// The providers the chat host lists, the ones whose binary was found marked ready.
    private var startAccounts: [PickerAccount] {
        catalog.agents.map { PickerAccount(name: $0.name, harness: $0.harness, icon: providerIconName(harness: $0.harness), ready: $0.found) }
    }

    /// The access options of the provider a new session opens on (the first that can work when none is named), each at the value chosen here
    /// and else at the provider's own.
    private var startAccessScales: [OptionScale] {
        _ = catalog.offers  // the offers are kept in the store; this is what refreshes the view when they arrive
        let chosen = NewSessionStart.access(fromJSON: startAccess)
        let agent = startAgent.isEmpty ? catalog.agents.first { $0.found }?.name : startAgent
        let options = agent.flatMap { AgentOfferStore.shared.offer($0)?.options } ?? []
        return composerMenu(options.map { option in
            guard let value = chosen[option.id], option.values.contains(where: { $0.id == value }) else { return option }
            return ChatOption(id: option.id, label: option.label, values: option.values, current: value)
        }).access
    }

    private var problems: [SessionAgeField: String] {
        sessionAgeProblems(draft, unparsable: Set(unparsable.map { $0 == "archive" ? .archive : .delete }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: "New sessions") {
                SettingsTabRow(title: "Starts with", detail: "The provider, model and reasoning a new session opens with; the message box still changes them for that session", first: true) {
                    ModelPickerButton(
                        provider: startAgent.isEmpty ? nil : startAgent, model: startModel.isEmpty ? nil : startModel, effort: startEffort,
                        accounts: startAccounts, catalog: catalog, showsAccess: false, accessScales: startAccessScales,
                        chooseAccess: { option, value in
                            var chosen = NewSessionStart.access(fromJSON: startAccess)
                            chosen[option] = value
                            startAccess = NewSessionStart.json(fromAccess: chosen)
                        },
                        effortFallback: (label: "Provider's own", detail: "The level the provider starts with."), allowsDefaultModel: true,
                        noneTitle: "First provider that can work", placeholder: "First that can work"
                    ) { pick in
                        switch pick {
                        case .account(let agent, let model): startAgent = agent; startModel = model ?? ""
                        case .effort(let level): startEffort = level
                        case .none: startAgent = ""; startModel = ""; startEffort = ""; startAccess = ""
                        case .inherit: break
                        }
                    }
                    .task { await catalog.load() }
                }
            }
            SettingsGroup(title: "Archive and delete") {
                row("Archive after", "Days without activity before a session is archived", .archive, off: nil, first: true, age: $draft.archive, fallback: defaultArchiveAfterDays)
                row("Delete after", "Days an archived session waits before it is deleted, with its worktree. Work that is not saved is kept", .delete, off: deleteAgeOffReason(draft), age: $draft.delete, fallback: defaultDeleteAfterDays)
                SettingsTabRow(title: "Ask before deleting a session", detail: "The question says that its worktree is removed with it") {
                    Toggle("Ask before deleting a session", isOn: $confirmDelete).labelsHidden().toggleStyle(.switch)
                }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
            SettingsGroup(title: "Reset") {
                SettingsTabRow(title: "Restore the defaults", detail: "Everything on this page goes back to how it came", first: true) {
                    Button(action: reset) { Label("Reset", systemImage: "arrow.counterclockwise") }.buttonStyle(SecondaryCapsuleButtonStyle())
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: draft) { save() }
    }

    private func row(_ title: String, _ detail: String, _ field: SessionAgeField, off: String?, first: Bool = false, age: Binding<SessionAge>, fallback: Int) -> some View {
        let key = field == .archive ? "archive" : "delete"
        let days = Binding(get: { if case .days(let days) = age.wrappedValue { days } else { fallback } }, set: { age.wrappedValue = .days($0) })
        return SettingsTabRow(title: title, detail: off ?? detail, first: first, problem: off == nil ? problems[field] : nil) {
            HStack(spacing: 10) {
                if age.wrappedValue != .never {
                    NumberField(key: key, value: days, unparsable: $unparsable, parse: { Int($0) }, format: { String($0) }, step: { $0 + $1 >= 1 ? $0 + $1 : nil })
                    Text("days").font(.caption).foregroundStyle(.secondary)
                }
                ChoicePopUp(
                    label: title, options: [(value: false, title: "Days"), (value: true, title: "Never")],
                    selection: Binding(get: { age.wrappedValue == .never }, set: { never in
                        unparsable.remove(key)
                        age.wrappedValue = never ? .never : .days(fallback)
                    }),
                    width: 110
                )
            }
            .disabled(off != nil || unreadable)
        }
        .foregroundStyle(off == nil && problems[field] == nil ? Color.primary : off == nil ? Color.orange : Color.secondary)
    }

    /// The preferences of the page go back to their defaults, and so do the ages when the file can be read (the change is written by `save`).
    private func reset() {
        AppPreferences().reset(.sessions)
        if unreadable == false {
            unparsable = []
            draft = SessionAges()
        }
    }

    private func load() {
        do {
            saved = sessionAges(chatJSON: try currentChatConfig())
            draft = saved
            failure = nil
            unreadable = false
        } catch {
            unreadable = true
            failure = "chat.json could not be read: \(error.localizedDescription)"
        }
    }

    /// Writes the file, read again just now; nothing while a field is refused (its line says why).
    private func save() {
        guard draft != saved, problems.isEmpty else { return }
        do {
            guard let updated = applyingSessionAges(draft, to: try currentChatConfig()) else {
                failure = "chat.json is not a JSON object, so it was not changed."
                return
            }
            try writeCurrentChatConfig(updated)
            saved = draft
            failure = nil
        } catch {
            FileHandle.standardError.write(Data("carrier: saving chat.json failed: \(error)\n".utf8))
            failure = "Could not save chat.json: \(error.localizedDescription)"
        }
    }
}
