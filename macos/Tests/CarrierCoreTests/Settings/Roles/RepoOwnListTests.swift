import Foundation
import Testing

@testable import CarrierCore

// A repo's own list of extra reviewers as Watching edits it (`RepoOwnList.swift`): the three choices, each field of an entry, removing, adding a draft, names and keys.

private func entry(_ key: String, _ name: String, type: String = "general", profile: String = "b-other", provider: String = "claude", model: String = "opus", effort: String? = nil) -> RepoExtraReviewer {
    RepoExtraReviewer(key: key, type: type, name: name, profile: profile, provider: provider, model: model, effort: effort)
}

@Test func theMapOfRolesAndTheReposOwnMapAreReadAsEntriesInTheOrderOfTheFile() throws {
    let json = Data(#"{"profiles": {}, "agents": {"extraReviewers": {"zeta": {"type": "ux", "name": "Zeta", "profile": "p", "provider": "codex", "model": "m", "effort": "low", "persona": {"name": "Ada"}}, "alfa": {"type": "t", "name": "Alfa", "profile": "p", "provider": "codex"}}}, "repos": [{"name": "c/d"}, {"name": "a/b", "agents": {"extraReviewers": {"uno": {"type": "t", "name": "Uno", "profile": "p", "provider": "claude", "model": "m"}}}}]}"#.utf8)
    // the persona and failover steps are not carried: a repo's entry is the Reviewer's for them; a field the entry lacks is empty, and the engine refuses it by name
    #expect(rolesExtraEntries(config: json) == [entry("zeta", "Zeta", type: "ux", profile: "p", provider: "codex", model: "m", effort: "low"), entry("alfa", "Alfa", type: "t", profile: "p", provider: "codex", model: "")])
    #expect(repoOwnEntries(config: json, repo: "a/b") == [entry("uno", "Uno", type: "t", profile: "p", provider: "claude", model: "m")])
    #expect(repoOwnEntries(config: json, repo: "c/d").isEmpty && repoOwnEntries(config: json, repo: "x/y").isEmpty && repoOwnEntries(config: Data("[]".utf8), repo: "a/b").isEmpty)
}

@Test func theThreeChoicesEachSendOneRequest() {
    let roles = [entry("seguridad", "Seguridad", type: "security", effort: "high"), entry("usabilidad", "Usabilidad", type: "ux", profile: "b-author", provider: "codex", model: "mini")]
    // Same as everywhere takes the key out and None is an empty map, whatever Roles has
    #expect(RepoExtraReviewers.sameAsEverywhere.choosing(repo: "a/b", roles: roles) == .repoExtraReviewers(repo: "a/b", nil))
    #expect(RepoExtraReviewers.noExtras.choosing(repo: "a/b", roles: roles) == .repoExtraReviewers(repo: "a/b", []))
    // Own list starts as a copy of the map of Roles, whole and in its order
    #expect(RepoExtraReviewers.ownList.choosing(repo: "a/b", roles: roles) == .repoExtraReviewers(repo: "a/b", roles))
    // with no reviewer in Roles an own list would be `{}`, which is None: nothing is sent until its first entry
    #expect(RepoExtraReviewers.ownList.choosing(repo: "a/b", roles: []) == nil)
    #expect(RepoExtraReviewers.sameAsEverywhere.choosing(repo: "a/b", roles: []) == .repoExtraReviewers(repo: "a/b", nil))
}

@Test func eachFieldOfAnOwnListEntryIsSentWithTheWholeMapAndTheKeyStays() throws {
    let list = RepoOwnList([entry("seguridad", "Seguridad", effort: "high"), entry("usabilidad", "Usabilidad", provider: "codex", model: "mini")])
    func sent(_ edit: RepoReviewerEdit, _ key: String = "seguridad") throws -> [RepoExtraReviewer] {
        guard case .repoExtraReviewers("a/b", let entries?) = try #require(list.applying(edit, to: key)).request(repo: "a/b") else { throw EditError.notTheRequest }
        return entries
    }
    // the other entry and the order are as they were
    #expect(try sent(.name("Seguridad del front")) == [entry("seguridad", "Seguridad del front", effort: "high"), list.entries[1]])
    #expect(try sent(.type("security")) == [entry("seguridad", "Seguridad", type: "security", effort: "high"), list.entries[1]])
    #expect(try sent(.profile("b-author")) == [entry("seguridad", "Seguridad", profile: "b-author", effort: "high"), list.entries[1]])
    #expect(try sent(.account(provider: "codex", model: "gpt-5"), "usabilidad") == [list.entries[0], entry("usabilidad", "Usabilidad", provider: "codex", model: "gpt-5")])
    // an account alone keeps the model; the effort goes out with nil
    #expect(try sent(.account(provider: "ollama", model: nil))[0] == entry("seguridad", "Seguridad", provider: "ollama", effort: "high"))
    #expect(try sent(.effort(nil))[0] == entry("seguridad", "Seguridad"))
    #expect(try sent(.effort("low"))[0].effort == "low")
    // an entry that is not there leaves the list as it is
    #expect(list.applying(.name("x"), to: "ghost") == list)
}

private enum EditError: Error { case notTheRequest }

@Test func removingAnEntrySendsTheOthersWholeAndTheLastOneSendsAnEmptyMap() {
    let list = RepoOwnList([entry("a", "A"), entry("b", "B"), entry("c", "C")])
    #expect(list.removing("b").request(repo: "a/b") == .repoExtraReviewers(repo: "a/b", [entry("a", "A"), entry("c", "C")]))
    #expect(RepoOwnList([entry("a", "A")]).removing("a").request(repo: "a/b") == .repoExtraReviewers(repo: "a/b", []))
}

@Test func anEntryIsAddedOnlyOnceItHasANameATypeAnIdentityAnAccountAndAModel() throws {
    let list = RepoOwnList([entry("seguridad", "Seguridad")])
    var draft = RepoExtraReviewer.draft
    // a new reviewer is a `general` one: it needs the other four
    #expect(draft.missing == [.name, .identity, .account, .model] && list.adding(draft) == nil)
    #expect(list.hint(for: draft, bundle: english.bundle, locale: english.locale) == "Not saved yet. It needs a name, an identity, an account and a model; nothing is written until it has them, and leaving this screen drops it.")
    #expect(list.hint(for: draft, bundle: spanish.bundle, locale: spanish.locale) == "Sin guardar todavía. Necesita un nombre, una identidad, una cuenta y un modelo; no se escribe nada hasta que los tenga, y al salir de esta pantalla se descarta.")
    for edit in [RepoReviewerEdit.name("  "), .profile("b-other"), .account(provider: "codex", model: nil)] {
        draft = draft.applying(edit)
        #expect(list.adding(draft) == nil)
    }
    // blank is not a name or a model, and an empty type is not a type
    draft = draft.applying(.type(" "))
    draft = draft.applying(.account(provider: "codex", model: "gpt-5"))
    #expect(draft.missing == [.name, .type])
    draft = draft.applying(.type("ux"))
    draft = draft.applying(.name(" Accesibilidad móvil "))
    draft = draft.applying(.effort("low"))
    // the key comes from the name, the entry is whole and goes at the end of the whole map
    #expect(list.adding(draft)?.entries == [entry("seguridad", "Seguridad"), entry("accesibilidad-movil", "Accesibilidad móvil", type: "ux", profile: "b-other", provider: "codex", model: "gpt-5", effort: "low")])
    #expect(list.hint(for: draft) == nil)
}

/// The names and keys the engine's own test writes (`src/config/extra-reviewer-key.test.ts`, `Tests/Fixtures/extra-reviewer-keys.json`): the app derives the key of a new entry itself, so the two must agree.
@Test func theKeyTheAppDerivesIsTheOneTheEnginesGoldenSaysForEveryName() throws {
    struct Case: Decodable { var name: String; var taken: [String]; var key: String }
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: testPaths().fixtures.appendingPathComponent("extra-reviewer-keys.json")))
    #expect(cases.count > 20)
    for found in cases { #expect(extraReviewerKey(found.name, taken: Set(found.taken)) == found.key, Comment(rawValue: "\(found.name.prefix(12)) taken \(found.taken.count)")) }
}

@Test func theKeyOfANewEntryIsNotOneAnotherHasOrOneARoleUses() {
    #expect(extraReviewerKey("Seguridad API", taken: []) == "seguridad-api")
    #expect(extraReviewerKey("Seguridad API", taken: ["seguridad-api"]) == "seguridad-api-2")
    #expect(extraReviewerKey("Lead", taken: []) == "lead-2" && extraReviewerKey("Reviewer", taken: []) == "reviewer-2")
    #expect(extraReviewerKey("3D", taken: []) == "r-3d" && extraReviewerKey("???", taken: []) == "extra")
    // a name that differs only in its case from another's is refused, though its key would differ: names differ whatever their case
    var draft = RepoExtraReviewer.draft
    [RepoReviewerEdit.name("Seguridad"), .profile("p"), .account(provider: "claude", model: "m")].forEach { draft = draft.applying($0) }
    #expect(RepoOwnList([entry("seguridad", "seguridad")]).adding(draft) == nil)
}

@Test func twoEntriesNeverShareANameWhateverItsCaseAndNothingIsSentForIt() throws {
    let list = RepoOwnList([entry("a", "Seguridad"), entry("b", "Usabilidad")])
    #expect(list.nameTaken(" usabilidad ") && list.nameTaken("SEGURIDAD") && list.nameTaken("Rendimiento") == false)
    // an entry keeps its own name, and takes no other's
    #expect(list.nameTaken("Seguridad", except: "a") == false && list.applying(.name("seguridad"), to: "a") != nil)
    #expect(list.applying(.name("usabilidad"), to: "a") == nil)
    var draft = RepoExtraReviewer.draft
    [RepoReviewerEdit.name("usabilidad"), .profile("p"), .account(provider: "claude", model: "m")].forEach { draft = draft.applying($0) }
    #expect(draft.isComplete && list.adding(draft) == nil)
    #expect(list.hint(for: draft, bundle: english.bundle, locale: english.locale) == "Another reviewer here is already called usabilidad. Pick another name.")
    #expect(list.hint(for: draft, bundle: spanish.bundle, locale: spanish.locale) == "Otro revisor de aquí ya se llama usabilidad. Elige otro nombre.")
}

@Test func anOwnListHoldsThreeEntriesAtMost() {
    let full = RepoOwnList([entry("a", "A"), entry("b", "B"), entry("c", "C")])
    var draft = RepoExtraReviewer.draft
    [RepoReviewerEdit.name("D"), .profile("p"), .account(provider: "claude", model: "m")].forEach { draft = draft.applying($0) }
    #expect(full.canAdd == false && full.adding(draft) == nil)
    #expect(RepoOwnList([entry("a", "A"), entry("b", "B")]).canAdd && RepoOwnList([entry("a", "A"), entry("b", "B")]).adding(draft)?.entries.count == 3)
}
