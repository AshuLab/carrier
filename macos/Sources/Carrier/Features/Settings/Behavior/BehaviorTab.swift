import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The Behavior tab: the values of `engine.json` (CarrierCore/EngineConfig.swift), in the three
/// groups of `behaviorGroups` (CarrierCore/BehaviorPage.swift). Every change that the engine would accept is sent when the person pauses (a number typed as "30" must not reach a running
/// Carrier as 3 and then 30), or at once when they leave: `editBehavior` to the engine, or to `carrier config` when none answers, which writes the file in place and, when the engine runs, makes
/// it run on it; nothing restarts Carrier.
/// Why it cannot save, or what the engine answered, is in the page's header (`SettingsHeaderNoteKey`).
struct BehaviorTabView: View {
    /// Opens a place of Settings (the lead reviewer's screen in Roles)
    let go: (SettingsPlace) -> Void
    @ObservedObject private var start = StartController.shared
    @State private var saved = EngineConfig()
    @State private var draft = EngineConfig()
    /// fields whose text is not a number yet
    @State private var unparsable: Set<String> = []
    @State private var unreadable = false
    /// the file has `agents.leadReviewer`: until it does, Lead rounds is dimmed
    @State private var hasLead = true
    @State private var failure: String?
    /// the send that waits for the person to stop typing, and the values it will send
    @State private var sendLater: Task<Void, Never>?
    @State private var waiting: EngineConfig?
    /// the request in flight; the next one waits for it, so two changes never reach the file out of order
    @State private var sending: Task<Void, Never>?
    private let sender = EngineConfigSender.app
    /// what the engine answered to the last save, from any tab
    private let engine = ReloadStatus.shared

    private var path: String { configFilePath() }

    /// Said at the right of the header only when there is something to say: why it could not save, or what the engine answered.
    private var headerNote: SettingsHeaderNote? {
        if unreadable {
            return SettingsHeaderNote(text: Copy.engineConfigUnreadable(), tone: .problem)
        }
        if let failure { return SettingsHeaderNote(text: failure, tone: .problem) }
        // the page says a problem answer to VoiceOver itself, once, when it comes (`announcesReloadProblems`)
        if let words = engine.words() { return SettingsHeaderNote(text: words, tone: engine.isProblem ? .problem : .plain, announces: false, asksAgain: engine.isProblem) }
        return nil
    }

    private var problems: [String: String] {
        draft.problems().merging(unparsable.map { ($0, Copy.behaviorMustBeNumber()) }) { _, text in text }
    }

    var body: some View {
        SettingsPageBody(reset: { if unreadable == false { draft = EngineConfig(); unparsable = [] } }) {
            ForEach(behaviorGroups(), id: \.title) { page in
                SettingsGroup(id: page.id, title: page.title) {
                    ForEach(Array(page.rows.enumerated()), id: \.element.key) { index, item in
                        row(item, first: index == 0)
                        if item.key == "maxLeadRounds", hasLead == false { noLead }
                    }
                }
            }
        }
        .buttonStyle(SecondaryCapsuleButtonStyle())
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .preference(key: SettingsHeaderNoteKey.self, value: headerNote)
        .announcesReloadProblems(answers: engine.answers, isProblem: engine.isProblem, words: engine.words())
        .onAppear(perform: load)
        // the send that waits for a pause is made when the person leaves, not lost
        .onDisappear { flush() }
        // and when Carrier quits: the app is gone before a pause ends, so this one is sent in place
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if let waiting { sender.sendBeforeQuit(.behavior(waiting)) }
        }
        .onChange(of: start.configExists) { load() }
        // a file that is there but unreadable may be fixed in another app: look again when Carrier is back in front (only then, so no edit is lost)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if unreadable { load() } }
        .onChange(of: draft) {
            failure = nil  // it spoke of an earlier edit
            autosave()
        }
    }

    private func row(_ item: BehaviorRow, first: Bool) -> some View {
        let dimmed = item.key == "maxLeadRounds" && hasLead == false
        return SettingsTabRow(id: item.key, title: item.title, detail: item.detail, first: first, problem: problems[item.key]) { control(item).disabled(dimmed) }
            .opacity(dimmed ? 0.4 : 1)
    }

    /// The line under a dimmed Lead rounds: why, and the way to the lead's screen.
    private var noLead: some View {
        SettingsTabRow(title: Copy.behaviorLeadOffTitle(), detail: Copy.behaviorLeadOffDetail()) {
            Button(Copy.behaviorOpenLead()) { go(SettingsPlace(.roles, path: [AgentRole.leadReviewer.rawValue])) }.controlSize(.small)
        }
    }

    @ViewBuilder private func control(_ item: BehaviorRow) -> some View {
        switch item.control {
        case .minutes:
            field(item.key, $draft.pollIntervalMinutes, unit: item.unit, parse: { Double($0.replacingOccurrences(of: ",", with: ".")) }, format: shownNumber, step: { $0 + Double($1) > 0 ? $0 + Double($1) : nil })
        case .number(let minimum):
            integer(item.key, intBinding(item.key), min: minimum, unit: item.unit)
        case .runTime:
            HStack(spacing: Tokens.Space.s10) {
                if draft.maxExecutionHours != nil {
                    integer(item.key, Binding(get: { draft.maxExecutionHours ?? 4 }, set: { draft.maxExecutionHours = $0 }), min: 1, unit: item.unit)
                }
                ChoicePopUp(
                    label: item.title, options: [(value: false, title: Copy.behaviorLimit()), (value: true, title: Copy.behaviorUnlimited())],
                    selection: Binding(get: { draft.maxExecutionHours == nil }, set: { unlimited in
                        unparsable.remove(item.key)
                        draft.maxExecutionHours = unlimited ? nil : 4
                    })
                )
            }
        case .logLevel:
            ChoicePopUp(label: item.title, options: EngineConfig.logLevels.map { (value: $0, title: $0) }, selection: $draft.logLevel)
        }
    }

    /// The whole-number value of `EngineConfig` that a row of `behaviorGroups` names.
    private func intBinding(_ key: String) -> Binding<Int> {
        switch key {
        case "maxConcurrentEpics": return $draft.maxConcurrentEpics
        case "maxReviews": return $draft.maxReviews
        case "maxLeadRounds": return $draft.maxLeadRounds
        case "maxExecutionRetries": return $draft.maxExecutionRetries
        case "githubCallTimeoutSeconds": return $draft.githubCallTimeoutSeconds
        case "finishedWindowDays": return $draft.finishedWindowDays
        default: preconditionFailure("no whole-number value named \(key)")
        }
    }

    private func integer(_ key: String, _ value: Binding<Int>, min: Int, unit: String? = nil) -> some View {
        field(key, value, unit: unit, parse: { Int($0) }, format: { String($0) }, step: { $0 + $1 >= min ? $0 + $1 : nil })
    }

    private func field<Value: Equatable>(_ key: String, _ value: Binding<Value>, unit: String?, parse: @escaping (String) -> Value?, format: @escaping (Value) -> String, step: @escaping (Value, Int) -> Value?) -> some View {
        HStack(spacing: Tokens.Space.s6) {
            NumberField(key: key, value: value, unparsable: $unparsable, parse: parse, format: format, step: step)
            if let unit { Text(unit).scaledFont(11).foregroundStyle(.secondary) }
        }
    }

    private func shownNumber(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            unreadable = true
            hasLead = true
            failure = nil
            unparsable = []
            return
        }
        unreadable = false
        hasLead = fileHasLeadReviewer(json: data)
        saved = EngineConfig(json: data)
        draft = saved
    }

    /// Sends the values after the request before it; the file is saved, and the engine runs on it, when it answers. `failure` says why not, when the engine refused them or could not be asked.
    private func sendNow() {
        sendLater?.cancel()
        sendLater = nil
        guard let config = waiting else { return }
        waiting = nil
        let before = sending
        sending = Task {
            await before?.value
            let result = await saveEngineConfig(.behavior(config), send: sender.send, status: engine)
            failure = result.problem
            if result == .saved { saved = config }
        }
    }

    /// Sends the values when the person has paused: a number is typed a key at a time, but "30" must not reach a running Carrier as 3 and then 30.
    private func sendAfterPause() {
        sendLater?.cancel()
        sendLater = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled == false { sendNow() }
        }
    }

    /// The send that waits for a pause is made now.
    private func flush() {
        if waiting != nil { sendNow() }
    }

    /// Sends what the person just changed, when the engine would accept it; a value that is still being typed waits.
    private func autosave() {
        guard unreadable == false, draft != saved, problems.isEmpty else { return }
        waiting = draft
        sendAfterPause()
    }
}
