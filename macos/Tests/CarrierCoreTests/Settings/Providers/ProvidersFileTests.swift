import Foundation
import Testing
@testable import CarrierCore

// What the app asks for `providers.json` (docs/adr/0020, ADR 0053): Carrier's own code writes the file, so the fake chat host stands in for it with the Swift functions that
// used to write it (unknown keys kept, the file written whole, a failed write leaving the old one), and the store is checked for what it asks, shows and reads: the first-open
// creation, the "found, not added" rule, the engine's answer and the refusals, over a temporary folder.

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-providers-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

private func text(_ file: ProvidersFile) throws -> String { String(decoding: try #require(try file.read()), as: UTF8.self) }

private func providers(_ file: ProvidersFile) throws -> [String: [String: Any]] {
    let json = try JSONSerialization.jsonObject(with: try #require(try file.read())) as? [String: Any]
    return try #require(json?["providers"] as? [String: [String: Any]])
}

@Test func addingAnAccountKeepsTheKeysTheAppDoesNotKnowAndWritesTheFileWhole() throws {
    let existing = Data(#"{"future":{"a":1},"providers":{"claude-work":{"harness":"claude","configDir":"/h/.cw","launchArgs":["--chrome"],"newKey":true}}}"#.utf8)
    let updated = try applyingAccounts([(name: "codex", harness: "codex")], to: existing)
    let json = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
    #expect((json["future"] as? [String: Int]) == ["a": 1])
    let map = try #require(json["providers"] as? [String: [String: Any]])
    #expect(map["claude-work"]?["newKey"] as? Bool == true && map["claude-work"]?["launchArgs"] as? [String] == ["--chrome"])
    #expect(map["codex"]?["harness"] as? String == "codex" && map["codex"]?["enabled"] == nil)
    #expect(map.keys.sorted() == ["claude-work", "codex"])
}

@Test func aFileThatIsNotAnObjectWithAProvidersMapIsNeverOverwrittenAndATakenNameIsNeverReplaced() throws {
    for bad in ["[1]", "not json", #"{"providers":[]}"#] {
        #expect(throws: ProvidersFileError.notAnObject) { try applyingAccounts([(name: "codex", harness: "codex")], to: Data(bad.utf8)) }
    }
    let taken = Data(#"{"providers":{"codex":{"harness":"codex","launchArgs":["-x"]}}}"#.utf8)
    #expect(throws: ProvidersFileError.taken("codex")) { try applyingAccounts([(name: "codex", harness: "codex")], to: taken) }
}

@Test func theStoreWritesTheFileInOneStepAndAFailedWriteLeavesTheOldOne() throws {
    let folder = try temporaryFolder()
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
        try? FileManager.default.removeItem(atPath: folder)
    }
    let file = ProvidersFile(folder: folder)
    #expect(file.exists == false)
    #expect(try file.read() == nil)
    try file.write(applyingAccounts([(name: "claude", harness: "claude")], to: nil))
    let before = try text(file)
    #expect(try providers(file).keys.sorted() == ["claude"])
    // no temporary file is left beside it
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder) == ["providers.json"])

    // a folder nobody can write to: the replacement cannot be made, and the old file is as it was
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder)
    #expect(throws: (any Error).self) { try file.write(applyingAccounts([(name: "codex", harness: "codex")], to: Data(before.utf8))) }
    #expect(try text(file) == before)
}

// MARK: first open and Add, through a fake host

private final class ProvidersHost: ChatHost, @unchecked Sendable {
    var capabilitiesAnswer: Set<ControlClient.Capability> = [.providers]
    var reply: HostProviders
    var asked = 0
    var regenerateTitlesCalls = 0
    var regenerateTitlesResult: Result<Int, Error> = .success(0)
    /// What Carrier's writing code works on, who it finds using an account, and what the engine answers once the file is written.
    var file: ProvidersFile?
    var uses: () throws -> [String: [AccountUse]] = { [:] }
    var engine = ReloadOutcome.applied
    /// The requests asked, and how many of them wrote the file (and so asked the engine).
    var requests: [ProvidersRequest] = []
    var engineAsks = 0

    init(_ json: String) throws { reply = try JSONDecoder().decode(HostProviders.self, from: Data(json.utf8)) }

    func changeProviders(_ request: ProvidersRequest) async throws -> ProvidersSaved {
        requests.append(request)
        guard let file else { throw ControlError.closed }
        let current: Data?
        let updated: Data
        do {
            current = try file.read()
            switch request {
            case .setAccounts(let accounts): updated = try applyingAccounts(accounts.map { ($0.name, $0.harness) }, to: current)
            case .addAccount(let name, let harness, let configDir): updated = try applyingNewAccount(name: name, harness: harness, configDir: configDir, to: current)
            case .editAccount(let name, let draft): updated = try applyingEdit(name: name, draft: draft, to: current)
            case .removeAccount(let name): updated = try applyingRemoval(name: name, uses: try uses()[name] ?? [], to: current)
            case .setTextGenerator(let choice): updated = try applyingTextGenerator(choice.map { ($0.server, $0.model) }, to: current)
            }
        } catch let error as ProvidersFileError {
            throw ControlError.remote(fixtureProvidersRefusal(error))
        }
        try file.write(updated)
        engineAsks += 1
        return try JSONDecoder().decode(ProvidersSaved.self, from: Data(engineReply(engine).utf8))
    }

    func capabilities() async throws -> Set<ControlClient.Capability> { capabilitiesAnswer }
    func providers() async throws -> HostProviders { asked += 1; return reply }
    func regenerateTitles() async throws -> Int {
        regenerateTitlesCalls += 1
        return try regenerateTitlesResult.get()
    }

    func agents() async throws -> [ChatAgent] { [] }
    func open(plan: SessionPlan) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String, ifStale: Bool) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func send(_ id: String, _ text: String, command: String?) async throws {}
    func interrupt(_ id: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: [], commands: []) }
    func setOption(_ id: String, option: String, value: String) async throws {}
}

/// The `engine` part of a reply, as Node says what the engine did.
private func engineReply(_ outcome: ReloadOutcome) -> String {
    switch outcome {
    case .applied: #"{"saved":{},"engine":"applied"}"#
    case .nobody, .unsupported: #"{"saved":{},"engine":"notRunning"}"#
    case .refused(let refusal): #"{"saved":{},"engine":"refused","engineReason":{"error":\#(jsonString(refusal.text))}}"#
    case .noAnswer: #"{"saved":{},"engine":"refused","engineReason":{"error":"no answer","code":"providers.engineNoAnswer"}}"#
    }
}

@MainActor private func makeStore(
    _ host: ProvidersHost, _ file: ProvidersFile, uses: @escaping () throws -> [String: [AccountUse]] = { [:] }, engine: ReloadOutcome = .applied,
    log: @escaping (String) -> Void = { _ in }
) -> ProvidersStore {
    (host.file, host.uses, host.engine) = (file, uses, engine)
    return ProvidersStore(host: host, file: { file }, log: log, status: ReloadStatus())
}

private func account(_ name: String, found: Bool) -> String {
    #"{"name":"\#(name)","harness":"\#(name)","found":\#(found),"state":"\#(found ? "ready" : "missing")"}"#
}

private func replyJSON(accounts: [String], unadded: [String] = []) -> String {
    #"{"accounts":[\#(accounts.joined(separator: ","))],"unadded":[\#(unadded.map { #"{"harness":"\#($0)","path":"/bin/\#($0)"}"# }.joined(separator: ","))],"servers":[]}"#
}

@MainActor @Test func withNoFileAndClaudeAndCodexFoundTheFirstOpenWritesExactlyThoseTwoNotOffered() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    // with no file the host answers the default accounts, one per harness, whether found or not
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true), account("codex", found: true), account("agy", found: false)]))
    let store = makeStore(host, file)
    await store.createFileIfMissing()
    let written = try providers(file)
    #expect(written.keys.sorted() == ["claude", "codex"])
    #expect(written.values.allSatisfy { $0.keys.sorted() == ["harness"] })
    #expect(written["codex"]?["harness"] as? String == "codex")
    // and the page shows what the host says after it
    #expect(host.asked == 2)
    if case .reply = store.outcome {} else { Issue.record("the store should hold the host's reply") }
}

@MainActor @Test func withAFileThereTheFirstOpenWritesNothingAndDoesNotEvenAsk() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    // an account the person removed: claude is found and has none
    let mine = #"{"providers":{"codex":{"harness":"codex"}},"extra":1}"#
    try file.write(Data(mine.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("codex", found: true)], unadded: ["claude"]))
    let store = makeStore(host, file)
    await store.createFileIfMissing()
    #expect(try text(file) == mine && host.asked == 0)
}

@MainActor @Test func theFirstOpenWritesNothingWhenTheHostCannotAnswerOrFoundNothingOrTheFileDoesNotMatch() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let none = try ProvidersHost(replyJSON(accounts: [account("claude", found: false)]))
    await makeStore(none, file).createFileIfMissing()
    let old = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    old.capabilitiesAnswer = []
    await makeStore(old, file).createFileIfMissing()
    let problem = try ProvidersHost(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"(file)","message":"bad"}}"#)
    await makeStore(problem, file).createFileIfMissing()
    #expect(file.exists == false)
}

@MainActor @Test func addWritesTheAccountAndAnAccountRemovedLaterIsNotBroughtBackByTheNextOpen() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude","command":"/opt/claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = makeStore(host, file)
    await store.add(harness: "agy")
    let written = try providers(file)
    #expect(written.keys.sorted() == ["agy", "claude"] && written["agy"]?.keys.sorted() == ["harness"])
    #expect(written["claude"]?["command"] as? String == "/opt/claude" && store.addProblem == nil)

    // the person removes claude by hand; opening the app again does not add it back
    try file.write(Data(#"{"providers":{"agy":{"harness":"agy"}}}"#.utf8))
    let after = try text(file)
    await store.createFileIfMissing()
    #expect(try text(file) == after)
}

@MainActor @Test func anAddThatCannotWriteSaysWhyAndLeavesTheFileAlone() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let host = try ProvidersHost(replyJSON(accounts: [], unadded: ["codex"]))
    let store = makeStore(host, file)

    try file.write(Data("[1]".utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem?.contains("not a JSON object") == true)
    #expect(try text(file) == "[1]")

    try file.write(Data(#"{"providers":{"codex":{"harness":"claude"}}}"#.utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem == "There is already an account named codex.")

    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let stuck = makeStore(host, failing)
    await stuck.add(harness: "agy")
    #expect(stuck.addProblem?.contains("could not be written") == true)
    #expect(try text(file) == #"{"providers":{"codex":{"harness":"claude"}}}"#)
}

// MARK: add, edit and remove (ProvidersEdit)

private func map(_ data: Data) throws -> [String: [String: Any]] {
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(json["providers"] as? [String: [String: Any]])
}

private let base = Data(#"{"future":1,"providers":{"claude":{"harness":"claude","note":"keep","model":"m","newKey":{"a":1}},"codex":{"harness":"codex"},"agy":{"harness":"agy"}}}"#.utf8)

@Test func addingAnAccountWritesItsNameHarnessAndFolderAndRefusesWhatTheEngineWouldRefuse() throws {
    let added = try map(applyingNewAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw", to: base))
    #expect(added["claude-work"]?["harness"] as? String == "claude" && added["claude-work"]?["configDir"] as? String == "/h/.cw")
    #expect(added["claude-work"]?.count == 2)
    #expect(added["claude"]?["newKey"] != nil && added.keys.sorted() == ["agy", "claude", "claude-work", "codex"])
    // no folder is no key
    #expect(try map(applyingNewAccount(name: "codex-2", harness: "codex", configDir: "", to: base))["codex-2"]?.keys.sorted() == ["harness"])
    #expect(throws: ProvidersFileError.taken("claude")) { try applyingNewAccount(name: "claude", harness: "claude", configDir: "", to: base) }
    for bad in ["", "Work", "1work", "a_b", "a b", String(repeating: "a", count: 41), "é"] {
        #expect(throws: (any Error).self, "\(bad)") { try applyingNewAccount(name: bad, harness: "claude", configDir: "", to: base) }
    }
    #expect(try map(applyingNewAccount(name: String(repeating: "a", count: 40), harness: "claude", configDir: "", to: base)).count == 4)
    // a folder that is not absolute is taken from the home folder, so the file is one the engine reads
    #expect(try map(applyingNewAccount(name: "w", harness: "claude", configDir: "relative/dir", to: base))["w"]?["configDir"] as? String == "~/relative/dir")
    #expect(throws: ProvidersFileError.self) { try applyingNewAccount(name: "w", harness: "agy", configDir: "", to: base) }
    #expect(throws: ProvidersFileError.notAnObject) { try applyingNewAccount(name: "w", harness: "claude", configDir: "", to: Data("[]".utf8)) }
}

@Test func eachFieldWritesItsKeyAndAnEmptiedFieldRemovesIt() throws {
    var draft = AccountDraft()
    draft.displayName = " Work "
    draft.command = "/opt/bin/claude"
    draft.configDir = "~/.claude-work"
    draft.autoCompact = "300000"
    draft.launchArgs = "--chrome\n\n --verbose "
    draft.idle = .never
    let written = try map(applyingEdit(name: "claude", draft: draft, to: base))["claude"]
    #expect(written?["displayName"] as? String == "Work" && written?["command"] as? String == "/opt/bin/claude" && written?["configDir"] as? String == "~/.claude-work")
    #expect(written?["autoCompact"] as? Int == 300_000 && written?["launchArgs"] as? [String] == ["--chrome", "--verbose"] && written?["idleCompaction"] as? Bool == false)
    // the keys the editor does not own stay
    #expect(written?["model"] as? String == "m" && written?["note"] as? String == "keep" && written?["newKey"] != nil)

    // "auto" stays a string; Use default and every emptied field remove their keys
    draft.autoCompact = "auto"
    #expect(try map(applyingEdit(name: "claude", draft: draft, to: base))["claude"]?["autoCompact"] as? String == "auto")
    let again = try applyingEdit(name: "claude", draft: draft, to: applyingEdit(name: "claude", draft: draft, to: base))
    var cleared = try #require(accountDraft(named: "claude", in: again))
    #expect(cleared.displayName == "Work" && cleared.launchArgs == "--chrome\n--verbose" && cleared.autoCompact == "auto" && cleared.idle == .never)
    cleared = AccountDraft()
    let emptied = try map(applyingEdit(name: "claude", draft: cleared, to: again))["claude"]
    #expect(emptied?.keys.sorted() == ["harness", "model", "newKey", "note"])
    let json = try #require(JSONSerialization.jsonObject(with: applyingEdit(name: "claude", draft: draft, to: base)) as? [String: Any])
    #expect(json["future"] as? Int == 1)

    #expect(throws: ProvidersFileError.missing("nope")) { try applyingEdit(name: "nope", draft: draft, to: base) }
}

@Test func theEditorRefusesInWordsNamingTheFieldWhatTheSchemaOfTheEngineRefuses() throws {
    func problems(_ harness: String, _ change: (inout AccountDraft) -> Void) -> [String: String] {
        var draft = AccountDraft()
        change(&draft)
        return draftProblems(draft, harness: harness)
    }
    #expect(problems("claude") { $0.autoCompact = "auto" }.isEmpty)
    #expect(problems("claude") { $0.autoCompact = "100000" }.isEmpty && problems("claude") { $0.autoCompact = "1000000" }.isEmpty)
    for bad in ["99999", "1000001", "1.5", "300k", "-1", "AUTO"] {
        #expect(problems("claude") { $0.autoCompact = bad }["autoCompact"]?.hasPrefix("Auto-compact after") == true, "\(bad)")
    }
    #expect(problems("codex") { $0.autoCompact = "50000" }.isEmpty && problems("codex") { $0.autoCompact = "1" }.isEmpty)
    for bad in ["auto", "0", "-5", "1.5"] { #expect(problems("codex") { $0.autoCompact = bad }["autoCompact"] != nil, "\(bad)") }
    #expect(problems("agy") { $0.autoCompact = "auto" }["autoCompact"] != nil && problems("agy") { $0.configDir = "/x" }["configDir"] != nil)
    #expect(problems("codex") { $0.idle = .never }["idleCompaction"] != nil && problems("agy") { $0.idle = .never }["idleCompaction"] != nil)
    #expect(problems("claude") { $0.idle = .never }.isEmpty)
    #expect(problems("claude") { $0.command = "claude" }["command"]?.hasPrefix("Binary path") == true && problems("claude") { $0.command = "~/bin/claude" }.isEmpty)
    // any path is taken for the config folder; only a character a path cannot have is refused
    #expect(problems("claude") { $0.configDir = "rel" }.isEmpty && problems("claude") { $0.configDir = "a/b c/../d" }.isEmpty)
    #expect(problems("claude") { $0.configDir = "a\u{7}b" }["configDir"]?.hasPrefix("Config folder") == true)
    #expect(problems("claude") { $0.displayName = String(repeating: "x", count: 61) }["displayName"] != nil)
    // launch arguments that repeat what Carrier sets
    #expect(problems("claude") { $0.launchArgs = "--chrome\n--model=opus" }["launchArgs"]?.contains("--model") == true)
    #expect(problems("claude") { $0.launchArgs = "--permission-mode" }["launchArgs"] != nil)
    #expect(problems("claude") { $0.launchArgs = "--chrome\n--verbose" }.isEmpty)
    #expect(problems("codex") { $0.launchArgs = "--sandbox" }["launchArgs"] != nil)
    #expect(problems("codex") { $0.launchArgs = "-c\nmodel_provider=x" }["launchArgs"]?.contains("model_provider") == true)
    #expect(problems("codex") { $0.launchArgs = "--config=model_auto_compact_token_limit=5" }["launchArgs"] != nil)
    #expect(problems("codex") { $0.launchArgs = "-cmodel_provider=x" }["launchArgs"] != nil)
    #expect(problems("codex") { $0.launchArgs = "-c\nfoo=bar\n--oss" }.isEmpty)
    #expect(problems("agy") { $0.launchArgs = "--model" }.isEmpty)
    // and applyingEdit never writes it
    var draft = AccountDraft()
    draft.autoCompact = "5"
    #expect(throws: ProvidersFileError.self) { try applyingEdit(name: "claude", draft: draft, to: base) }
}

@Test func removingFreesTheAccountOnlyWhenNothingNamesIt() throws {
    let removed = try map(applyingRemoval(name: "codex", uses: [], to: base))
    #expect(removed.keys.sorted() == ["agy", "claude"] && removed["claude"]?["newKey"] != nil)
    let uses: [AccountUse] = [.role(.author), .repoOverride(repo: "a/b", role: .reviewer), .failover(nil), .chatAgent("claude")]
    #expect(throws: ProvidersFileError.inUse("claude", uses)) { try applyingRemoval(name: "claude", uses: uses, to: base) }
    #expect(throws: ProvidersFileError.missing("nope")) { try applyingRemoval(name: "nope", uses: [], to: base) }
}

@Test func aFailoverStepStopsTheRemovalOfItsAccount() {
    let config = Data(#"{"failover":{"roles":{"author":[{"provider":"codex"}]}},"agents":{"author":{"provider":"claude"}}}"#.utf8)
    let chat = Data(#"{"agents":{"x":{"account":"claude"}}}"#.utf8)
    #expect(accountUses(config: config, chat: chat)["codex"] == [.failover(.author)])
    #expect(accountUses(config: config, chat: chat)["claude"] == [.role(.author), .chatAgent("x")])
}

@Test func aConfigFolderThatIsNotAbsoluteIsTakenFromTheHomeFolderAndTheOthersStayAsTheyAre() {
    #expect(normalizedConfigDir("work") == "~/work" && normalizedConfigDir("./work") == "~/work" && normalizedConfigDir("  .claude-work ") == "~/.claude-work")
    #expect(normalizedConfigDir("/srv/claude") == "/srv/claude" && normalizedConfigDir("~/x") == "~/x" && normalizedConfigDir("~") == "~" && normalizedConfigDir("") == "")
}

@Test func theEditorReadsTheAccountFromTheFileAndAnAccountTheFileLacksIsNotInventedAsABlankOne() throws {
    let json = Data(#"{"providers":{"w":{"harness":"claude","displayName":"Work","command":"/bin/c","configDir":"~/.w","autoCompact":200000,"launchArgs":["--a","--b"],"idleCompaction":false}}}"#.utf8)
    let draft = try #require(accountDraft(named: "w", in: json))
    #expect(draft.displayName == "Work" && draft.command == "/bin/c" && draft.configDir == "~/.w" && draft.autoCompact == "200000")
    #expect(draft.launchArgs == "--a\n--b" && draft.idle == .never)
    #expect(accountDraft(named: "nope", in: json) == nil && accountDraft(named: "w", in: nil) == nil)
}

// MARK: the store

@MainActor @Test func theStoreAddsEditsAndRemovesAndSaysWhyItDidNotWrite() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(base)
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    var uses: [String: [AccountUse]] = ["claude": [.role(.author), .chatAgent("claude")]]
    let store = makeStore(host, file, uses: { uses })

    // add: written, and the host asked again
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw"))
    await store.settled()
    #expect(try providers(file).keys.sorted() == ["agy", "claude", "claude-work", "codex"])
    #expect(host.asked == 1 && store.editProblem == nil)
    // a taken or invalid name is refused before writing
    let before = try text(file)
    #expect(await store.addAccount(name: "claude", harness: "claude", configDir: "") == false)
    #expect(store.editProblem == "There is already an account named claude.")
    #expect(await store.addAccount(name: "Bad Name", harness: "claude", configDir: "") == false)
    #expect(store.editProblem?.hasPrefix("Name must be") == true)
    #expect(try text(file) == before)
    #expect(host.asked == 1)

    // edit
    var draft = try #require(accountDraft(named: "claude-work", in: file.read()))
    draft.autoCompact = "250000"
    #expect(await store.save(name: "claude-work", draft: draft))
    await store.settled()
    #expect(try providers(file)["claude-work"]?["autoCompact"] as? Int == 250_000)
    draft.autoCompact = "10"
    let saved = try text(file)
    #expect(await store.save(name: "claude-work", draft: draft) == false)
    #expect(store.editProblem?.hasPrefix("Auto-compact after") == true)
    #expect(try text(file) == saved)

    // remove: refused while named, says who; a free one is written
    #expect(await store.remove(name: "claude") == false)
    #expect(store.editProblem == "claude is used by Author, Chat agent claude, so it stays. Point those at another account first.")
    #expect(try providers(file).keys.contains("claude"))
    #expect(await store.remove(name: "claude-work"))
    await store.settled()
    #expect(try providers(file).keys.sorted() == ["agy", "claude", "codex"])
    #expect(store.editProblem == nil)
    uses = [:]
    #expect(await store.remove(name: "claude"))
    await store.settled()
    #expect(try providers(file).keys.sorted() == ["agy", "codex"])
}

@MainActor @Test func whenTheHostAnswersAProblemAfterASaveThePageSaysItWithTheKeyAndTheFileStaysAsWritten() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(base)
    let host = try ProvidersHost(replyJSON(accounts: []))
    host.reply = try JSONDecoder().decode(HostProviders.self, from: Data(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"providers.codex.model","message":"Invalid input"}}"#.utf8))
    let store = makeStore(host, file)
    var draft = AccountDraft()
    draft.displayName = "Mine"
    #expect(await store.save(name: "codex", draft: draft))
    await store.settled()
    #expect(try providers(file)["codex"]?["displayName"] as? String == "Mine")
    #expect(store.outcome.note?.contains("providers.codex.model") == true && store.outcome.note?.contains("Invalid input") == true)
}

@MainActor @Test func aChatJsonThatCannotBeReadStopsARemoval() async throws {
    struct Unreadable: Error {}
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(base)
    let store = makeStore(try ProvidersHost(replyJSON(accounts: [])), file, uses: { throw Unreadable() })
    #expect(await store.remove(name: "codex") == false)
    #expect(try providers(file).keys.contains("codex"))
    #expect(store.editProblem == "providers.json could not be written; the file stays as it was.")
}

// MARK: what the engine did with the file

private var work: AccountDraft {
    var draft = AccountDraft()
    draft.displayName = "Work"
    return draft
}

@MainActor @Test func everyChangeOfProvidersJsonIsOneRequestAndOnlyOneThatWroteTheFileGetsTheEnginesAnswer() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = makeStore(host, file)

    // the first open makes the file, one account per harness found
    let first = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    await makeStore(first, file).createFileIfMissing()
    #expect(first.requests == [.setAccounts([DetectedAccount(name: "claude", harness: "claude")])] && first.engineAsks == 1)
    // a file there already: the first open asks for nothing
    await store.createFileIfMissing()
    #expect(host.requests.isEmpty)

    await store.add(harness: "agy")
    #expect(host.requests == [.setAccounts([DetectedAccount(name: "agy", harness: "agy")])] && host.engineAsks == 1 && store.addProblem == nil)
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw"))
    await store.settled()
    #expect(await store.save(name: "claude-work", draft: work))
    await store.settled()
    #expect(await store.remove(name: "claude-work"))
    await store.settled()
    #expect(host.requests.count == 4 && host.engineAsks == 4 && store.editProblem == nil)
    #expect(host.requests.suffix(3) == [.addAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw"), .editAccount(name: "claude-work", draft: work), .removeAccount(name: "claude-work")])
    // an account that is taken, one that is missing: the request was refused and the engine was not asked
    #expect(await store.addAccount(name: "agy", harness: "claude", configDir: "") == false)
    #expect(await store.remove(name: "ghost") == false)
    await store.add(harness: "agy")
    #expect(host.requests.count == 7 && host.engineAsks == 4)
    // a write that failed
    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    await makeStore(host, failing).add(harness: "codex")
    #expect(host.engineAsks == 4)
}

@MainActor @Test func anEngineThatRefusesWhatWasWrittenIsShownWhereTheFailureToSaveIsShownAndTheLastSaveDecides() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let kept = ReloadOutcome.refused(Refusal(code: "config.problem", params: ["path": "agents.author.provider", "problem": "providerNotDeclared"], text: "agents.author.provider: bad"))
    let store = makeStore(host, file, engine: kept)

    await store.add(harness: "agy")
    // the row leaves "Found, not added" once the host is asked again, so the words are the editProblem the accounts show, not the Add button's
    #expect(store.editProblem == "Saved, but Carrier kept its settings: agents.author.provider: bad" && store.addProblem == nil)
    #expect(try providers(file).keys.sorted() == ["agy", "claude"])
    // the editor closes on a save that was written; its words are left for the page
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: ""))
    await store.settled()
    #expect(store.editProblem == "Saved, but Carrier kept its settings: agents.author.provider: bad")
    // a later save the engine applied clears it
    host.engine = .applied
    #expect(await store.save(name: "claude-work", draft: work))
    await store.settled()
    #expect(store.editProblem == nil)
}

@MainActor @Test func theEnginesAnswerIsKeptWhereEveryPageOfSettingsReadsIt() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    let status = ReloadStatus()
    host.file = file
    host.engine = .refused(.words("bad"))
    let store = ProvidersStore(host: host, file: { file }, log: { _ in }, status: status)
    #expect(await store.save(name: "claude", draft: work))
    #expect(status.outcome == .refused(.words("bad")) && status.isProblem)
    // the newest answer is the one kept
    host.engine = .applied
    var again = work
    again.displayName = "Work 2"
    #expect(await store.save(name: "claude", draft: again))
    #expect(status.outcome == .applied && status.isProblem == false && store.editProblem == nil)
    await store.settled()
}

@MainActor @Test func aRequestTheHostRefusedSaysWhyAndDoesNotKeepTheEnginesWordsOfAnEarlierOne() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"},"codex":{"harness":"codex"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    let store = makeStore(host, file, uses: { ["codex": [.role(.author)]] }, engine: .refused(.words("bad")))

    // Save is written and the engine kept its settings; Remove is refused before it writes anything, and says so
    #expect(await store.save(name: "claude", draft: work))
    #expect(store.editProblem?.hasSuffix("bad") == true)
    #expect(await store.remove(name: "codex") == false)
    #expect(store.editProblem?.contains("so it stays") == true)
    await store.settled()
    #expect(host.engineAsks == 1 && store.editProblem?.contains("so it stays") == true)
}

@MainActor @Test func aRequestThatFailedForAnotherReasonThanARefusalIsLoggedAndSaysTheFileStaysAsItWas() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    var logged: [String] = []
    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let store = makeStore(host, failing, log: { logged.append($0) })
    #expect(await store.save(name: "claude", draft: work) == false)
    #expect(store.editProblem == "providers.json could not be written; the file stays as it was." && logged.count == 1 && logged[0].contains("save claude"))
    // no host running and no carrier to run: nothing can write the file
    let none = ProvidersStore(host: SocketChatHost(socketPath: { "/tmp/cc-none-\(UUID().uuidString.prefix(8)).sock" }), file: { file }, log: { logged.append($0) }, status: ReloadStatus())
    #expect(await none.remove(name: "claude") == false)
    #expect(none.editProblem?.contains("does not support") == true)
}

@MainActor @Test func anOlderEngineThatDoesNotReloadSaysNothingAndARefusalIsAProblem() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = makeStore(host, file, engine: .unsupported)

    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: ""))
    await store.settled()
    // an engine that is not running (or an older one) is told to nobody: nothing to show, problem or note
    #expect(store.editProblem == nil && store.editNote == nil)
    // a refusal is a problem, an engine that did not answer too, and the next save the engine applied clears both
    host.engine = .refused(.words("agents.author.provider: bad"))
    #expect(await store.save(name: "claude-work", draft: work))
    await store.settled()
    #expect(store.editProblem?.hasSuffix("agents.author.provider: bad") == true && store.editNote == nil)
    host.engine = .noAnswer
    #expect(await store.save(name: "claude-work", draft: work))
    #expect(store.editProblem == "Saved, but Carrier did not answer: it may not have applied it.")
    host.engine = .applied
    _ = await store.save(name: "claude-work", draft: work)
    await store.settled()
    #expect(store.editProblem == nil && store.editNote == nil)
}

// MARK: the text generator

private func object(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }

@Test func choosingATextGeneratorWritesOneEntryByNameAndKeepsEveryOtherKey() throws {
    let existing = Data(#"{"future":{"a":1},"providers":{"claude":{"harness":"claude","newKey":true}},"textGenerators":{"mine":{"kind":"ollama","model":"x"}}}"#.utf8)
    let json = try object(applyingTextGenerator((server: "ollama", model: "qwen3:8b"), to: existing))
    #expect((json["future"] as? [String: Int]) == ["a": 1])
    #expect((json["providers"] as? [String: [String: Any]])?["claude"]?["newKey"] as? Bool == true)
    let generators = try #require(json["textGenerators"] as? [String: [String: String]])
    // the one the person wrote by hand stays, the app's is named after the server
    #expect(generators == ["mine": ["kind": "ollama", "model": "x"], "ollama": ["kind": "ollama", "model": "qwen3:8b"]])
    #expect(json["textGenerator"] as? String == "ollama")
}

@Test func choosingAnotherReplacesWhatTheAppWroteAndNeverTouchesTheProvidersMap() throws {
    let first = try applyingTextGenerator((server: "ollama", model: "qwen3:8b"), to: nil)
    // a file with no providers key stays without it: the engine has its defaults then
    #expect(try object(first)["providers"] == nil)
    let second = try object(applyingTextGenerator((server: "lmstudio", model: "gemma"), to: first))
    #expect((second["textGenerators"] as? [String: [String: String]]) == ["lmstudio": ["kind": "lmstudio", "model": "gemma"]])
    #expect(second["textGenerator"] as? String == "lmstudio")
    // another model of the same server replaces the model
    let third = try object(applyingTextGenerator((server: "lmstudio", model: "llama"), to: try applyingTextGenerator((server: "lmstudio", model: "gemma"), to: nil)))
    #expect((third["textGenerators"] as? [String: [String: String]]) == ["lmstudio": ["kind": "lmstudio", "model": "llama"]])
}

@Test func clearingRemovesTheChoiceAndTheEntryTheAppWroteAndKeepsTheRest() throws {
    let chosen = try applyingTextGenerator((server: "ollama", model: "qwen3:8b"), to: Data(#"{"future":1,"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let cleared = try object(applyingTextGenerator(nil, to: chosen))
    #expect(cleared["textGenerator"] == nil && cleared["textGenerators"] == nil)
    #expect(cleared["future"] as? Int == 1 && (cleared["providers"] as? [String: Any])?.keys.sorted() == ["claude"])
    // an entry the person wrote stays, only the choice goes
    let mine = Data(#"{"textGenerators":{"local":{"kind":"ollama","model":"x"}},"textGenerator":"local"}"#.utf8)
    let kept = try object(applyingTextGenerator(nil, to: mine))
    #expect(kept["textGenerator"] == nil && (kept["textGenerators"] as? [String: [String: String]]) == ["local": ["kind": "ollama", "model": "x"]])
}

@Test func aFileTheAppCannotReadIsNeverOverwrittenByATextGeneratorChoice() throws {
    for bad in ["[1]", "not json", #"{"textGenerators":[]}"#, #"{"textGenerators":"x"}"#] {
        #expect(throws: ProvidersFileError.notAnObject) { try applyingTextGenerator((server: "ollama", model: "m"), to: Data(bad.utf8)) }
        #expect(throws: ProvidersFileError.notAnObject) { try applyingTextGenerator(nil, to: Data(bad.utf8)) }
    }
    // a server or model the engine would refuse is never written
    for bad in [(server: "openai", model: "m"), (server: "ollama", model: "  ")] {
        #expect(throws: (any Error).self) { try applyingTextGenerator(bad, to: nil) }
    }
}

@MainActor @Test func theTextGeneratorIsWrittenAndTheEngineAskedOnlyWhileTheHostListsIt() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let mine = #"{"providers":{"codex":{"harness":"codex"}},"extra":1}"#
    try file.write(Data(mine.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("codex", found: true)]))
    let store = makeStore(host, file)
    await store.load()
    #expect(store.generatorEditable == false)
    // an older host would refuse the keys: nothing is asked, nothing is written, and the page says why
    #expect(await store.chooseTextGenerator((server: "ollama", model: "qwen3:8b")) == false)
    #expect(try text(file) == mine && host.requests.isEmpty && store.editProblem?.contains("Update") == true)
    host.capabilitiesAnswer = [.providers, .textGenerators]
    await store.load()
    #expect(store.generatorEditable)
    #expect(await store.chooseTextGenerator((server: "ollama", model: "qwen3:8b")))
    await store.settled()
    #expect(host.requests == [.setTextGenerator(TextGeneratorChoice(server: "ollama", model: "qwen3:8b"))] && host.engineAsks == 1 && store.editProblem == nil)
    let json = try object(try #require(try file.read()))
    #expect(json["textGenerator"] as? String == "ollama" && json["extra"] as? Int == 1)
    // the engine's refusal is shown with the key it names
    let refusing = makeStore(host, file, engine: .refused(.words("textGenerator: \"x\" is not declared in textGenerators")))
    await refusing.load()
    #expect(await refusing.chooseTextGenerator(nil))
    await refusing.settled()
    #expect(refusing.editProblem?.contains("textGenerator:") == true)
    host.capabilitiesAnswer = []
    await store.load()
    #expect(store.generatorEditable == false)
}

@MainActor @Test func theChosenGeneratorIsReadFromTheHostAsSoonAsTheRequestIsAnswered() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let host = try ProvidersHost(replyJSON(accounts: [account("codex", found: true)]))
    host.capabilitiesAnswer = [.providers, .textGenerators]
    let store = makeStore(host, file)
    await store.load()
    #expect(await store.chooseTextGenerator((server: "ollama", model: "qwen3:8b")))
    // the page shows the choice the moment the file is written: the host was asked again before the call gave back
    #expect(host.asked == 2)
    await store.settled()
    #expect(host.asked == 2)
}

@MainActor @Test func earlierTitlesActionIsGatedByCapabilityAndReportsStartedZeroOrRefusal() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let host = try ProvidersHost(replyJSON(accounts: [account("codex", found: true)]))
    let store = makeStore(host, file)

    // without regenerateTitles in hello, nothing is asked
    host.capabilitiesAnswer = [.providers, .textGenerators]
    await store.load()
    #expect(store.canRegenerateTitles == false)
    await store.regenerateTitles()
    #expect(host.regenerateTitlesCalls == 0 && store.retitleOutcome == nil)

    // with regenerateTitles in hello, started count, 0, and refusal are recorded
    host.capabilitiesAnswer = [.providers, .textGenerators, .regenerateTitles]
    await store.load()
    #expect(store.canRegenerateTitles)
    host.regenerateTitlesResult = .success(3)
    await store.regenerateTitles()
    #expect(host.regenerateTitlesCalls == 1 && store.retitleOutcome == .started(3))
    #expect(store.retitleOutcome?.words == "Started 3 sessions in the background")

    host.regenerateTitlesResult = .success(0)
    await store.regenerateTitles()
    #expect(store.retitleOutcome == .started(0))
    #expect(store.retitleOutcome?.words == "Nothing to title: every session already has a title")

    host.regenerateTitlesResult = .failure(ControlError.remote(.words("Could not write titles: no text generator is chosen; choose one in Providers")))
    await store.regenerateTitles()
    #expect(store.retitleOutcome == .refused("Could not write titles: no text generator is chosen; choose one in Providers"))

    // changing the generator or dismissing clears the previous outcome
    #expect(await store.chooseTextGenerator((server: "ollama", model: "qwen3:8b")))
    #expect(store.retitleOutcome == nil)
    await store.regenerateTitles()
    #expect(store.retitleOutcome != nil)
    store.dismissProblem()
    #expect(store.retitleOutcome == nil)

    // losing the capability clears it too
    host.regenerateTitlesResult = .success(1)
    await store.regenerateTitles()
    #expect(store.retitleOutcome == .started(1))
    host.capabilitiesAnswer = [.providers, .textGenerators]
    await store.load()
    #expect(store.canRegenerateTitles == false && store.retitleOutcome == nil)
}

@MainActor @Test func labelIconAndColorAreOfferedOnlyWhileTheHostSaysItKnowsThem() async throws {
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    let store = makeStore(host, ProvidersFile(folder: NSTemporaryDirectory() + "carrier-none"))
    #expect(store.identityEditable == false)
    // a host that lists providers but not accountIdentity is an older carrier: it would refuse the file with the keys in it
    await store.load()
    #expect(store.identityEditable == false)
    host.capabilitiesAnswer = [.providers, .accountIdentity]
    await store.load()
    #expect(store.identityEditable && store.paletteEditable == false)
    // the later icons and colors need their own word, or the older host would refuse the whole file
    host.capabilitiesAnswer = [.providers, .accountIdentity, .accountPalette]
    await store.load()
    #expect(store.identityEditable && store.paletteEditable)
    host.capabilitiesAnswer = []
    await store.load()
    #expect(store.identityEditable == false && store.paletteEditable == false)
}

@Test func aFolderAnotherAccountOfTheSameToolHasIsNamedAndNothingElseIs() {
    let file = Data(#"{"providers":{"teams":{"harness":"claude","configDir":"~/.claude-lab"},"pro":{"harness":"claude","configDir":"/h/.claude"},"codex-work":{"harness":"codex","configDir":"~/.claude-lab"},"claude":{"harness":"claude"}}}"#.utf8)
    let home = NSHomeDirectory()
    #expect(accountSharingFolder(configDir: "~/.claude-lab", harness: "claude", in: file) == "teams")
    #expect(accountSharingFolder(configDir: home + "/.claude-lab/", harness: "claude", in: file) == "teams")
    #expect(accountSharingFolder(configDir: ".claude-lab", harness: "claude", in: file) == "teams")
    #expect(accountSharingFolder(configDir: "~/.claude-lab", harness: "claude", except: "teams", in: file) == nil)
    #expect(accountSharingFolder(configDir: "~/.claude-lab-lu", harness: "claude", in: file) == nil)
    #expect(accountSharingFolder(configDir: "~/.claude-lab", harness: "codex", in: file) == "codex-work")
    #expect(accountSharingFolder(configDir: "", harness: "claude", in: file) == nil)
    #expect(accountSharingFolder(configDir: "~/.claude-lab", harness: "claude", in: nil) == nil)
    #expect(accountSharingFolder(configDir: "~/.claude-lab", harness: "claude", in: Data("not json".utf8)) == nil)
}

@Test func anAccountWithNoFolderHasTheToolsOwnAndTheNoteNamesItByItsDisplayName() {
    let file = Data(#"{"providers":{"claude":{"harness":"claude"},"codex":{"harness":"codex","displayName":"Codex Pro"},"empty":{"harness":"claude","configDir":""}}}"#.utf8)
    #expect(accountSharingFolder(configDir: "~/.claude", harness: "claude", in: file) == "claude")
    #expect(accountSharingFolder(configDir: NSHomeDirectory() + "/.codex", harness: "codex", in: file) == "Codex Pro")
    #expect(accountSharingFolder(configDir: "~/.claude", harness: "claude", except: "claude", in: file) == "empty")
    #expect(accountSharingFolder(configDir: "~/.codex", harness: "claude", in: file) == nil)
    #expect(accountSharingFolder(configDir: "/", harness: "agy", in: file) == nil)
}
