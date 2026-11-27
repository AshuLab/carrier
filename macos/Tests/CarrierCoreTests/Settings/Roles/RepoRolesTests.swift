import Foundation
import Testing
@testable import CarrierCore

private let global = #"""
"profiles": {"b-author": {"kind": "gh"}, "a-reviewer": {"kind": "gh"}, "b-other": {"kind": "gh"}},
"agents": {
  "author": {"profile": "b-author", "provider": "claude", "model": "sonnet", "effort": "high", "persona": {"name": "Ada"}},
  "reviewer": {"profile": "a-reviewer", "provider": "codex", "model": "gpt-5"}
}
"""#

private func config(repoAgents: String? = nil, extra: String = "") -> Data {
    let own = repoAgents.map { #", "agents": \#($0)"# } ?? ""
    return Data(#"{"keep": 1, \#(global)\#(extra), "repos": [{"name": "a/b"\#(own)}, {"name": "c/d"}]}"#.utf8)
}

private func rows(_ json: Data, _ repo: String = "a/b") throws -> [AgentRole: RepoRoleRow] {
    Dictionary(uniqueKeysWithValues: try #require(repoRoles(json: json, repo: repo)).rows.map { ($0.role, $0) })
}

@Test func aRepoWithNoOverrideShowsTheInheritedRoles() throws {
    let found = try rows(config())
    let author = try #require(found[.author])
    #expect(author.isOwn == false && author.value == author.inherited)
    #expect(author.value.text(bundle: english.bundle, locale: english.locale) == "b-author · claude · sonnet · high")
    #expect(author.value.persona == RolePersona(name: "Ada", prompt: nil))
    #expect(found[.reviewer]?.value.text(bundle: english.bundle, locale: english.locale) == "a-reviewer · codex · gpt-5")
}

@Test func anOverrideOfOnlyTheModelMixesOwnAndInherited() throws {
    let author = try #require(rows(config(repoAgents: #"{"author": {"model": "opus"}}"#))[.author])
    #expect(author.isOwn && author.own == RoleFields(model: "opus"))
    #expect(author.value.text(bundle: english.bundle, locale: english.locale) == "b-author · claude · opus · high")
    #expect(author.inherited.text(bundle: english.bundle, locale: english.locale) == "b-author · claude · sonnet · high")
}

@Test func aFullOverrideIsTheOwnValue() throws {
    let own = #"{"reviewer": {"profile": "b-other", "provider": "ollama", "model": "qwen", "effort": "max", "persona": {"prompt": "Be brief"}}}"#
    let reviewer = try #require(rows(config(repoAgents: own))[.reviewer])
    #expect(reviewer.value.text(bundle: english.bundle, locale: english.locale) == "b-other · ollama · qwen · max" && reviewer.value == reviewer.own)
    #expect(reviewer.inherited.text(bundle: english.bundle, locale: english.locale) == "a-reviewer · codex · gpt-5")
}

@Test func aReposPersonaReplacesTheGlobalOneWhole() throws {
    let author = try #require(rows(config(repoAgents: #"{"author": {"persona": {"prompt": "Be brief"}}}"#))[.author])
    #expect(author.value.persona == RolePersona(name: nil, prompt: "Be brief"))
}

@Test func anotherRepoIsNotAffected() throws {
    let found = try rows(config(repoAgents: #"{"author": {"model": "opus"}}"#), "c/d")
    #expect(found[.author]?.isOwn == false && found[.author]?.value.model == "sonnet")
}

@Test func theLeadReviewerRowIsShownOnlyWhenTheGlobalConfigHasOne() throws {
    #expect(try rows(config())[.leadReviewer] == nil)
    // a repo cannot add one in this epic, so its own entry alone does not show the row
    #expect(try rows(config(repoAgents: #"{"leadReviewer": {"model": "x"}}"#))[.leadReviewer] == nil)
    let lead = #", "agents": {"author": {"profile": "b-author", "provider": "claude", "model": "sonnet"}, "leadReviewer": {"profile": "b-other", "provider": "claude", "model": "opus"}}"#
    let with = Data(#"{"profiles": {"b-other": {"kind": "gh"}}\#(lead), "repos": [{"name": "a/b"}]}"#.utf8)
    #expect(try rows(with)[.leadReviewer]?.value.text(bundle: english.bundle, locale: english.locale) == "b-other · claude · opus")
}

@Test func theProfileNamesAreRead() throws {
    #expect(try #require(repoRoles(json: config(), repo: "a/b")).profiles == ["a-reviewer", "b-author", "b-other"])
}

@Test func aConfigThatIsNotAJSONObjectIsNotConfigured() {
    #expect(repoRoles(json: Data(), repo: "a/b") == nil)
    #expect(repoRoles(json: Data("[]".utf8), repo: "a/b") == nil)
    #expect(repoRoles(json: Data("nope".utf8), repo: "a/b") == nil)
}

@Test func readingNeverWritesTheFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("repo-roles-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let before = config(repoAgents: #"{"author": {"model": "opus"}}"#)
    try before.write(to: url)
    _ = repoRoles(json: try Data(contentsOf: url), repo: "a/b")
    #expect(try Data(contentsOf: url) == before)
}

@Test func anEmptyObjectHasNoRoleToShowBeyondNotSet() throws {
    let found = try rows(Data("{}".utf8))
    #expect(found[.author]?.value.text(bundle: english.bundle, locale: english.locale) == "Not set" && found[.leadReviewer] == nil)
}

@Test func theFixtureConfigGivesEveryFixtureRepoItsThreeRoles() throws {
    let json = Data(fixtureConfig.utf8)
    let names = try #require(configRepoNames(json: json))
    #expect(names.count == 3)
    for name in names {
        #expect(try rows(json, name).keys.count == 3)
    }
    #expect(try rows(json, "acme/api")[.reviewer]?.value.text(bundle: english.bundle, locale: english.locale) == "acme-reviewer · codex · gpt-5-mini · high")
    #expect(try rows(json, "acme/web")[.reviewer]?.isOwn == false)
}

@Test func theRolesPageOfARepoIsTheGlobalRolesWithTheReposOwnOverThem() throws {
    let bots = ForgeBots(names: [])
    let global = try #require(rolesPage(config: config(), providers: nil, bots: bots))
    // a repo with nothing of its own reads as Roles does, the Lead reviewer that is off included
    let plain = try #require(repoRolesPage(config: config(), providers: nil, bots: bots, repo: "a/b"))
    #expect(plain.rows.map(\.role) == [.author, .reviewer, .leadReviewer] && plain.rows == global.rows && plain.rows[2].off)
    let own = try #require(repoRolesPage(config: config(repoAgents: #"{"author": {"model": "opus", "persona": {"prompt": "Be brief"}}}"#), providers: nil, bots: bots, repo: "a/b"))
    #expect(own.rows[0].fields == RoleFields(profile: "b-author", provider: "claude", model: "opus", effort: "high", persona: RolePersona(name: nil, prompt: "Be brief")))
    #expect(own.rows[1] == plain.rows[1])
    // another repo is not touched, and the global page is as it was
    #expect(try #require(repoRolesPage(config: config(repoAgents: #"{"author": {"model": "opus"}}"#), providers: nil, bots: bots, repo: "c/d")).rows[0].fields.model == "sonnet")
    #expect(try #require(rolesPage(config: config(repoAgents: #"{"author": {"model": "opus"}}"#), providers: nil, bots: bots)).rows[0].fields.model == "sonnet")
    #expect(repoRolesPage(config: Data("[]".utf8), providers: nil, bots: bots, repo: "a/b") == nil)
}

@Test func theLeadReviewerIsARoleOfTheRepoOnlyWhileTheGlobalConfigHasIt() throws {
    let bots = ForgeBots(names: [])
    // the global block of `config` has no lead reviewer
    let own = #"{"leadReviewer": {"model": "opus"}}"#
    let off = try #require(repoRolesPage(config: config(repoAgents: own), providers: nil, bots: bots, repo: "a/b"))
    #expect(off.rows.map(\.role) == [.author, .reviewer, .leadReviewer] && off.rows[2].off)
    let lead = Data(#"{"profiles": {"p": {"kind": "gh"}}, "agents": {"author": {"profile": "p", "provider": "claude", "model": "m"}, "reviewer": {"profile": "p", "provider": "claude", "model": "m"}, "leadReviewer": {"profile": "p", "provider": "claude", "model": "m"}}, "repos": [{"name": "a/b", "agents": {"leadReviewer": {"model": "opus"}}}]}"#.utf8)
    let page = try #require(repoRolesPage(config: lead, providers: nil, bots: bots, repo: "a/b"))
    #expect(page.rows.map(\.role) == [.author, .reviewer, .leadReviewer] && page.rows[2].fields.model == "opus")
}

private let twoExtras = #", "agents": {"author": {"profile": "b-author", "provider": "claude", "model": "sonnet"}, "reviewer": {"profile": "a-reviewer", "provider": "codex", "model": "gpt-5"}, "extraReviewers": {"seguridad": {"type": "security", "name": "Seguridad", "profile": "b-other", "provider": "claude", "model": "opus"}, "usabilidad": {"type": "ux", "name": "Usabilidad", "profile": "b-author", "provider": "codex", "model": "mini"}}}"#

private func withExtras(own: String?) -> Data {
    let entry = own.map { #", "agents": {"extraReviewers": \#($0)}"# } ?? ""
    return Data(#"{"profiles": {"a-reviewer": {"kind": "gh"}, "b-author": {"kind": "gh"}, "b-other": {"kind": "gh"}}\#(twoExtras), "repos": [{"name": "a/b"\#(entry)}, {"name": "c/d"}]}"#.utf8)
}

@Test func aRepoWithNoKeyListsTheGlobalReviewersInTheOrderOfTheFileNotAlphabetically() throws {
    let entry = { (key: String) in #""\#(key)": {"type": "t", "name": "N \#(key)", "profile": "a-reviewer", "provider": "codex", "model": "m"}"# }
    let global = "{" + ["zeta", "alfa", "mitad"].map(entry).joined(separator: ", ") + "}"
    let json = Data(#"{"profiles": {"a-reviewer": {"kind": "gh"}}, "agents": {"author": {"profile": "a-reviewer", "provider": "codex", "model": "m"}, "reviewer": {"profile": "a-reviewer", "provider": "codex", "model": "m"}, "extraReviewers": \#(global)}, "repos": [{"name": "a/b"}, {"name": "c/d", "agents": {"extraReviewers": {"uno": {"type": "t", "name": "Uno", "profile": "a-reviewer", "provider": "codex", "model": "m"}}}}]}"#.utf8)
    let bots = ForgeBots(names: [])
    // the repo follows Roles, which runs them in the order of the file: zeta, alfa, mitad
    #expect(try #require(repoExtraReviewers(config: json, providers: nil, bots: bots, repo: "a/b")).map(\.slot) == [.extra(key: "zeta"), .extra(key: "alfa"), .extra(key: "mitad")])
    #expect(try #require(rolesPage(config: json, providers: nil, bots: bots)).rows.filter { $0.slot.isExtra }.map(\.slot) == [.extra(key: "zeta"), .extra(key: "alfa"), .extra(key: "mitad")])
    #expect(try #require(repoExtraReviewers(config: json, providers: nil, bots: bots, repo: "c/d")).map(\.slot) == [.extra(key: "uno")])
}

@Test func aRepoWithNoKeyFollowsTheListOfRoles() throws {
    #expect(try #require(repoRoles(json: config(), repo: "a/b")).extras == .sameAsEverywhere)
    #expect(try #require(repoRoles(json: config(repoAgents: #"{"author": {"model": "opus"}}"#), repo: "a/b")).extras == .sameAsEverywhere)
    #expect(try #require(repoRoles(json: withExtras(own: nil), repo: "a/b")).extras == .sameAsEverywhere)
    let bots = ForgeBots(names: [])
    let reviewers = try #require(repoExtraReviewers(config: withExtras(own: nil), providers: nil, bots: bots, repo: "a/b"))
    #expect(reviewers.map(\.slot) == [.extra(key: "seguridad"), .extra(key: "usabilidad")] && reviewers.map(\.fields.model) == ["opus", "mini"])
    #expect(reviewers.map { $0.title() } == ["Seguridad", "Usabilidad"] && reviewers.map(\.type) == ["security", "ux"])
}

@Test func aReposOwnMapReplacesTheGlobalOneWholeAndKeepsItsOrder() throws {
    let own = #"{"rendimiento": {"type": "performance", "name": "Rendimiento", "profile": "a-reviewer", "provider": "ollama", "model": "qwen", "effort": "low"}}"#
    #expect(try #require(repoRoles(json: withExtras(own: own), repo: "a/b")).extras == .ownList)
    let reviewers = try #require(repoExtraReviewers(config: withExtras(own: own), providers: nil, bots: ForgeBots(names: []), repo: "a/b"))
    #expect(reviewers.count == 1 && reviewers[0].slot == .extra(key: "rendimiento") && reviewers[0].title() == "Rendimiento" && reviewers[0].type == "performance")
    #expect(reviewers[0].fields == RoleFields(profile: "a-reviewer", provider: "ollama", model: "qwen", effort: "low"))
    #expect(reviewers[0].identity == .gh && reviewers[0].headline(bundle: english.bundle, locale: english.locale) == "qwen · low · a-reviewer")
    // another repo keeps the global list
    #expect(try #require(repoExtraReviewers(config: withExtras(own: own), providers: nil, bots: ForgeBots(names: []), repo: "c/d")).count == 2)
    #expect(try #require(repoRoles(json: withExtras(own: own), repo: "c/d")).extras == .sameAsEverywhere)
}

@Test func anEmptyMapLeavesOnlyTheReviewer() throws {
    #expect(try #require(repoRoles(json: withExtras(own: "{}"), repo: "a/b")).extras == .noExtras)
    let bots = ForgeBots(names: [])
    #expect(try #require(repoExtraReviewers(config: withExtras(own: "{}"), providers: nil, bots: bots, repo: "a/b")).isEmpty)
    // the rail of the repo has the Reviewer alone, with or without extras
    #expect(try #require(repoRolesPage(config: withExtras(own: "{}"), providers: nil, bots: bots, repo: "a/b")).rows.map(\.slot) == [.author, .reviewer, .lead])
    #expect(try #require(repoRolesPage(config: withExtras(own: nil), providers: nil, bots: bots, repo: "a/b")).rows.map(\.slot) == [.author, .reviewer, .lead])
}

@Test func theOrderOfARepoOwnMapIsTheOrderOfTheFileWhateverTheRepoIsAndTheMapsAreNotMerged() throws {
    let entry = { (key: String) in #""\#(key)": {"type": "t", "name": "N \#(key)", "profile": "a-reviewer", "provider": "codex", "model": "m"}"# }
    let own = "{" + ["zeta", "alfa", "mitad"].map(entry).joined(separator: ", ") + "}"
    let json = Data(#"{"profiles": {"a-reviewer": {"kind": "gh"}}\#(twoExtras), "repos": [{"name": "c/d"}, {"name": "a/b", "agents": {"extraReviewers": \#(own)}}]}"#.utf8)
    let reviewers = try #require(repoExtraReviewers(config: json, providers: nil, bots: ForgeBots(names: []), repo: "a/b"))
    // the global keys are not in it: the repo's map replaces the whole
    #expect(reviewers.map(\.slot) == [.extra(key: "zeta"), .extra(key: "alfa"), .extra(key: "mitad")])
    #expect(try #require(repoExtraReviewers(config: json, providers: nil, bots: ForgeBots(names: []), repo: "c/d")).map(\.slot) == [.extra(key: "seguridad"), .extra(key: "usabilidad")])
    // a list is not a map: the engine refuses it, and the app reads the repo as following Roles
    #expect(try #require(repoRoles(json: withExtras(own: "[]"), repo: "a/b")).extras == .sameAsEverywhere)
}

@Test func theExtraReviewersOfAConfigThatIsNotAJSONObjectAreNotRead() {
    #expect(repoExtraReviewers(config: Data("[]".utf8), providers: nil, bots: ForgeBots(names: []), repo: "a/b") == nil)
}

@Test func theFixtureHasARepoWithAnOwnMapAndOneWithNone() throws {
    let json = Data(fixtureConfig.utf8)
    let own = try #require(repoExtraReviewers(config: json, providers: nil, bots: ForgeBots(names: []), repo: "acme/web"))
    #expect(own.map(\.slot) == [.extra(key: "rendimiento")] && own[0].title() == "Rendimiento")
    #expect(try #require(repoRoles(json: json, repo: "acme/web")).extras == .ownList)
    #expect(try #require(repoRoles(json: json, repo: "acme/a-really-long-repository-name-for-the-sidebar")).extras == .noExtras)
    #expect(try #require(repoRoles(json: json, repo: "acme/api")).extras == .sameAsEverywhere)
}

@Test func theStatesSayWhatTheyAreInEnglishAndSpanish() {
    #expect(RepoExtraReviewers.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["Same as everywhere", "Own list", "None"])
    #expect(RepoExtraReviewers.allCases.map { $0.title(bundle: spanish.bundle, locale: spanish.locale) } == ["Igual que en todas partes", "Lista propia", "Ninguno"])
    // an engine that cannot write the list says the app only shows it, in both languages; one that can does not
    for state in RepoExtraReviewers.allCases {
        #expect(state.footer(editable: false, bundle: english.bundle, locale: english.locale).hasSuffix("edit it in engine.json."))
        #expect(state.footer(editable: false, bundle: spanish.bundle, locale: spanish.locale).hasSuffix("edítala en engine.json."))
        #expect(state.footer(editable: true, bundle: english.bundle, locale: english.locale).contains("engine.json") == false)
    }
    // an own list says its persona, failover steps and skills are the Reviewer's
    #expect(RepoExtraReviewers.ownList.footer(editable: true, bundle: english.bundle, locale: english.locale).hasSuffix("persona, failover steps and skills come from the Reviewer."))
    #expect(RepoExtraReviewers.ownList.footer(editable: true, bundle: spanish.bundle, locale: spanish.locale).hasSuffix("vienen del Revisor."))
}
