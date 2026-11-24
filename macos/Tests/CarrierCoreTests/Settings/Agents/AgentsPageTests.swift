import Foundation
import Testing
@testable import CarrierCore

private let full = #"""
{
  "keep": 1,
  "profiles": {
    "acme-author": {"kind": "forge", "agent": "acme-author"},
    "acme-reviewer": {"kind": "forge", "agent": "acme-reviewer"},
    "acme-lead": {"kind": "forge", "agent": "acme-lead"},
    "me": {"kind": "gh"}
  },
  "agents": {
    "author": {"profile": "acme-author", "provider": "claude", "model": "sonnet", "effort": "high", "persona": {"name": "Ada", "prompt": "Be brief"}},
    "reviewer": {"profile": "acme-reviewer", "provider": "codex", "model": "gpt-5", "effort": "max"},
    "leadReviewer": {"profile": "acme-lead", "provider": "claude", "model": "opus"}
  },
  "failover": {
    "triggers": ["usage_limit"],
    "roles": {
      "author": [{"provider": "codex", "model": "gpt-5"}, {"provider": "claude-work"}, {"provider": "agy", "model": "gemini"}],
      "reviewer": []
    }
  }
}
"""#

private let bots = ForgeBots(names: ["acme-author", "acme-reviewer", "acme-lead"], note: nil)

private func page(_ json: String = full, providers: String? = nil, bots: ForgeBots = bots) throws -> AgentsPage {
    try #require(agentsPage(config: Data(json.utf8), providers: providers.map { Data($0.utf8) }, bots: bots))
}

private func row(_ page: AgentsPage, _ role: AgentRole) throws -> RoleRow { try #require(page.rows.first { $0.role == role }) }

@Test func aFullConfigGivesTheThreeRolesInOrderWithEveryField() throws {
    let found = try page()
    #expect(found.rows.map(\.role) == [.author, .reviewer, .leadReviewer])
    let author = try row(found, .author)
    #expect(author.fields == RoleFields(profile: "acme-author", provider: "claude", model: "sonnet", effort: "high", persona: RolePersona(name: "Ada", prompt: "Be brief")))
    #expect(author.identity == .forge("acme-author") && author.summary == "acme-author · claude · sonnet · high")
    #expect(try row(found, .reviewer).summary == "acme-reviewer · codex · gpt-5 · max")
    #expect(try row(found, .leadReviewer).off == false)
    #expect(found.bots == bots && found.sharedNote == nil)
}

@Test func failoverStepsAreReadWithTheirModelAndAllOfThemAreKept() throws {
    let steps = try row(page(), .author).steps
    #expect(steps.map(\.text) == ["codex · gpt-5", "claude-work", "agy · gemini"])
    #expect(steps[1].model == nil)
}

@Test func aRoleWithNoFailoverHasNoStepsWhetherEmptyOrAbsent() throws {
    let found = try page()
    #expect(try row(found, .reviewer).steps.isEmpty)
    #expect(try row(found, .leadReviewer).steps.isEmpty)
}

@Test func aRoleWithNoEffortShowsItWithoutOne() throws {
    let lead = try row(page(), .leadReviewer)
    #expect(lead.fields.effort == nil)
    #expect(lead.summary == "acme-lead · claude · opus")
}

@Test func aConfigWithoutALeadReviewerShowsItOffAndDimmedWithTheSwitchOnTop() throws {
    let json = #"{"profiles": {"me": {"kind": "gh"}}, "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}, "reviewer": {"profile": "me", "provider": "codex", "model": "m"}}}"#
    let lead = try row(page(json), .leadReviewer)
    #expect(lead.off && lead.hasSwitch && lead.summary == "Off" && lead.fields.isEmpty && lead.identity == .unset)
    #expect(try row(page(json), .author).off == false && (try row(page(json), .author).hasSwitch == false))
}

@Test func aProfileMissingFromTheRegistryShowsAsMissingAndKeepsItsName() throws {
    let found = try page(bots: ForgeBots(names: ["acme-author"], note: nil))
    let reviewer = try row(found, .reviewer)
    #expect(reviewer.identity == .missing && reviewer.fields.profile == "acme-reviewer")
    #expect(reviewer.identityDetail.contains("acme-reviewer"))
    #expect(try row(found, .author).identity == .forge("acme-author"))
}

@Test func aProfileThatIsNotInProfilesIsMissingToo() throws {
    let json = #"{"profiles": {}, "agents": {"author": {"profile": "ghost", "provider": "claude", "model": "m"}}}"#
    #expect(try row(page(json), .author).identity == .missing)
}

@Test func theOwnGhLoginNeedsNoBot() throws {
    let json = #"{"profiles": {"me": {"kind": "gh"}}, "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}}}"#
    #expect(try row(page(json, bots: forgeBots(registry: nil)), .author).identity == .gh)
}

@Test func theRegistryMissingOrUnreadableGivesNoBotsAndANoteNotAnError() {
    let missing = forgeBots(registry: nil)
    #expect(missing.names.isEmpty && missing.note?.contains("No Agent Forge registry") == true)
    let broken = forgeBots(registry: Data("not json".utf8))
    #expect(broken.names.isEmpty && broken.note?.contains("could not be read") == true)
    let list = forgeBots(registry: Data(#"{"agents": [{"name": "a", "privateKey": "secret"}, {"label": "x"}, {"name": "b"}]}"#.utf8))
    #expect(list == ForgeBots(names: ["a", "b"], note: nil))
}

@Test func theRegistryIsFoundWhereForgeKeepsIt() {
    #expect(forgeRegistryPath(environment: ["AGENT_FORGE_CONFIG": "/x/agents.json"], home: "/h") == "/x/agents.json")
    #expect(forgeRegistryPath(environment: ["XDG_CONFIG_HOME": "/xdg"], home: "/h") == "/xdg/agent-forge/agents.json")
    #expect(forgeRegistryPath(environment: [:], home: "/h") == "/h/.config/agent-forge/agents.json")
    #expect(forgeRegistryPath(environment: ["AGENT_FORGE_CONFIG": ""], home: "/h") == "/h/.config/agent-forge/agents.json")
}

@Test func theProviderIsMissingWhenItIsNotAnAccount() throws {
    #expect(try row(page(), .author).providerMissing == false) // the three default accounts without providers.json
    let found = try page(providers: #"{"providers": {"claude": {"harness": "claude"}}}"#)
    #expect(try row(found, .author).providerMissing == false)
    #expect(try row(found, .reviewer).providerMissing)
    #expect(found.accounts == ["claude"])
}

@Test func twoRolesOfOneAccountSaySoByTheEnginesRuleNotByName() throws {
    let same = #"{"profiles": {"a": {"kind": "forge", "agent": "bot"}, "b": {"kind": "forge", "agent": "bot"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "b"}}}"#
    #expect(try page(same).sharedNote == "Author and Reviewer are one account (a and b): the signature will show it.")
    let twice = #"{"profiles": {"a": {"kind": "forge", "agent": "bot"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "a"}}}"#
    #expect(try page(twice).sharedNote == "Author and Reviewer both work as a: the signature will show it.")
    let gh = #"{"profiles": {"a": {"kind": "gh"}, "b": {"kind": "gh"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "b"}}}"#
    #expect(try page(gh).sharedNote != nil)
    let apart = #"{"profiles": {"a": {"kind": "forge", "agent": "x"}, "b": {"kind": "forge", "agent": "y"}, "c": {"kind": "gh"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "b"}, "leadReviewer": {"profile": "c"}}}"#
    #expect(try page(apart).sharedNote == nil)
}

@Test func aConfigThatIsMissingOrNotAJSONObjectIsNotConfigured() {
    #expect(agentsPage(config: Data("[]".utf8), providers: nil, bots: bots) == nil)
    #expect(agentsPage(config: Data("nope".utf8), providers: nil, bots: bots) == nil)
}

@Test func readingTheConfigNeverWritesIt() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + "agents-page-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(full.utf8).write(to: url)
    let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    _ = try #require(agentsPage(config: Data(contentsOf: url), providers: nil, bots: bots))
    #expect(try Data(contentsOf: url) == Data(full.utf8))
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
}
