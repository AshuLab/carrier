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
    #expect(map["codex"]?["harness"] as? String == "codex" && map["codex"]?["enabled"] as? Bool == false)
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
    func answer(_ id: String, approval: String, choice: String) async throws {}
    func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents { ChatEvents(events: [], cursor: after, options: [], commands: []) }
    func setOption(_ id: String, option: String, value: String) async throws {}
}

private func account(_ name: String, found: Bool) -> String {
    #"{"name":"\#(name)","harness":"\#(name)","enabled":false,"found":\#(found),"state":"\#(found ? "ready" : "missing")"}"#
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
    let store = ProvidersStore(host: host, file: { file }, log: { _ in })
    await store.createFileIfMissing()
    let written = try providers(file)
    #expect(written.keys.sorted() == ["claude", "codex"])
    #expect(written.values.allSatisfy { $0["enabled"] as? Bool == false })
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
    let store = ProvidersStore(host: host, file: { file }, log: { _ in })
    await store.createFileIfMissing()
    #expect(try text(file) == mine && host.asked == 0)
}

@MainActor @Test func theFirstOpenWritesNothingWhenTheHostCannotAnswerOrFoundNothingOrTheFileDoesNotMatch() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let none = try ProvidersHost(replyJSON(accounts: [account("claude", found: false)]))
    await ProvidersStore(host: none, file: { file }, log: { _ in }).createFileIfMissing()
    let old = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)]))
    old.capabilitiesAnswer = []
    await ProvidersStore(host: old, file: { file }, log: { _ in }).createFileIfMissing()
    let problem = try ProvidersHost(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"(file)","message":"bad"}}"#)
    await ProvidersStore(host: problem, file: { file }, log: { _ in }).createFileIfMissing()
    #expect(file.exists == false)
}

@MainActor @Test func addWritesTheAccountAndAnAccountRemovedLaterIsNotBroughtBackByTheNextOpen() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    try file.write(Data(#"{"providers":{"claude":{"harness":"claude","command":"/opt/claude"}}}"#.utf8))
    let host = try ProvidersHost(replyJSON(accounts: [account("claude", found: true)], unadded: ["agy"]))
    let store = ProvidersStore(host: host, file: { file }, log: { _ in })
    await store.add(harness: "agy")
    let written = try providers(file)
    #expect(written.keys.sorted() == ["agy", "claude"] && written["agy"]?["enabled"] as? Bool == false)
    #expect(written["claude"]?["command"] as? String == "/opt/claude" && store.addProblem == nil)

    // the person removes claude by hand; opening the app again does not add it back
    try file.write(Data(#"{"providers":{"agy":{"harness":"agy","enabled":false}}}"#.utf8))
    let after = try text(file)
    await store.createFileIfMissing()
    #expect(try text(file) == after)
}

@MainActor @Test func anAddThatCannotWriteSaysWhyAndLeavesTheFileAlone() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let file = ProvidersFile(folder: folder)
    let host = try ProvidersHost(replyJSON(accounts: [], unadded: ["codex"]))
    let store = ProvidersStore(host: host, file: { file }, log: { _ in })

    try file.write(Data("[1]".utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem?.contains("not a JSON object") == true)
    #expect(try text(file) == "[1]")

    try file.write(Data(#"{"providers":{"codex":{"harness":"claude"}}}"#.utf8))
    await store.add(harness: "codex")
    #expect(store.addProblem == "There is already an account named codex.")

    let failing = ProvidersFile(folder: folder, save: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let stuck = ProvidersStore(host: host, file: { failing }, log: { _ in })
    await stuck.add(harness: "agy")
    #expect(stuck.addProblem?.contains("could not be written") == true)
    #expect(try text(file) == #"{"providers":{"codex":{"harness":"claude"}}}"#)
}
