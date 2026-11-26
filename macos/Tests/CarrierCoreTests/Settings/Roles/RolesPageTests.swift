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

private func page(_ json: String = full, providers: String? = nil, bots: ForgeBots = bots) throws -> RolesPage {
    try #require(rolesPage(config: Data(json.utf8), providers: providers.map { Data($0.utf8) }, bots: bots, bundle: english.bundle, locale: english.locale))
}

private func row(_ page: RolesPage, _ role: AgentRole) throws -> RoleRow { try #require(page.rows.first { $0.role == role }) }

@Test func aFullConfigGivesTheThreeRolesInOrderWithEveryField() throws {
    let found = try page()
    #expect(found.rows.map(\.role) == [.author, .reviewer, .leadReviewer])
    let author = try row(found, .author)
    #expect(author.fields == RoleFields(profile: "acme-author", provider: "claude", model: "sonnet", effort: "high", persona: RolePersona(name: "Ada", prompt: "Be brief")))
    #expect(author.identity == .forge("acme-author") && author.summary(bundle: english.bundle, locale: english.locale) == "acme-author · claude · sonnet · high")
    #expect(try row(found, .reviewer).summary(bundle: english.bundle, locale: english.locale) == "acme-reviewer · codex · gpt-5 · max")
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
    #expect(lead.summary(bundle: english.bundle, locale: english.locale) == "acme-lead · claude · opus")
}

@Test func aConfigWithoutALeadReviewerShowsItOffAndDimmedWithTheSwitchOnTop() throws {
    let json = #"{"profiles": {"me": {"kind": "gh"}}, "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}, "reviewer": {"profile": "me", "provider": "codex", "model": "m"}}}"#
    let lead = try row(page(json), .leadReviewer)
    #expect(lead.off && lead.hasSwitch && lead.summary(bundle: english.bundle, locale: english.locale) == "Off" && lead.fields.isEmpty && lead.identity == .unset)
    #expect(try row(page(json), .author).off == false && (try row(page(json), .author).hasSwitch == false))
}

@Test func aProfileMissingFromTheRegistryShowsAsMissingAndKeepsItsName() throws {
    let found = try page(bots: ForgeBots(names: ["acme-author"], note: nil))
    let reviewer = try row(found, .reviewer)
    #expect(reviewer.identity == .missing && reviewer.fields.profile == "acme-reviewer")
    #expect(reviewer.identityDetail(bundle: english.bundle, locale: english.locale).contains("acme-reviewer"))
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
    let missing = forgeBots(registry: nil, bundle: english.bundle, locale: english.locale)
    #expect(missing.names.isEmpty && missing.note?.contains("No Agent Forge registry") == true)
    let broken = forgeBots(registry: Data("not json".utf8), bundle: english.bundle, locale: english.locale)
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
    #expect(rolesPage(config: Data("[]".utf8), providers: nil, bots: bots) == nil)
    #expect(rolesPage(config: Data("nope".utf8), providers: nil, bots: bots) == nil)
}

@Test func readingTheConfigNeverWritesIt() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + "agents-page-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(full.utf8).write(to: url)
    let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    _ = try #require(rolesPage(config: Data(contentsOf: url), providers: nil, bots: bots))
    #expect(try Data(contentsOf: url) == Data(full.utf8))
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)
}

private func withExtras(_ entries: String) -> String {
    """
    {"profiles": {"a": {"kind": "gh"}, "x": {"kind": "forge", "agent": "acme-reviewer"}},
     "agents": {"author": {"profile": "a", "provider": "claude", "model": "m"},
                "reviewer": {"profile": "a", "provider": "codex", "model": "gpt-5"}\(entries.isEmpty ? "" : ", \"extraReviewers\": [\(entries)]"),
                "leadReviewer": {"profile": "a", "provider": "claude", "model": "opus"}},
     "failover": {"roles": {"reviewer": [{"provider": "claude-work", "model": "sonnet"}]}}}
    """
}

@Test func aConfigWithNoExtraReviewersHasTheThreeRowsAsBefore() throws {
    #expect(try page(withExtras("")).rows.map(\.slot) == [.author, .reviewer, .lead])
    #expect(try page(withExtras("")).rows.contains { $0.slot.isExtra } == false)
}

@Test func oneExtraReviewerIsReviewer2BetweenTheReviewerAndTheLead() throws {
    let found = try page(withExtras(#"{"profile": "x", "provider": "codex", "model": "gpt-5-mini", "effort": "low"}"#))
    #expect(found.rows.map(\.slot) == [.author, .reviewer, .extra(2), .lead])
    let extra = try #require(found.rows.first { $0.slot == .extra(2) })
    #expect(extra.title(bundle: english.bundle, locale: english.locale) == "Reviewer 2" && extra.slot.name == "reviewer-2" && extra.id == "reviewer-2")
    #expect(extra.identity == .forge("acme-reviewer") && extra.summary(bundle: english.bundle, locale: english.locale) == "x · codex · gpt-5-mini · low")
}

@Test func threeExtraReviewersAreReviewer2To4InTheOrderOfTheList() throws {
    let entry = { (model: String) in #"{"profile": "a", "provider": "codex", "model": "\#(model)", "persona": {"name": "P\#(model)", "prompt": "q"}}"# }
    let found = try page(withExtras([entry("m2"), entry("m3"), entry("m4")].joined(separator: ",")))
    #expect(found.rows.map(\.slot) == [.author, .reviewer, .extra(2), .extra(3), .extra(4), .lead])
    #expect(found.rows.filter { $0.slot.isExtra }.map { $0.fields.model } == ["m2", "m3", "m4"])
    #expect(found.rows.first { $0.slot == .extra(3) }?.fields.persona?.name == "Pm3")
}

@Test func anExtraReviewerWithNoFailoverTakesTheReviewersStepsAndOneWithItsOwnKeepsThem() throws {
    let found = try page(withExtras(#"{"profile": "a", "provider": "codex", "model": "m", "failover": [{"provider": "agy"}]}, {"profile": "a", "provider": "codex", "model": "m"}"#))
    let own = try #require(found.rows.first { $0.slot == .extra(2) })
    #expect(own.ownSteps && own.steps.map(\.text) == ["agy"])
    let inherited = try #require(found.rows.first { $0.slot == .extra(3) })
    #expect(inherited.ownSteps == false && inherited.steps.map(\.text) == ["claude-work · sonnet"])
}

@Test func theSlotNamesRoundTripAndAnUnknownReviewerIsNil() {
    for slot in [RoleSlot.author, .reviewer, .lead, .extra(2), .extra(4)] { #expect(RoleSlot(name: slot.name) == slot) }
    #expect(RoleSlot(name: "reviewer-1") == nil && RoleSlot(name: "reviewer-5") == nil && RoleSlot(name: "reviewer-02") == nil && RoleSlot(name: "x") == nil)
}

@Test func anExtraReviewersSkillsAreTheReviewersAndAnIdentityLessSlotHasNone() throws {
    let found = try page(withExtras(#"{"profile": "a", "provider": "codex", "model": "m"}"#))
    let extra = try #require(found.rows.first { $0.slot == .extra(2) })
    let reviewer = try #require(found.rows.first { $0.slot == .reviewer })
    let stages = { (row: RoleRow) in row.slot.stages(bundle: english.bundle, locale: english.locale).map(\.skill) }
    #expect(stages(extra) == ["code-review", "code-post"] && stages(extra) == stages(reviewer))
    #expect(RoleSlot.lead.stages(bundle: english.bundle, locale: english.locale).isEmpty)
}

@Test func aPlaceWhoseReviewerNoLongerExistsHasNoRowSoTheViewShowsTheFirstScreen() throws {
    // the place names a slot that parses, but the file now has fewer extra reviewers: no row answers it
    let place = try #require(RoleSlot(name: "reviewer-3"))
    let one = try page(withExtras(#"{"profile": "a", "provider": "codex", "model": "m"}"#))
    #expect(one.rows.contains { $0.slot == .extra(2) } && one.rows.contains { $0.slot == place } == false)
    #expect(try page(withExtras("")).rows.contains { $0.slot == place } == false)
}
