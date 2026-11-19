import Foundation
import Testing
@testable import CarrierCore

private func config(author: String = #"{"profile": "acme-author", "provider": "claude", "model": "sonnet", "effort": "high"}"#,
                     reviewer: String = #"{"profile": "acme-reviewer", "provider": "codex", "model": "gpt-5"}"#,
                     lead: String? = #"{"profile": "acme-lead", "provider": "claude", "model": "opus"}"#) -> String {
    """
    {"profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "acme-reviewer": {"kind": "forge", "agent": "acme-reviewer"},
                  "acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
     "agents": {"author": \(author), "reviewer": \(reviewer)\(lead.map { ", \"leadReviewer\": \($0)" } ?? "")}}
    """
}

private let bots = ForgeBots(names: ["acme-author", "acme-reviewer", "acme-lead"], note: nil)

private func readiness(_ json: String, providers: String? = nil) throws -> AgentsReadiness {
    agentsReadiness(try #require(agentsPage(config: Data(json.utf8), providers: providers.map { Data($0.utf8) }, bots: bots)))
}

@Test func threeRolesThatAreWholeAreSetUp() throws {
    let found = try readiness(config())
    #expect(found.tone == .ready && found.title == "All three roles are set up")
    #expect(found.notes == ["Each has an identity, an account and a model."] && found.problems.isEmpty && found.fix == nil)
}

@Test func aLeadReviewerThatIsOffIsSaidAndIsNotAProblem() throws {
    let found = try readiness(config(lead: nil))
    #expect(found.tone == .ready && found.title == "Author and Reviewer are set up" && found.notes == ["The Lead reviewer is off."])
}

@Test func anIdentityNotInTheRegistryNeedsAttentionAndPointsToItsRole() throws {
    let found = try readiness(config(reviewer: #"{"profile": "gone", "provider": "codex", "model": "gpt-5"}"#).replacingOccurrences(of: #""me""#, with: #""gone": {"kind": "forge", "agent": "gone"}, "me""#))
    #expect(found.tone == .attention && found.title == "One role needs attention" && found.fix == .reviewer)
    #expect(found.notes.first == "Reviewer: the identity “gone” is not in Agent Forge or in profiles. Choose another.")
}

@Test func anAccountThatIsNotInProvidersJsonNeedsAttention() throws {
    let found = try readiness(config(), providers: #"{"providers": {"claude": {"harness": "claude"}}}"#)
    #expect(found.problems.map(\.role) == [.reviewer] && found.fix == .reviewer)
    #expect(found.problems.contains { $0.text == "the account “codex” is not in providers.json." })
}

@Test func aRoleWithNothingChosenSaysWhatIsMissing() throws {
    let found = try readiness(config(author: #"{}"#))
    let texts = found.problems.filter { $0.role == .author }.map(\.text)
    #expect(texts == ["it has no identity yet.", "it has no account yet.", "it has no model yet."])
    #expect(found.title == "One role needs attention" && found.fix == .author)
}

@Test func twoRolesInTroubleAreCountedByRoleNotByProblem() throws {
    let found = try readiness(config(author: #"{}"#, reviewer: #"{}"#))
    #expect(found.title == "2 roles need attention" && found.problems.count == 6)
}

@Test func everyProblemHasItsOwnIdEvenWhenOneRoleHasSeveral() throws {
    let found = try readiness(config(author: #"{}"#))
    #expect(found.problems.count == 3 && Set(found.problems.map(\.id)).count == 3)
}

@Test func aLeadReviewerBeingTurnedOnIsShownAsOneThatIsOnWhileTheFileStillHasNone() throws {
    let page = try #require(agentsPage(config: Data(config(lead: nil).utf8), providers: nil, bots: bots))
    let off = try #require(page.rows.first { $0.role == .leadReviewer })
    #expect(off.off && off.headline == "Off" && off.drafting == false)
    var draft = LeadReviewerDraft()
    draft.apply(.bot("acme-lead"))
    draft.apply(.provider("claude"))
    draft.apply(.model("opus"))
    let shown = draft.shown(in: off)
    // the switch still says the file has no role, and the page words and draws it as a role that is on
    #expect(shown.off && shown.drafting && shown.headline == "opus · acme-lead")
    #expect(shown.switchDetail == off.switchDetail)
    // before anything is chosen it is not "Off" either: it says nothing is set
    #expect(LeadReviewerDraft().shown(in: off).headline == "Not set")
}

@Test func theLeadReviewerWhileOffIsNeverChecked() throws {
    let found = try readiness(config(lead: nil))
    #expect(found.problems.isEmpty)
}

@Test func theSharedAccountNoteIsKept() throws {
    let found = try readiness(config(reviewer: #"{"profile": "acme-author", "provider": "codex", "model": "gpt-5"}"#))
    #expect(found.notes.contains { $0.contains("Author and Reviewer both work as acme-author") })
}

@Test func theHeadlineOfARoleIsItsModelEffortAndIdentity() throws {
    let page = try #require(agentsPage(config: Data(config(lead: nil).utf8), providers: nil, bots: bots))
    #expect(page.rows.first { $0.role == .author }?.headline == "sonnet · high · acme-author")
    #expect(page.rows.first { $0.role == .reviewer }?.headline == "gpt-5 · acme-reviewer")
    #expect(page.rows.first { $0.role == .leadReviewer }?.headline == "Off")
    let empty = try #require(agentsPage(config: Data(config(author: "{}").utf8), providers: nil, bots: bots))
    #expect(empty.rows.first { $0.role == .author }?.headline == "Not set")
}

// MARK: the skill of each stage

@Test func theStagesAreWhatTheEngineInvokesNotMore() throws {
    let prompts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("src/prompts")
    let code = try FileManager.default.contentsOfDirectory(at: prompts, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ts" && $0.lastPathComponent.hasSuffix(".test.ts") == false }
        .map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    let regex = try NSRegularExpression(pattern: #"invoke\(task, '([a-z0-9:_-]+)'\)"#)
    let invoked = Set(regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
        Range(match.range(at: 1), in: code).map { String(code[$0]) }
    })
    let listed = Set(AgentRole.allCases.flatMap(\.stages).map(\.skill))
    #expect(invoked.isEmpty == false)
    #expect(listed == invoked, "AgentRole.stages and src/prompts disagree on the skills each stage runs")
}

@Test func theLeadReviewerHasNoStageAndTheOthersHaveTheirSkillsInOrder() {
    #expect(AgentRole.leadReviewer.stages.isEmpty)
    #expect(AgentRole.author.stages.map(\.skill) == ["ship", "code-resolve"])
    #expect(AgentRole.reviewer.stages.map(\.skill) == ["code-review", "code-post"])
}

@Test func codexIsToldASkillWithADollarAndTheOthersWithASlash() {
    #expect(skillInvocation("ship", icon: "codex") == "$ship")
    #expect(skillInvocation("code-review", icon: "claude") == "/code-review")
    #expect(skillInvocation("code-post", icon: "antigravity") == "/code-post")
    #expect(skillInvocation("ship", icon: nil) == "/ship")
}

// MARK: the picture of a bot

@Test func theRegistryGivesTheGitHubAppIdOfEachBotThatHasAValidOne() {
    let list = forgeBots(registry: Data(#"{"agents": [{"name": "a", "appId": "4854138"}, {"name": "b", "appId": "12/../x"}, {"name": "c"}, {"name": "d", "appId": 7}, {"name": "e", "appId": ""}]}"#.utf8))
    #expect(list.names == ["a", "b", "c", "d", "e"])
    #expect(list.appIds == ["a": "4854138"])
}

@Test func theAvatarIsAskedOnlyForADigitsOnlyIdAtASensibleSize() {
    #expect(forgeAvatarURL(appId: "4854138", pixels: 192)?.absoluteString == "https://avatars.githubusercontent.com/in/4854138?s=192")
    for bad in ["", "abc", "12 3", "1/2", "../1", "1234567890123", "-1", "1.5", "1\u{0301}", "١٢٣"] { #expect(forgeAvatarURL(appId: bad, pixels: 192) == nil, "\(bad)") }
    #expect(forgeAvatarURL(appId: "1", pixels: 0) == nil && forgeAvatarURL(appId: "1", pixels: 100_000) == nil)
}

@Test func aBotWithNoPictureWearsTheFirstLettersOfItsName() {
    #expect(roleInitials("artanis-agent") == "AA")
    #expect(roleInitials("zeratul") == "Z")
    #expect(roleInitials("acme-lead-two") == "AL")
    #expect(roleInitials("  ") == "?" && roleInitials("") == "?")
    #expect(roleInitials("élan vital") == "ÉV")
}
