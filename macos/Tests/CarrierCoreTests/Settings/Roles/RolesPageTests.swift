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

@Test func theLeadTakesTheReviewersStepsWhileItHasNoneAndKeepsItsOwnWhenItDeclaresThem() throws {
    let reviewerSteps = #""reviewer": [{"provider": "claude-work", "model": "sonnet"}]"#
    let inherited = try row(page(full.replacingOccurrences(of: #""reviewer": []"#, with: reviewerSteps)), .leadReviewer)
    #expect(inherited.ownSteps == false && inherited.steps.map(\.text) == ["claude-work · sonnet"])
    let own = try row(page(full.replacingOccurrences(of: #""reviewer": []"#, with: reviewerSteps + #", "leadReviewer": [{"provider": "agy"}]"#)), .leadReviewer)
    #expect(own.ownSteps && own.steps.map(\.text) == ["agy"])
    // the Author and the Reviewer never take another role's steps
    #expect(try row(page(full.replacingOccurrences(of: #""reviewer": []"#, with: reviewerSteps)), .author).ownSteps)
}

@Test func theRailSaysHowManyRoundsTheLeadHasWithTheAuthorThreeUnlessTheFileSaysOtherwise() throws {
    #expect(try page().leadRounds == 3)
    #expect(try page(full.replacingOccurrences(of: #""keep": 1,"#, with: #""limits": {"maxLeadRounds": 5},"#)).leadRounds == 5)
    #expect(Copy.rolesRailPasses(rounds: 3, bundle: english.bundle, locale: english.locale) == "When every reviewer agrees · up to 3 rounds with the author")
    #expect(Copy.rolesRailPasses(rounds: 1, bundle: english.bundle, locale: english.locale) == "When every reviewer agrees · up to 1 round with the author")
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

private func withExtras(_ entries: String, as shape: (open: String, close: String) = ("{", "}")) -> String {
    """
    {"profiles": {"a": {"kind": "gh"}, "x": {"kind": "forge", "agent": "acme-reviewer"}},
     "agents": {"author": {"profile": "a", "provider": "claude", "model": "m"},
                "reviewer": {"profile": "a", "provider": "codex", "model": "gpt-5"}\(entries.isEmpty ? "" : ", \"extraReviewers\": \(shape.open)\(entries)\(shape.close)"),
                "leadReviewer": {"profile": "a", "provider": "claude", "model": "opus"}},
     "failover": {"roles": {"reviewer": [{"provider": "claude-work", "model": "sonnet"}]}}}
    """
}

@Test func aConfigWithNoExtraReviewersHasTheThreeRowsAsBefore() throws {
    #expect(try page(withExtras("")).rows.map(\.slot) == [.author, .reviewer, .lead])
    #expect(try page(withExtras("")).rows.contains { $0.slot.isExtra } == false)
}

@Test func anEmptyMapAndAListGiveNoExtraReviewerRow() throws {
    #expect(try page(withExtras(" ")).rows.map(\.slot) == [.author, .reviewer, .lead])
    let list = withExtras(#"{"type": "ux", "name": "Usabilidad", "profile": "x", "provider": "codex", "model": "m"}"#, as: ("[", "]"))
    #expect(try page(list).rows.map(\.slot) == [.author, .reviewer, .lead])
}

@Test func oneExtraReviewerIsTitledByItsNameAndAddressedByItsKeyBetweenTheReviewerAndTheLead() throws {
    let found = try page(withExtras(#""seguridad-api": {"type": "security", "name": "Seguridad API", "profile": "x", "provider": "codex", "model": "gpt-5-mini", "effort": "low"}"#))
    #expect(found.rows.map(\.slot) == [.author, .reviewer, .extra(key: "seguridad-api"), .lead])
    let extra = try #require(found.rows.first { $0.slot.isExtra })
    #expect(extra.title(bundle: english.bundle, locale: english.locale) == "Seguridad API" && extra.title(bundle: spanish.bundle, locale: spanish.locale) == "Seguridad API")
    #expect(extra.slot.name == "seguridad-api" && extra.id == "seguridad-api" && extra.type == "security")
    #expect(extra.identity == .forge("acme-reviewer") && extra.summary(bundle: english.bundle, locale: english.locale) == "x · codex · gpt-5-mini · low")
}

@Test func threeExtraReviewersAreInTheOrderOfTheMapNotOfTheKeys() throws {
    let entry = { (key: String, model: String) in #""\#(key)": {"type": "t", "name": "N\#(model)", "profile": "a", "provider": "codex", "model": "\#(model)", "persona": {"name": "P\#(model)", "prompt": "q"}}"# }
    let found = try page(withExtras([entry("zeta", "m2"), entry("alfa", "m3"), entry("model", "m4")].joined(separator: ",")))
    #expect(found.rows.map(\.slot) == [.author, .reviewer, .extra(key: "zeta"), .extra(key: "alfa"), .extra(key: "model"), .lead])
    #expect(found.rows.filter { $0.slot.isExtra }.map { $0.fields.model } == ["m2", "m3", "m4"])
    #expect(found.rows.filter { $0.slot.isExtra }.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["Nm2", "Nm3", "Nm4"])
    #expect(found.rows.first { $0.slot == .extra(key: "alfa") }?.fields.persona?.name == "Pm3")
}

@Test func onlyThreeExtraReviewersAreRead() throws {
    let entry = { (key: String) in #""\#(key)": {"type": "t", "name": "\#(key)", "profile": "a", "provider": "codex", "model": "m"}"# }
    let found = try page(withExtras(["a", "b", "c", "d"].map(entry).joined(separator: ",")))
    #expect(found.rows.filter { $0.slot.isExtra }.map(\.id) == ["a", "b", "c"])
}

@Test func anExtraReviewerWithNoFailoverTakesTheReviewersStepsAndOneWithItsOwnKeepsThem() throws {
    let found = try page(withExtras(#""own": {"type": "t", "name": "Own", "profile": "a", "provider": "codex", "model": "m", "failover": [{"provider": "agy"}]}, "plain": {"type": "t", "name": "Plain", "profile": "a", "provider": "codex", "model": "m"}"#))
    let own = try #require(found.rows.first { $0.slot == .extra(key: "own") })
    #expect(own.ownSteps && own.steps.map(\.text) == ["agy"])
    let inherited = try #require(found.rows.first { $0.slot == .extra(key: "plain") })
    #expect(inherited.ownSteps == false && inherited.steps.map(\.text) == ["claude-work · sonnet"])
}

@Test func theSlotNamesRoundTripAndAWordOfARoleOrAnOddKeyIsNil() {
    for slot in [RoleSlot.author, .reviewer, .lead, .extra(key: "seguridad-api"), .extra(key: "r-2")] { #expect(RoleSlot(name: slot.name) == slot) }
    #expect(RoleSlot(name: "lead") == nil && RoleSlot(name: "lead-reviewer") == nil && RoleSlot(name: "2fast") == nil && RoleSlot(name: "Upper") == nil && RoleSlot(name: "") == nil)
    #expect(RoleSlot(name: String(repeating: "a", count: 41)) == nil && RoleSlot(name: "has space") == nil)
}

@Test func anExtraReviewersSkillsAreTheReviewersAndAnIdentityLessSlotHasNone() throws {
    let found = try page(withExtras(#""x": {"type": "t", "name": "X", "profile": "a", "provider": "codex", "model": "m"}"#))
    let extra = try #require(found.rows.first { $0.slot.isExtra })
    let reviewer = try #require(found.rows.first { $0.slot == .reviewer })
    let stages = { (row: RoleRow) in row.slot.stages(bundle: english.bundle, locale: english.locale).map(\.skill) }
    #expect(stages(extra) == ["code-review", "code-post"] && stages(extra) == stages(reviewer))
    #expect(RoleSlot.lead.stages(bundle: english.bundle, locale: english.locale).map(\.skill) == ["code-review", "code-post"])
}

@Test func aPlaceWhoseKeyIsNotInTheFileHasNoRowSoTheViewShowsTheFirstScreen() throws {
    // the place names a slot that parses, but the file has no such key: no row answers it
    let place = try #require(RoleSlot(name: "gone"))
    let one = try page(withExtras(#""here": {"type": "t", "name": "Here", "profile": "a", "provider": "codex", "model": "m"}"#))
    #expect(one.rows.contains { $0.slot == .extra(key: "here") } && one.rows.contains { $0.slot == place } == false)
    #expect(try page(withExtras("")).rows.contains { $0.slot == place } == false)
}

@Test func theKeysOfAMapComeInTheOrderOfTheFileWhateverIsInsideThem() {
    let file = #"{"agents": {"extraReviewers": {"zeta": {"name": "a\"}b", "list": [1, {"x": "]"}]}, "b": 1, "alfa": {}}, "other": 1}"#
    #expect(jsonKeys(in: Data(file.utf8), at: ["agents", "extraReviewers"]) == ["zeta", "b", "alfa"])
    #expect(jsonKeys(in: Data(file.utf8), at: ["agents", "missing"]) == nil && jsonKeys(in: Data(file.utf8), at: ["other"]) == nil)
    #expect(jsonKeys(in: Data(#"{"agents": {"extraReviewers": []}}"#.utf8), at: ["agents", "extraReviewers"]) == nil)
    #expect(jsonKeys(in: Data(#"{"agents": {"extraReviewers": {}}}"#.utf8), at: ["agents", "extraReviewers"]) == [])
}
