import Foundation
import Testing
@testable import CarrierCore

// Changing and resetting a repo's role: what is written to a temporary config.json, and what is refused before writing.

private let accounts = ["claude", "codex", "agy"]
private let base = #"""
{"keep": {"deep": [1, 2]}, "profiles": {"author": {"kind": "gh"}, "reviewer": {"kind": "gh"}, "other": {"kind": "gh"}},
 "agents": {"author": {"profile": "author", "provider": "claude", "model": "m"}, "reviewer": {"profile": "reviewer", "provider": "codex", "model": "m"}},
 "repos": [{"name": "a/b", "extra": true}, {"name": "c/d"}]}
"""#

private func temporaryConfig(_ text: String = base) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-role-\(UUID().uuidString).json"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func file(_ path: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
}

private func entry(_ path: String, repo: Int = 0, role: String = "reviewer") throws -> [String: Any]? {
    let repos = try #require(file(path)["repos"] as? [[String: Any]])
    return (repos[repo]["agents"] as? [String: Any])?[role] as? [String: Any]
}

@Test func changingOneFieldWritesOnlyThatRolesEntryWithOnlyThatField() throws {
    let path = try temporaryConfig()
    #expect(saveRepoRole(RoleFields(model: "qwen3-coder"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) == .saved)
    let written = try file(path)
    #expect(try entry(path) as? [String: String] == ["model": "qwen3-coder"])
    #expect(try entry(path, repo: 1) == nil)
    let repos = try #require(written["repos"] as? [[String: Any]])
    #expect(repos[0]["extra"] as? Bool == true && repos[0]["name"] as? String == "a/b")
    #expect((written["keep"] as? [String: Any])?["deep"] as? [Int] == [1, 2])
    #expect(written["agents"] as? [String: Any] != nil && written["profiles"] as? [String: Any] != nil)
}

@Test func theFileIsReadAgainJustBeforeWritingSoAnotherWritersChangeSurvives() throws {
    let path = try temporaryConfig()
    let seen = try #require(repoRoles(json: Data(contentsOf: URL(fileURLWithPath: path)), repo: "a/b"))
    #expect(seen.rows.count == 2)
    // another writer (the Behavior tab, a hand edit) changes the file after the page read it
    try base.replacingOccurrences(of: #""keep""#, with: #""pollIntervalMinutes": 9, "keep""#).write(toFile: path, atomically: true, encoding: .utf8)
    #expect(saveRepoRole(RoleFields(effort: "max"), role: .author, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) == .saved)
    #expect(try file(path)["pollIntervalMinutes"] as? Int == 9)
    #expect(try entry(path, role: "author") as? [String: String] == ["effort": "max"])
}

@Test func aFieldLeftAloneIsKeptAndTheOthersAreSet() throws {
    let path = try temporaryConfig()
    _ = saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    _ = saveRepoRole(RoleFields(profile: "other", model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try entry(path) as? [String: String] == ["profile": "other", "model": "a"])
    // clearing the model removes only that key
    _ = saveRepoRole(RoleFields(profile: "other"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try entry(path) as? [String: String] == ["profile": "other"])
}

@Test func aModelOfOnlySpacesIsNotWrittenAndAnEntryThatWouldBeEmptyIsRemoved() throws {
    let path = try temporaryConfig()
    #expect(saveRepoRole(RoleFields(model: "   "), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) == .saved)
    #expect(try entry(path) == nil)
    #expect(try (file(path)["repos"] as? [[String: Any]])?[0]["agents"] == nil)
    _ = saveRepoRole(RoleFields(model: " gpt-5 "), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try entry(path) as? [String: String] == ["model": "gpt-5"])
    _ = saveRepoRole(RoleFields(model: " "), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try entry(path) == nil)
}

@Test func aPersonaWithOnlyANameOrOnlyAPromptIsWrittenAsSuch() throws {
    let path = try temporaryConfig()
    _ = saveRepoRole(RoleFields(persona: RolePersona(name: " Rex ", prompt: "  ")), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect((try entry(path)?["persona"]) as? [String: String] == ["name": "Rex"])
    _ = saveRepoRole(RoleFields(persona: RolePersona(name: "", prompt: "Be strict.")), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect((try entry(path)?["persona"]) as? [String: String] == ["prompt": "Be strict."])
    _ = saveRepoRole(RoleFields(persona: RolePersona(name: " ", prompt: " ")), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try entry(path) == nil)
}

@Test func resetRemovesTheRolesEntryAndLeavesTheOtherRole() throws {
    let path = try temporaryConfig()
    _ = saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    _ = saveRepoRole(RoleFields(model: "b"), role: .author, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(saveRepoRole(nil, role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) == .saved)
    #expect(try entry(path) == nil)
    #expect(try entry(path, role: "author") as? [String: String] == ["model": "b"])
    _ = saveRepoRole(nil, role: .author, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    #expect(try (file(path)["repos"] as? [[String: Any]])?[0]["agents"] == nil)
}

@Test func aNameThatIsNotDeclaredIsRefusedBeforeWritingWithTheReasonInWords() throws {
    let path = try temporaryConfig()
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    let profile = saveRepoRole(RoleFields(profile: "ghost"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied })
    guard case .refused(let reason) = profile else { Issue.record("not refused: \(profile)"); return }
    #expect(reason.contains("ghost") && reason.contains("not declared in profiles"))
    guard case .refused(let account) = saveRepoRole(RoleFields(provider: "ollama"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) else { Issue.record("not refused"); return }
    #expect(account.contains("ollama") && account.contains("providers.json"))
    #expect(saveRepoRole(RoleFields(effort: "ultra"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) != .saved)
    #expect(saveRepoRole(RoleFields(persona: RolePersona(name: String(repeating: "x", count: 41))), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) != .saved)
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
}

@Test func theSameIdentityOnAuthorAndReviewerIsAcceptedAndTheSignatureNoteSaysSo() throws {
    let path = try temporaryConfig()
    let roles = try #require(repoRoles(json: Data(contentsOf: URL(fileURLWithPath: path)), repo: "a/b"))
    #expect(signatureNote(roles.rows) == nil)
    #expect(saveRepoRole(RoleFields(profile: "author"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .applied }) == .saved)
    let after = try #require(repoRoles(json: Data(contentsOf: URL(fileURLWithPath: path)), repo: "a/b"))
    #expect(signatureNote(after.rows)?.contains("signature will show it") == true)
}

@Test func aRepoThatIsNoLongerInTheFileFailsAndAnUnreadableFileFails() throws {
    let path = try temporaryConfig()
    #expect(saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "x/y", path: path, accounts: accounts, reload: { .applied }) == .failed("x/y is no longer in the config file."))
    #expect(saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path + ".missing", accounts: accounts, reload: { .applied }) == .failed("The config file could not be read."))
}

@Test func theAccountsAreThoseOfProvidersJSONOrTheThreeDefaults() {
    #expect(declaredAccounts(providersJSON: nil) == ["claude", "codex", "agy"])
    #expect(declaredAccounts(providersJSON: Data("{}".utf8)) == ["claude", "codex", "agy"])
    #expect(declaredAccounts(providersJSON: Data(#"{"providers":{"work":{"harness":"claude"},"home":{"harness":"codex"}}}"#.utf8)) == ["home", "work"])
}

// MARK: the engine is asked to reload

@Test func aSavedRepoRoleAsksTheEngineToReloadAfterTheWriteAndNeverAfterAFailedOne() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path)
    #expect(saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: engine.reload) == .saved)
    #expect(engine.calls == 1 && engine.seen[0] == engine.now)
    #expect(try entry(path)?["model"] as? String == "a")
    #expect(saveRepoRole(nil, role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: engine.reload) == .saved)
    #expect(engine.calls == 2)
    #expect(try entry(path) == nil)
    // refused, unknown repo, unreadable file: nothing is asked
    #expect(saveRepoRole(RoleFields(provider: "ollama"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: engine.reload) != .saved)
    #expect(saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "x/y", path: path, accounts: accounts, reload: engine.reload) != .saved)
    #expect(saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path + ".missing", accounts: accounts, reload: engine.reload) != .saved)
    #expect(engine.calls == 2)
}

@Test func aRepoRoleTheEngineRefusedToApplyIsSavedAndSaysWhatTheEngineAnswered() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path, problem: "repos.0.agents.reviewer: bad")
    let result = saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: engine.reload)
    #expect(result == .notApplied("Saved, but Carrier kept its settings: repos.0.agents.reviewer: bad") && result.isWritten)
    #expect(try entry(path)?["model"] as? String == "a")
}

@Test func eachAccountGetsTheIconOfTheHarnessItRuns() {
    let json = #"{"providers":{"pro":{"harness":"claude"},"codex":{"harness":"codex"},"agy":{"harness":"agy"},"teams":{"harness":"claude"},"bare":{}}}"#
    #expect(accountIcons(providersJSON: Data(json.utf8)) == ["pro": "claude", "codex": "codex", "agy": "antigravity", "teams": "claude", "bare": "bare"])
    #expect(accountIcons(providersJSON: nil) == ["claude": "claude", "codex": "codex", "agy": "antigravity"])
}

@Test func aRoleSavedWhileTheEngineDidNotAnswerIsSavedAndSaysTheEngineDidNotAnswer() throws {
    let path = try temporaryConfig()
    let result = saveRepoRole(RoleFields(model: "a"), role: .reviewer, repo: "a/b", path: path, accounts: accounts, reload: { .noAnswer })
    #expect(result == .notApplied("Saved, but Carrier did not answer: it will read the file when it starts.") && result.isWritten)
    #expect(try entry(path)?["model"] as? String == "a")
}
