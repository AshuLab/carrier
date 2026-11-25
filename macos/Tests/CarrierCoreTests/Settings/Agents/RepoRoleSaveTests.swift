import Foundation
import Testing
@testable import CarrierCore

// What the Agents page checks of a repo's role while the person types, and what it reads of the accounts. The write is the engine's (src/config/role-edit.ts).

private let accounts = ["claude", "codex", "agy"]
private let base = #"""
{"profiles": {"author": {"kind": "gh"}, "reviewer": {"kind": "gh"}, "other": {"kind": "gh"}},
 "agents": {"author": {"profile": "author", "provider": "claude", "model": "m"}, "reviewer": {"profile": "reviewer", "provider": "codex", "model": "m"}},
 "repos": [{"name": "a/b", "extra": true}, {"name": "c/d"}]}
"""#

@Test func aNameThatIsNotDeclaredIsSaidInWordsWhileTheFieldsAreChecked() {
    let profiles = ["author", "reviewer", "other"]
    func problems(_ fields: RoleFields) -> [String] { fields.normalized().problems(profiles: profiles, accounts: accounts) }
    #expect(problems(RoleFields(profile: "ghost")) == ["Identity “ghost” is not declared in profiles. Pick another one."])
    #expect(problems(RoleFields(provider: "ollama")) == ["Provider “ollama” is not an account of providers.json. Pick another one."])
    #expect(problems(RoleFields(effort: "ultra")) == ["Effort must be one of low, medium, high, xhigh, max."])
    #expect(problems(RoleFields(persona: RolePersona(name: String(repeating: "x", count: 41)))) == ["The persona’s name is one line of up to 40 characters."])
    #expect(problems(RoleFields(profile: "author", provider: "claude", model: " m ", effort: "high")).isEmpty)
    // a model of only spaces is none
    #expect(RoleFields(model: "   ").normalized().model == nil)
}

@Test func theSameIdentityOnAuthorAndReviewerIsAcceptedAndTheSignatureNoteSaysSo() throws {
    let roles = try #require(repoRoles(json: Data(base.utf8), repo: "a/b"))
    #expect(signatureNote(roles.rows) == nil)
    let same = base.replacingOccurrences(of: #""profile": "reviewer""#, with: #""profile": "author""#)
    let after = try #require(repoRoles(json: Data(same.utf8), repo: "a/b"))
    #expect(signatureNote(after.rows)?.contains("signature will show it") == true)
}

@Test func theAccountsAreThoseOfProvidersJSONOrTheThreeDefaults() {
    #expect(declaredAccounts(providersJSON: nil) == ["claude", "codex", "agy"])
    #expect(declaredAccounts(providersJSON: Data("{}".utf8)) == ["claude", "codex", "agy"])
    #expect(declaredAccounts(providersJSON: Data(#"{"providers":{"work":{"harness":"claude"},"home":{"harness":"codex"}}}"#.utf8)) == ["home", "work"])
}

@Test func eachAccountGetsTheIconOfTheHarnessItRuns() {
    let json = #"{"providers":{"pro":{"harness":"claude"},"codex":{"harness":"codex"},"agy":{"harness":"agy"},"teams":{"harness":"claude"},"bare":{}}}"#
    #expect(accountIcons(providersJSON: Data(json.utf8)) == ["pro": "claude", "codex": "codex", "agy": "antigravity", "teams": "claude", "bare": "bare"])
    #expect(accountIcons(providersJSON: nil) == ["claude": "claude", "codex": "codex", "agy": "antigravity"])
}
