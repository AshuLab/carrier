import Foundation
import Testing
@testable import CarrierCore

// The options pill and its panel: the pill's text and the panel's rows as pure functions over what the provider lists (Claude's
// three, Codex's four, none), and the change of an option through a fake host, with its refusal.

private func option(_ id: String, _ label: String, _ values: [(String, String)], current: String) -> ChatOption {
    ChatOption(id: id, label: label, values: values.map { .init(id: $0.0, label: $0.1) }, current: current)
}

private let claude = [
    option("model", "Model", [("sonnet", "Sonnet"), ("opus", "Opus")], current: "sonnet"),
    option("effort", "Effort", [("medium", "Medium"), ("high", "High")], current: "high"),
    option("permissionMode", "Permissions", [("default", "Ask first"), ("acceptEdits", "Accept edits")], current: "default"),
]

private let codex = [
    option("model", "Model", [("gpt-5", "GPT-5")], current: "gpt-5"),
    option("reasoning", "Reasoning", [("medium", "Medium"), ("high", "High")], current: "medium"),
    option("approval", "Approvals", [("on-request", "On request"), ("never", "Never")], current: "on-request"),
    option("sandbox", "Sandbox", [("workspace-write", "Workspace write"), ("read-only", "Read only")], current: "workspace-write"),
]

@Test func thePillJoinsTheCurrentValuesInTheProvidersOrder() {
    #expect(optionsPill(claude) == "Sonnet · High · Ask first")
    #expect(optionsPill(codex) == "GPT-5 · Medium · On request · Workspace write")
}

@Test func thePillIsAbsentWhenTheProviderListsNoOptions() {
    #expect(optionsPill([]) == nil)
}

@Test func aCurrentValueTheProviderDoesNotListShowsAsItIs() {
    #expect(optionsPill([option("model", "Model", [("sonnet", "Sonnet")], current: "claude-x")]) == "claude-x")
}

@Test func thePanelHasARowPerOptionWithTheCurrentValueTicked() {
    let rows = optionRows(claude)
    #expect(rows.map(\.label) == ["Model", "Effort", "Permissions"])
    #expect(rows[1].choices.map(\.label) == ["Medium", "High"])
    #expect(rows[1].choices.map(\.ticked) == [false, true])
    #expect(optionRows(codex).count == 4)
    #expect(optionRows([]).isEmpty)
}

@Test func theEventsReplyCarriesTheOptions() throws {
    let json = """
    {"events":[],"cursor":0,"streaming":"","approvals":[],"options":[{"id":"model","label":"Model","values":[{"id":"sonnet","label":"Sonnet"}],"current":"sonnet"}]}
    """
    #expect(try JSONDecoder().decode(ChatEvents.self, from: Data(json.utf8)).options == [option("model", "Model", [("sonnet", "Sonnet")], current: "sonnet")])
    // a host that says nothing of options lists none
    #expect(try JSONDecoder().decode(ChatEvents.self, from: Data(#"{"events":[],"cursor":0,"streaming":""}"#.utf8)).options.isEmpty)
}

// MARK: through a fake host

private final class OptionsHost: ChatHost, @unchecked Sendable {
    var options = claude
    var refuse: Error?
    var changes: [String] = []

    func agents() async throws -> [ChatAgent] { [] }
    func open(agent: String, folder: String, worktree: WorktreeRequest?) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func interrupt(_ id: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func capabilities() async throws -> Set<ControlClient.Capability> { [] }
    func cloneRepo(_ repo: String) async throws -> ClonedRepo { throw ControlError.closed }
    func createProject(_ name: String) async throws -> String { throw ControlError.closed }
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func answer(_ id: String, approval: String, choice: String) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: options) }
    func setOption(_ id: String, option: String, value: String) async throws {
        changes.append("\(option)=\(value)")
        if let refuse { throw refuse }
        options = options.map { $0.id == option ? ChatOption(id: $0.id, label: $0.label, values: $0.values, current: value) : $0 }
    }
}

@MainActor @Test func theOptionsComeFromTheEventsReplyAndAClosedSessionHasNone() async {
    let host = OptionsHost()
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    #expect(model.options.isEmpty)
    await model.poll()
    #expect(optionsPill(model.options) == "Sonnet · High · Ask first")
    host.options = []
    await model.poll()
    #expect(optionsPill(model.options) == nil)
}

@MainActor @Test func choosingAValueSendsSetOptionAndThePillFollowsTheHostsReply() async {
    let host = OptionsHost()
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in })
    await model.poll()
    await model.setOption("effort", "medium")
    #expect(host.changes == ["effort=medium"])
    #expect(optionsPill(model.options) == "Sonnet · Medium · Ask first" && model.optionRefusal == nil)
}

@MainActor @Test func aRefusalIsSaidInWordsAndNothingChanges() async {
    let host = OptionsHost()
    host.refuse = ControlError.remote("The reasoning effort can only change between turns")
    var logged: [String] = []
    let model = ConversationModel(host: host, sessionId: "s", log: { logged.append($0) })
    await model.poll()
    await model.setOption("effort", "medium")
    #expect(model.optionRefusal == "The reasoning effort can only change between turns")
    #expect(optionsPill(model.options) == "Sonnet · High · Ask first" && logged.isEmpty)
    // the next choice that works clears the words
    host.refuse = nil
    await model.setOption("effort", "medium")
    #expect(model.optionRefusal == nil && optionsPill(model.options) == "Sonnet · Medium · Ask first")
}

@MainActor @Test func aHostThatIsNotAnsweringIsLoggedAndShown() async {
    let host = OptionsHost()
    host.refuse = ControlError.closed
    var logged: [String] = []
    let model = ConversationModel(host: host, sessionId: "s", log: { logged.append($0) })
    await model.setOption("model", "opus")
    #expect(model.optionRefusal == "The chat host is not answering" && logged.count == 1)
}

// MARK: a closed session

private final class MemoryBox: @unchecked Sendable { var stored: [String: [ChatOption]] = [:] }

@MainActor @Test func aClosedSessionListsWhatItOfferedAndAChoiceWaitsForTheMessageThatWakesIt() async {
    let box = MemoryBox()
    let memory = OptionsMemory(load: { box.stored[$0] ?? [] }, save: { box.stored[$0] = $1 })
    let host = OptionsHost()
    let running = ConversationModel(host: host, sessionId: "s", log: { _ in }, memory: memory)
    await running.poll()
    #expect(box.stored["s"] == claude)

    // the session closes, and the app starts again: the host lists nothing, the memory has what it offered
    host.options = []
    let closed = ConversationModel(host: host, sessionId: "s", log: { _ in }, memory: memory)
    #expect(closed.shownOptions.isEmpty)  // nothing is shown before the first answer
    await closed.poll()
    #expect(closed.options.isEmpty && optionsPill(closed.shownOptions) == "Sonnet · High · Ask first")

    // choosing changes the box and asks the host nothing
    await closed.setOption("effort", "medium")
    #expect(host.changes.isEmpty && optionsPill(closed.shownOptions) == "Sonnet · Medium · Ask first" && closed.wakeOptions == ["effort": "medium"])
    // a value the session never offered is not taken
    await closed.setOption("model", "gpt-5")
    #expect(closed.wakeOptions == ["effort": "medium"])
}

@MainActor @Test func theChoicesMadeWhileClosedAreAppliedAfterTheResumeAndBeforeTheMessage() async {
    let box = MemoryBox()
    box.stored["s"] = claude
    let host = OptionsHost()
    host.options = []
    let model = ConversationModel(host: host, sessionId: "s", log: { _ in }, memory: OptionsMemory(load: { box.stored[$0] ?? [] }, save: { box.stored[$0] = $1 }))
    await model.poll()
    await model.setOption("effort", "medium")
    await model.setOption("model", "opus")
    model.draft = "hello"
    await model.submit()
    // the model first: the reasoning levels depend on it
    #expect(host.changes == ["model=opus", "effort=medium"] && model.wakeOptions.isEmpty)
}
