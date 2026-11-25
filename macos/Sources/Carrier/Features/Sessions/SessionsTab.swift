import CarrierCore
import CarrierUI
import SwiftUI

/// The Sessions tab: what a new session starts with and where it opens, the two ages of the session clock (each a number of days or Never) and whether deleting
/// asks first, and, in dates, what the ages do to a session left alone from today. A change is asked of Carrier's own code as it is made (`editChatSettings`: over the chat host's socket, or
/// `carrier config` when the host does not list `config`), which writes the chat's `chat.json`; the host reads the file each pass, so nothing is restarted. Reset puts the preferences back and writes the default ages.
struct SessionsTabView: View {
    @State private var saved = SessionAges()
    @State private var draft = SessionAges()
    /// `worktreeStart` of chat.json, as the file says
    @State private var start = defaultWorktreeStart
    /// `idleCloseMinutes` of chat.json, as the file says
    @State private var idle = defaultIdleClose
    /// fields whose text is not a number yet
    @State private var unparsable: Set<String> = []
    @State private var failure: String?
    /// what the last request was sent with, so a field that was changed is sent and one that is back to it is not
    @State private var sentStart = defaultWorktreeStart
    @State private var sentIdle = defaultIdleClose
    /// the request in flight; the next one waits for it, so two changes never write the file at once
    @State private var saving: Task<Void, Never>?
    private let host = SocketChatHost(configLauncher: .app)
    /// chat.json could not be read: the ages cannot be changed until it can
    @State private var unreadable = false
    @AppStorage(Preference.chatConfirmDelete) private var confirmDelete
    @AppStorage(Preference.chatNewSessionAgent) private var startAgent
    @AppStorage(Preference.chatNewSessionModel) private var startModel
    @AppStorage(Preference.chatNewSessionEffort) private var startEffort
    @AppStorage(Preference.chatNewSessionAccess) private var startAccess
    @AppStorage(Preference.chatNewSessionWorkIn) private var workIn
    private let catalog = ModelCatalog.shared

    private var startAccounts: [PickerAccount] { startPickerAccounts(catalog) }

    private var startAccessScales: [OptionScale] { accessScalesOfStart(catalog: catalog, agent: startAgent, access: startAccess) }

    private var unparsableFields: Set<SessionAgeField> { Set(unparsable.map { $0 == "archive" ? .archive : .delete }) }

    private var problems: [SessionAgeField: String] { sessionAgeProblems(draft, unparsable: unparsableFields) }

    var body: some View {
        SettingsPageBody(reset: reset) {
            SettingsGroup(
                id: "new-sessions", title: Copy.sessionsSettingsNewSessions(),
                footer: Copy.sessionsSettingsNewSessionsFooter()
            ) {
                SettingsTabRow(id: "starts-with", title: Copy.sessionsSettingsStartsWith(), detail: Copy.sessionsSettingsStartsWithDetail(), first: true) {
                    ModelPickerButton(
                        provider: startAgent.isEmpty ? nil : startAgent, model: startModel.isEmpty ? nil : startModel, effort: startEffort,
                        accounts: startAccounts, catalog: catalog, showsAccess: false, accessScales: startAccessScales,
                        chooseAccess: { option, value in
                            var chosen = NewSessionStart.access(fromJSON: startAccess)
                            chosen[option] = value
                            startAccess = NewSessionStart.json(fromAccess: chosen)
                        },
                        effortFallback: (label: Copy.sessionsSettingsEffortOwn(), detail: Copy.sessionsSettingsEffortOwnDetail()), allowsDefaultModel: true,
                        noneTitle: Copy.sessionsSettingsFirstProvider(), placeholder: Copy.sessionsSettingsFirstProviderShort()
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
                SettingsTabRow(id: "work-in", title: Copy.sessionsSettingsWorkIn(), detail: Copy.sessionsSettingsWorkInDetail()) {
                    ChoicePopUp(label: Copy.sessionsSettingsWorkIn(), options: WorkIn.allCases.map { (value: $0, title: $0.title()) }, selection: $workIn)
                }
                let startOff = worktreeStartOffReason(workIn: workIn)
                SettingsTabRow(id: "start-from", title: Copy.sessionsSettingsStartFrom(), detail: startOff ?? Copy.sessionsSettingsStartFromDetail()) {
                    ChoicePopUp(label: Copy.sessionsSettingsStartFrom(), options: WorktreeStart.allCases.map { (value: $0, title: $0.title()) }, selection: $start)
                        .disabled(startOff != nil || unreadable)
                }
                .foregroundStyle(startOff == nil ? Color.primary : Color.secondary)
            }
            SettingsGroup(
                id: "idle-sessions", title: Copy.sessionsSettingsIdleSessions(),
                footer: Copy.sessionsSettingsIdleFooter()
            ) {
                SettingsTabRow(id: "sleep-after", title: Copy.sessionsSettingsSleepAfter(), detail: Copy.sessionsSettingsSleepAfterDetail(), first: true) {
                    ChoicePopUp(label: Copy.sessionsSettingsSleepAfter(), options: IdleClose.allCases.map { (value: $0, title: $0.title()) }, selection: $idle)
                        .disabled(unreadable)
                }
            }
            SettingsGroup(
                id: "archive-and-delete", title: Copy.sessionsSettingsArchiveAndDelete(),
                footer: Copy.sessionsSettingsArchiveFooter()
            ) {
                row(id: "archive-after", Copy.sessionsSettingsArchiveAfter(), Copy.sessionsSettingsArchiveAfterDetail(), .archive, off: nil, first: true, age: $draft.archive, fallback: defaultArchiveAfterDays)
                row(id: "delete-after", Copy.sessionsSettingsDeleteAfter(), Copy.sessionsSettingsDeleteAfterDetail(), .delete, off: deleteAgeOffReason(draft), age: $draft.delete, fallback: defaultDeleteAfterDays)
                SettingsTabRow(id: "ask-before-deleting-a-session", title: Copy.sessionsSettingsAskBeforeDeleting(), detail: Copy.sessionsSettingsAskBeforeDeletingDetail()) {
                    Toggle(Copy.sessionsSettingsAskBeforeDeleting(), isOn: $confirmDelete).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "with-these-ages", title: Copy.sessionsSettingsWithTheseAges()) {
                // with chat.json unreadable the draft is only the defaults, not what the host will use
                let line = unreadable ? nil : sessionAgesLine(draft, today: Date(), unparsable: unparsableFields)
                if let line { SettingsTabRow(title: Copy.sessionsSettingsStopUsingToday(), detail: line, first: true) { EmptyView() } }
                SettingsTabRow(title: Copy.sessionsSettingsLeftAlone(), detail: Copy.sessionsSettingsLeftAloneDetail(), first: line == nil) { EmptyView() }
            }
            if let failure { Label(failure, icon: .warningFilled).scaledFont(12).foregroundStyle(.orange) }
        }
        .onAppear(perform: load)
        .onChange(of: draft) { save() }
        .onChange(of: start) { saveStart() }
        .onChange(of: idle) { saveIdle() }
    }

    private func row(id: String, _ title: String, _ detail: String, _ field: SessionAgeField, off: String?, first: Bool = false, age: Binding<SessionAge>, fallback: Int) -> some View {
        let key = field == .archive ? "archive" : "delete"
        let days = Binding(get: { if case .days(let days) = age.wrappedValue { days } else { fallback } }, set: { age.wrappedValue = .days($0) })
        return SettingsTabRow(id: id, title: title, detail: off ?? detail, first: first, problem: off == nil ? problems[field] : nil) {
            HStack(spacing: Tokens.Space.s10) {
                if age.wrappedValue != .never {
                    NumberField(key: key, value: days, unparsable: $unparsable, parse: { Int($0) }, format: { String($0) }, step: { $0 + $1 >= 1 ? $0 + $1 : nil })
                    Text(Copy.sessionsSettingsDays()).scaledFont(11).foregroundStyle(.secondary)
                }
                ChoicePopUp(
                    label: title, options: [(value: false, title: Copy.sessionsSettingsDaysChoice()), (value: true, title: Copy.sessionsSettingsNever())],
                    selection: Binding(get: { age.wrappedValue == .never }, set: { never in
                        unparsable.remove(key)
                        age.wrappedValue = never ? .never : .days(fallback)
                    })
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
            start = defaultWorktreeStart
            idle = defaultIdleClose
        }
    }

    private func load() {
        do {
            let file = try currentChatConfig()
            saved = sessionAges(chatJSON: file)
            draft = saved
            start = worktreeStart(chatJSON: file)
            idle = idleClose(chatJSON: file)
            (sentStart, sentIdle) = (start, idle)
            failure = nil
            unreadable = false
        } catch {
            unreadable = true
            failure = Copy.sessionsSettingsUnreadable(error: error.localizedDescription)
        }
    }

    /// Asks for the ages; nothing while a field is refused (its line says why).
    private func save() {
        guard draft != saved, problems.isEmpty else { return }
        saved = draft
        send(.ages(draft))
    }

    private func saveStart() {
        guard start != sentStart else { return }
        sentStart = start
        send(.worktreeStart(start))
    }

    private func saveIdle() {
        guard idle != sentIdle else { return }
        sentIdle = idle
        send(.idleClose(idle))
    }

    /// Sends the change after the one before it; when it is refused or fails, the rows go back to what the file says and the line says why.
    private func send(_ changes: ChatSettingChanges) {
        let before = saving
        saving = Task {
            await before?.value
            do {
                _ = try await host.editChatSettings(changes)
                failure = nil
            } catch {
                FileHandle.standardError.write(Data("carrier: saving chat.json failed: \(error)\n".utf8))
                let words = Self.words(error)
                load()
                failure = words
            }
        }
    }

    private static func words(_ error: Error) -> String {
        if case ControlError.remote(let refusal) = error { return refusal.shown() }
        return Copy.sessionsSettingsSaveFailed(error: error.localizedDescription)
    }
}


/// The providers the chat host lists, the ones whose binary was found marked ready.
@MainActor func startPickerAccounts(_ catalog: ModelCatalog) -> [PickerAccount] {
    catalog.agents.map { PickerAccount(name: $0.name, harness: $0.harness, icon: providerIconName(harness: $0.harness), ready: $0.found) }
}

/// The access options of the provider a new session opens on (the first that can work when none is named), each at the value chosen (the JSON
/// of option and value) and else at the provider's own.
@MainActor func accessScalesOfStart(catalog: ModelCatalog, agent named: String, access json: String) -> [OptionScale] {
    _ = catalog.offers  // the offers are kept in the store; this is what refreshes the view when they arrive
    let chosen = NewSessionStart.access(fromJSON: json)
    let agent = named.isEmpty ? catalog.agents.first { $0.found }?.name : named
    let options = agent.flatMap { AgentOfferStore.shared.offer($0)?.options } ?? []
    return composerMenu(options.map { option in
        guard let value = chosen[option.id], option.values.contains(where: { $0.id == value }) else { return option }
        return ChatOption(id: option.id, label: option.label, values: option.values, current: value)
    }).access
}
