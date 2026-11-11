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
    #expect(author.value.text == "b-author · claude · sonnet · high")
    #expect(author.value.persona == RolePersona(name: "Ada", prompt: nil))
    #expect(found[.reviewer]?.value.text == "a-reviewer · codex · gpt-5")
}

@Test func anOverrideOfOnlyTheModelMixesOwnAndInherited() throws {
    let author = try #require(rows(config(repoAgents: #"{"author": {"model": "opus"}}"#))[.author])
    #expect(author.isOwn && author.own == RoleFields(model: "opus"))
    #expect(author.value.text == "b-author · claude · opus · high")
    #expect(author.inherited.text == "b-author · claude · sonnet · high")
}

@Test func aFullOverrideIsTheOwnValue() throws {
    let own = #"{"reviewer": {"profile": "b-other", "provider": "ollama", "model": "qwen", "effort": "max", "persona": {"prompt": "Be brief"}}}"#
    let reviewer = try #require(rows(config(repoAgents: own))[.reviewer])
    #expect(reviewer.value.text == "b-other · ollama · qwen · max" && reviewer.value == reviewer.own)
    #expect(reviewer.inherited.text == "a-reviewer · codex · gpt-5")
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
    #expect(try rows(with)[.leadReviewer]?.value.text == "b-other · claude · opus")
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
    #expect(found[.author]?.value.text == "Not set" && found[.leadReviewer] == nil)
}

@Test func theFixtureConfigGivesEveryFixtureRepoItsThreeRoles() throws {
    let json = Data(fixtureConfig.utf8)
    let names = try #require(configRepoNames(json: json))
    #expect(names.count == 3)
    for name in names {
        #expect(try rows(json, name).keys.count == 3)
    }
    #expect(try rows(json, "acme/api")[.reviewer]?.value.text == "acme-reviewer · codex · gpt-5-mini · high")
    #expect(try rows(json, "acme/web")[.reviewer]?.isOwn == false)
}
