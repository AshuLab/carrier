import Foundation
import Testing
@testable import CarrierCore

// Changing a global role from the Agents page: what is written to a temporary config.json, and what is refused before writing.

private let accounts = ["claude", "codex", "agy"]
private let bots = ["acme-author", "acme-reviewer", "spare"]
private let base = #"""
{"keep": {"deep": [1, 2]}, "orchestratorProfile": "acme-author",
 "profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "acme-reviewer": {"kind": "forge", "agent": "acme-reviewer"}, "me": {"kind": "gh"}},
 "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m", "effort": "high", "persona": {"name": "Ada", "x": 1}, "extra": true},
            "reviewer": {"profile": "acme-reviewer", "provider": "codex", "model": "g"}},
 "failover": {"roles": {"author": [{"provider": "codex"}]}},
 "repos": [{"name": "a/b"}]}
"""#

private func temporaryConfig(_ text: String = base) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-global-role-\(UUID().uuidString).json"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func file(_ path: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
}

private func role(_ path: String, _ name: String) throws -> [String: Any] {
    try #require((file(path)["agents"] as? [String: Any])?[name] as? [String: Any])
}

private func save(_ change: RoleChange, _ role: AgentRole = .author, path: String) -> RoleSave {
    saveGlobalRole(change, role: role, path: path, accounts: accounts, bots: bots, reload: { .applied })
}

@Test func changingOneFieldWritesOnlyThatRolesKeyAndKeepsEverythingElse() throws {
    let path = try temporaryConfig()
    let before = try file(path)
    #expect(save(.model("gpt-5"), path: path) == .saved)
    var expected = before
    var agents = try #require(expected["agents"] as? [String: Any])
    var author = try #require(agents["author"] as? [String: Any])
    author["model"] = "gpt-5"
    agents["author"] = author
    expected["agents"] = agents
    #expect(try NSDictionary(dictionary: file(path)).isEqual(to: expected))
}

@Test func aGlobalRoleSaveReadsTheFileAgainSoAnotherWritersChangeSurvives() throws {
    let path = try temporaryConfig()
    // the page read the file; another writer (the Behavior tab, a hand edit) changes it before the save
    try base.replacingOccurrences(of: #""keep""#, with: #""pollIntervalMinutes": 9, "keep""#).write(toFile: path, atomically: true, encoding: .utf8)
    #expect(save(.effort("max"), .reviewer, path: path) == .saved)
    #expect(try file(path)["pollIntervalMinutes"] as? Int == 9)
    #expect(try role(path, "reviewer")["effort"] as? String == "max")
}

@Test func effortIsOneOfTheFiveLevelsOrNone() throws {
    let path = try temporaryConfig()
    #expect(save(.effort(nil), path: path) == .saved)
    #expect(try role(path, "author")["effort"] == nil)
    guard case .refused(let reason) = save(.effort("Max"), path: path) else { Issue.record("expected a refusal"); return }
    #expect(reason.contains("Effort must be one of"))
}

@Test func choosingABotAddsItsProfileOnceAndChoosingItAgainReusesIt() throws {
    let path = try temporaryConfig()
    #expect(save(.bot("spare"), path: path) == .saved)
    #expect(try role(path, "author")["profile"] as? String == "spare")
    #expect(try (file(path)["profiles"] as? [String: Any])?["spare"] as? [String: String] == ["kind": "forge", "agent": "spare"])
    #expect(save(.bot("spare"), .reviewer, path: path) == .saved)
    #expect(save(.bot("acme-reviewer"), path: path) == .saved)
    let profiles = try #require(file(path)["profiles"] as? [String: Any])
    #expect(profiles.keys.sorted() == ["acme-author", "acme-reviewer", "me", "spare"])
    #expect(try role(path, "author")["profile"] as? String == "acme-reviewer")
}

@Test func aBotWhoseNameIsTakenByAnotherProfileGetsAFreeName() throws {
    let path = try temporaryConfig(base.replacingOccurrences(of: #""me": {"kind": "gh"}"#, with: #""spare": {"kind": "gh"}"#))
    #expect(save(.bot("spare"), path: path) == .saved)
    #expect(try role(path, "author")["profile"] as? String == "spare-2")
    #expect(try (file(path)["profiles"] as? [String: Any])?["spare-2"] as? [String: String] == ["kind": "forge", "agent": "spare"])
}

@Test func thePersonsLoginUsesTheGhProfileAndAddsOneWhenThereIsNone() throws {
    let path = try temporaryConfig()
    #expect(save(.gh, path: path) == .saved)
    #expect(try role(path, "author")["profile"] as? String == "me")
    let without = try temporaryConfig(base.replacingOccurrences(of: #", "me": {"kind": "gh"}"#, with: ""))
    #expect(save(.gh, path: without) == .saved)
    #expect(try role(without, "author")["profile"] as? String == "gh")
    #expect(try (file(without)["profiles"] as? [String: Any])?["gh"] as? [String: String] == ["kind": "gh"])
}

@Test func anEmptyModelOrAnUndeclaredProviderOrBotIsRefusedWithTheReasonAndNothingIsWritten() throws {
    let path = try temporaryConfig()
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    #expect(save(.model("   "), path: path) == .refused("The model cannot be empty."))
    guard case .refused(let provider) = save(.provider("ghost"), path: path) else { Issue.record("expected a refusal"); return }
    #expect(provider.contains("ghost") && provider.contains("providers.json"))
    guard case .refused(let bot) = save(.bot("ghost"), path: path) else { Issue.record("expected a refusal"); return }
    #expect(bot.contains("ghost") && bot.contains("Agent Forge"))
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
}

@Test func aRoleKeepsItsThreeRequiredFields() throws {
    let path = try temporaryConfig(base.replacingOccurrences(of: #""provider": "codex", "model": "g""#, with: #""provider": "codex""#))
    guard case .refused(let reason) = save(.effort("low"), .reviewer, path: path) else { Issue.record("expected a refusal"); return }
    #expect(reason.contains("needs an identity, a provider and a model") || reason.contains("model"))
    #expect(try role(path, "reviewer")["effort"] == nil)
    // a role the file does not have (the lead reviewer while it is off) is not made by changing one field
    guard case .refused(let off) = save(.model("x"), .leadReviewer, path: path) else { Issue.record("expected a refusal"); return }
    #expect(off.contains("Lead reviewer"))
    #expect(try role(path, "author")["model"] as? String == "m")
}

@Test func theSamePersonAsAuthorAndReviewerIsWrittenOnBothRolesAndTheSignatureNoteShows() throws {
    let path = try temporaryConfig()
    #expect(save(.bot("spare"), .author, path: path) == .saved)
    #expect(save(.bot("spare"), .reviewer, path: path) == .saved)
    let names = ForgeBots(names: bots, note: nil)
    let shown = try #require(agentsPage(config: Data(contentsOf: URL(fileURLWithPath: path)), providers: nil, bots: names))
    #expect(shown.sharedNote == "Author and Reviewer both work as spare: the signature will show it.")

    // two profile names for the same bot are one account too
    let twoNames = try temporaryConfig(base.replacingOccurrences(of: #""me": {"kind": "gh"}"#, with: #""again": {"kind": "forge", "agent": "acme-author"}"#))
    var written = try file(twoNames)
    var agents = try #require(written["agents"] as? [String: Any])
    var reviewer = try #require(agents["reviewer"] as? [String: Any])
    reviewer["profile"] = "again"
    agents["reviewer"] = reviewer
    written["agents"] = agents
    let data = try JSONSerialization.data(withJSONObject: written)
    let page = try #require(agentsPage(config: data, providers: nil, bots: names))
    #expect(page.sharedNote?.contains("are one account") == true)
}

// MARK: the engine is asked to reload

@Test func aSavedRoleAsksTheEngineToReloadAfterTheWriteAndNeverAfterAFailedOne() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path)
    #expect(saveGlobalRole(.model("gpt-5"), role: .author, path: path, accounts: accounts, bots: bots, reload: engine.reload) == .saved)
    #expect(engine.calls == 1 && engine.seen[0] == engine.now)
    #expect(try role(path, "author")["model"] as? String == "gpt-5")
    // refused before writing, or a file that is not there: nothing is asked
    #expect(saveGlobalRole(.provider("nope"), role: .author, path: path, accounts: accounts, bots: bots, reload: engine.reload) != .saved)
    #expect(saveGlobalRole(.model("m"), role: .author, path: path + ".missing", accounts: accounts, bots: bots, reload: engine.reload) != .saved)
    #expect(engine.calls == 1)
}

@Test func aRoleTheEngineRefusedToApplyStaysSaved() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path, problem: "agents.author.model: must not be empty")
    let result = saveGlobalRole(.model("gpt-5"), role: .author, path: path, accounts: accounts, bots: bots, reload: engine.reload)
    #expect(result == .saved && result.problem == nil)
    #expect(try role(path, "author")["model"] as? String == "gpt-5")
}
