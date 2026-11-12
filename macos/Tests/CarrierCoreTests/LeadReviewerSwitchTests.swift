import Foundation
import Testing
@testable import CarrierCore

// The Use a lead reviewer switch of the Agents page: what turning it off removes from a temporary config.json, that turning it on writes nothing
// until identity, provider and model are chosen, and what the page's model says about the dimmed page.

private let accounts = ["claude", "codex", "agy"]
private let bots = ["acme-author", "acme-lead"]
private let withLead = #"""
{"keep": {"deep": [1]}, "orchestratorProfile": "acme-author",
 "profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
 "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m"},
            "leadReviewer": {"profile": "acme-lead", "provider": "claude", "model": "opus", "effort": "high", "extra": true}},
 "failover": {"triggers": ["usage_limit"], "roles": {"author": [{"provider": "codex"}], "leadReviewer": [{"provider": "codex", "model": "gpt-5"}]}},
 "repos": [{"name": "a/b"}]}
"""#
private let withoutLead = #"""
{"keep": 1, "profiles": {"acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
 "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}}}
"""#

private func temporaryConfig(_ text: String) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-lead-\(UUID().uuidString).json"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func file(_ path: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
}

private func complete() -> LeadReviewerDraft {
    var draft = LeadReviewerDraft()
    draft.apply(.bot("acme-lead"))
    draft.apply(.provider("codex"))
    draft.apply(.model(" gpt-5 "))
    return draft
}

@Test func turningItOffRemovesTheRoleAndItsFailoverStepsAndKeepsEveryOtherKey() throws {
    let path = try temporaryConfig(withLead)
    var expected = try file(path)
    #expect(turnLeadReviewerOff(path: path, reload: { nil }) == .saved)
    var agents = try #require(expected["agents"] as? [String: Any])
    agents["leadReviewer"] = nil
    expected["agents"] = agents
    var failover = try #require(expected["failover"] as? [String: Any])
    var roles = try #require(failover["roles"] as? [String: Any])
    roles["leadReviewer"] = nil
    failover["roles"] = roles
    expected["failover"] = failover
    #expect(try NSDictionary(dictionary: file(path)).isEqual(to: expected))
}

@Test func turningItOffWhenTheFileHasNoRoleLeavesTheFileAsItIs() throws {
    let path = try temporaryConfig(withoutLead)
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    #expect(turnLeadReviewerOff(path: path, reload: { nil }) == .saved)
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    #expect(turnLeadReviewerOff(path: path + ".missing", reload: { nil }) != .saved)
}

@Test func turningItOnWritesNothingUntilIdentityProviderAndModelAreChosen() throws {
    let path = try temporaryConfig(withoutLead)
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    var draft = LeadReviewerDraft()
    #expect(draft.isComplete == false && draft.missing == ["an identity", "a provider", "a model"])
    #expect(draft.hint == "Choose an identity, a provider and a model to turn it on. Nothing is written until then.")
    draft.apply(.bot("acme-lead"))
    draft.apply(.effort("max"))
    draft.apply(.model("   "))
    #expect(draft.missing == ["a provider", "a model"])
    // the page never calls with an incomplete draft, and if it did the file stays as it is
    guard case .refused = turnLeadReviewerOn(draft, path: path, accounts: accounts, bots: bots, reload: { nil }) else { Issue.record("expected a refusal"); return }
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
}

@Test func onceTheThreeAreChosenTheWholeRoleIsWrittenAndEveryOtherKeyStays() throws {
    let path = try temporaryConfig(withoutLead)
    var draft = complete()
    draft.apply(.effort("high"))
    #expect(draft.isComplete && draft.hint == nil)
    #expect(turnLeadReviewerOn(draft, path: path, accounts: accounts, bots: bots, reload: { nil }) == .saved)
    let saved = try file(path)
    let lead = try #require((saved["agents"] as? [String: Any])?["leadReviewer"] as? [String: Any])
    #expect(NSDictionary(dictionary: lead).isEqual(to: ["profile": "acme-lead", "provider": "codex", "model": "gpt-5", "effort": "high"]))
    #expect(saved["keep"] as? Int == 1)
    #expect((saved["agents"] as? [String: Any])?["author"] != nil)
}

@Test func aBotOrProviderTheFileWouldRefuseIsRefusedAndNothingIsWritten() throws {
    let path = try temporaryConfig(withoutLead)
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    var unknownBot = complete()
    unknownBot.apply(.bot("ghost"))
    var unknownProvider = complete()
    unknownProvider.apply(.provider("nope"))
    for draft in [unknownBot, unknownProvider] {
        guard case .refused = turnLeadReviewerOn(draft, path: path, accounts: accounts, bots: bots, reload: { nil }) else { Issue.record("expected a refusal"); return }
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
}

@Test func theDraftIsShownInPlaceOfTheEmptyRoleAndTheSwitchRowTellsWhatOffDoes() throws {
    let off = try #require(agentsPage(config: Data(withoutLead.utf8), providers: nil, bots: ForgeBots(names: bots, note: nil))?.rows.first { $0.role == .leadReviewer })
    #expect(off.off && off.usable(turningOn: false) == false && off.usable(turningOn: true))
    #expect(off.switchDetail == "Off: the file has no lead reviewer")
    let shown = complete().shown(in: off)
    #expect(shown.fields == RoleFields(profile: "acme-lead", provider: "codex", model: " gpt-5 ") && shown.identity == .forge("acme-lead"))

    let on = try #require(agentsPage(config: Data(withLead.utf8), providers: nil, bots: ForgeBots(names: bots, note: nil))?.rows.first { $0.role == .leadReviewer })
    #expect(on.off == false && on.usable(turningOn: false))
    #expect(on.switchDetail.contains("removes the lead reviewer and its failover steps from the file"))
}

// MARK: the engine is asked to reload

@Test func turningTheLeadReviewerOnOrOffAsksTheEngineToReloadAfterTheWriteOnly() throws {
    let path = try temporaryConfig(withoutLead)
    let engine = FakeReload(file: path)
    // an incomplete draft writes nothing and asks nothing
    #expect(turnLeadReviewerOn(LeadReviewerDraft(), path: path, accounts: accounts, bots: bots, reload: engine.reload) != .saved)
    #expect(engine.calls == 0)
    #expect(turnLeadReviewerOn(complete(), path: path, accounts: accounts, bots: bots, reload: engine.reload) == .saved)
    #expect(engine.calls == 1 && engine.seen[0] == engine.now)
    #expect(turnLeadReviewerOff(path: path, reload: engine.reload) == .saved)
    #expect(engine.calls == 2 && engine.seen[1] == engine.now)
    // already off: the file is left as it is, so there is nothing to apply
    #expect(turnLeadReviewerOff(path: path, reload: engine.reload) == .saved)
    #expect(turnLeadReviewerOff(path: path + ".missing", reload: engine.reload) != .saved)
    #expect(engine.calls == 2)
}

@Test func aLeadReviewerTheEngineRefusedToApplyIsSavedAndSaysWhatTheEngineAnswered() throws {
    let path = try temporaryConfig(withLead)
    let engine = FakeReload(file: path, problem: "failover.roles.leadReviewer: bad")
    let result = turnLeadReviewerOff(path: path, reload: engine.reload)
    #expect(result == .notApplied("Saved, but Carrier kept its settings: failover.roles.leadReviewer: bad") && result.isWritten)
    #expect((try file(path)["agents"] as? [String: Any])?["leadReviewer"] == nil)
}
