import Foundation
import Testing
@testable import CarrierCore

// The app's writing of providers.json (docs/adr/0020): unknown keys kept, the file written whole, a failed write leaving the old one, the
// first-open creation and the "found, not added" rule, over a temporary folder and a fake chat host.

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

    init(_ json: String) throws { reply = try JSONDecoder().decode(HostProviders.self, from: Data(json.utf8)) }

    func capabilities() async throws -> Set<ControlClient.Capability> { capabilitiesAnswer }
    func providers() async throws -> HostProviders { asked += 1; return reply }

    func agents() async throws -> [ChatAgent] { [] }
    func open(plan: SessionPlan) async throws -> String { "" }
    func workspace(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func fetch(_ folder: String) async throws -> WorkspaceInfo { WorkspaceInfo(folder: folder, git: false) }
    func suggestName(_ folder: String) async throws -> String { "" }
    func checkName(_ folder: String, _ name: String) async throws -> NameCheck { NameCheck(valid: true, free: true) }
    func list(archived: Bool) async throws -> [ChatSession] { [] }
    func resume(_ id: String) async throws {}
    func send(_ id: String, _ text: String) async throws {}
    func send(_ id: String, _ text: String, command: String?) async throws {}
    func interrupt(_ id: String) async throws {}
    func archive(_ id: String, _ archived: Bool) async throws {}
    func delete(_ id: String) async throws {}
    func cloneRepo(_ repo: String) async throws -> ClonedRepo { throw ControlError.closed }
    func createProject(_ name: String) async throws -> String { throw ControlError.closed }
    func githubRepos(page: Int) async throws -> GithubReposPage { throw ControlError.closed }
    func deletePreview(_ ids: [String]) async throws -> [SessionDeletePreview] { [] }
    func answer(_ id: String, approval: String, choice: String, answers: [String: String]?) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: [], commands: []) }
    func setOption(_ id: String, option: String, value: String) async throws {}
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
    let store = ProvidersStore(host: host, file: { file }, log: { _ in }, reload: { .applied })
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
    let store = ProvidersStore(host: host, file: { file }, log: { _ in }, reload: { .applied })
    await store.createFileIfMissing()
    #expect(try text(file) == mine && host.asked == 0)
}

@MainActor @Test func theFirstOpenWritesNothingWhenTheHostCannotAnswerOrFoundNothingOrTheFileDoesNotMatch() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let none = try ProvidersHost(replyJSON(accounts: [account("claude", found: false)]))
    await ProvidersStore(host: none, file: { file }, log: { _ in }, reload: { .applied }).createFileIfMissing()
    let old = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    old.capabilitiesAnswer = []
    await ProvidersStore(host: old, file: { file }, log: { _ in }, reload: { .applied }).createFileIfMissing()
    let problem = try ProvidersHost(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"(file)","message":"bad"}}"#)
    await ProvidersStore(host: problem, file: { file }, log: { _ in }, reload: { .applied }).createFileIfMissing()
    #expect(file.exists == false)
}

@MainActor @Test func addWritesTheAccountAndAnAccountRemovedLaterIsNotBroughtBackByTheNextOpen() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude","command":"/opt/claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = ProvidersStore(host: host, file: { file }, log: { _ in }, reload: { .applied })
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
    let store = ProvidersStore(host: host, file: { file }, log: { _ in }, reload: { .applied })

    try file.write(Data("[1]".utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem?.contains("not a JSON object") == true)
    #expect(try text(file) == "[1]")

    try file.write(Data(#"{"providers":{"codex":{"harness":"claude"}}}"#.utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem == "There is already an account named codex.")

    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let stuck = ProvidersStore(host: host, file: { failing }, log: { _ in }, reload: { .applied })
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
    let store = ProvidersStore(host: host, file: { file }, uses: { uses }, log: { _ in }, reload: { .applied })

    // add: written, and the host asked again
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw"))
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
    #expect(try providers(file).keys.sorted() == ["agy", "claude", "codex"])
    #expect(store.editProblem == nil)
    uses = [:]
    #expect(await store.remove(name: "claude"))
    #expect(try providers(file).keys.sorted() == ["agy", "codex"])
}

@MainActor @Test func whenTheHostAnswersAProblemAfterASaveThePageSaysItWithTheKeyAndTheFileStaysAsWritten() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(base)
    let host = try ProvidersHost(replyJSON(accounts: []))
    host.reply = try JSONDecoder().decode(HostProviders.self, from: Data(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"providers.codex.model","message":"Invalid input"}}"#.utf8))
    let store = ProvidersStore(host: host, file: { file }, uses: { [:] }, log: { _ in }, reload: { .applied })
    var draft = AccountDraft()
    draft.displayName = "Mine"
    #expect(await store.save(name: "codex", draft: draft))
    #expect(try providers(file)["codex"]?["displayName"] as? String == "Mine")
    #expect(store.outcome.note?.contains("providers.codex.model") == true && store.outcome.note?.contains("Invalid input") == true)
}

@MainActor @Test func aChatJsonThatCannotBeReadStopsARemoval() async throws {
    struct Unreadable: Error {}
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(base)
    let store = ProvidersStore(host: try ProvidersHost(replyJSON(accounts: [])), file: { file }, uses: { throw Unreadable() }, log: { _ in }, reload: { .applied })
    #expect(await store.remove(name: "codex") == false)
    #expect(try providers(file).keys.contains("codex"))
    #expect(store.editProblem == "providers.json could not be written; the file stays as it was.")
}

// MARK: the engine is asked to reload

private var work: AccountDraft {
    var draft = AccountDraft()
    draft.displayName = "Work"
    return draft
}

@MainActor @Test func everyWriteOfProvidersJsonAsksTheEngineToReloadAfterItAndAFailedOneAsksNothing() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let engine = FakeReload(file: file.url.path)
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = ProvidersStore(host: host, file: { file }, uses: { [:] }, log: { _ in }, reload: engine.reload)

    // the first open makes the file, one account per harness found
    let first = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    await ProvidersStore(host: first, file: { file }, log: { _ in }, reload: engine.reload).createFileIfMissing()
    #expect(engine.calls == 1 && engine.seen[0] == engine.now)
    // a file there already: the first open writes nothing and asks nothing
    await store.createFileIfMissing()
    #expect(engine.calls == 1)

    await store.add(harness: "agy")
    #expect(engine.calls == 2 && engine.seen[1] == engine.now && store.addProblem == nil)
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: "/h/.cw") && engine.calls == 3)
    #expect(await store.save(name: "claude-work", draft: work) && engine.calls == 4)
    #expect(await store.remove(name: "claude-work") && engine.calls == 5 && store.editProblem == nil)
    // an account that is taken, one that is missing: nothing was written
    #expect(await store.addAccount(name: "agy", harness: "claude", configDir: "") == false)
    #expect(await store.remove(name: "ghost") == false)
    await store.add(harness: "agy")
    #expect(engine.calls == 5)
    // a write that failed
    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let stuck = ProvidersStore(host: host, file: { failing }, log: { _ in }, reload: engine.reload)
    await stuck.add(harness: "codex")
    #expect(engine.calls == 5)
}

@MainActor @Test func anEngineThatRefusesWhatWasWrittenIsShownWhereTheFailureToSaveIsShownAndTheLastSaveDecides() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let engine = FakeReload(file: file.url.path, problem: "agents.author.provider: bad")
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = ProvidersStore(host: host, file: { file }, uses: { [:] }, log: { _ in }, reload: engine.reload)

    await store.add(harness: "agy")
    // the row leaves "Found, not added" once the host is asked again, so the words are the editProblem the accounts show, not the Add button's
    #expect(store.editProblem == "Saved, but Carrier kept its settings: agents.author.provider: bad" && store.addProblem == nil)
    #expect(try providers(file).keys.sorted() == ["agy", "claude"])
    // the editor closes on a save that was written; its words are left for the page
    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: ""))
    #expect(store.editProblem == "Saved, but Carrier kept its settings: agents.author.provider: bad")
    // a later save the engine applied clears it
    engine.problem = nil
    #expect(await store.save(name: "claude-work", draft: work))
    #expect(store.editProblem == nil)
}

@MainActor @Test func anOlderEngineThatDoesNotReloadIsAPlainNoteNotAProblemAndLeavingThePageClearsWhatItSaid() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    var answer = ReloadOutcome.unsupported
    let store = ProvidersStore(host: host, file: { file }, uses: { [:] }, log: { _ in }, reload: { answer })

    #expect(await store.addAccount(name: "claude-work", harness: "claude", configDir: ""))
    #expect(store.editProblem == nil && store.editNote == "Saved. This Carrier does not apply it while it runs: it will read the file when it starts.")
    // the person leaves the page: nothing of it stays for the next visit
    store.dismissProblem()
    #expect(store.editProblem == nil && store.editNote == nil)
    // a refusal is a problem, and the next save the engine applied clears both
    answer = .refused("agents.author.provider: bad")
    #expect(await store.save(name: "claude-work", draft: work))
    #expect(store.editProblem?.hasSuffix("agents.author.provider: bad") == true && store.editNote == nil)
    answer = .applied
    _ = await store.save(name: "claude-work", draft: work)
    #expect(store.editProblem == nil && store.editNote == nil)
}
