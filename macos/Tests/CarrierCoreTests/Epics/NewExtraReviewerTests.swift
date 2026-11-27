import Foundation
import Testing
@testable import CarrierCore

// The Add a reviewer draft of the Roles page: that nothing is sent until the reviewer has a name, a type, an identity, an account and a model, and what the screen says meanwhile.
// What the engine refuses (a name another reviewer has) is the engine's (src/config/role-edit.ts) and the fixture engine's (`FixtureServerTests`).

private let config = #"""
{"profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}},
 "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m"},
            "reviewer": {"profile": "acme-author", "provider": "codex", "model": "gpt-5"},
            "extraReviewers": {"seguridad": {"type": "security", "name": "Seguridad", "profile": "acme-author", "provider": "claude", "model": "m"}}},
 "failover": {"roles": {"reviewer": [{"provider": "claude", "model": "opus"}]}}}
"""#

private func page() throws -> RolesPage {
    try #require(rolesPage(config: Data(config.utf8), providers: nil, bots: ForgeBots(names: ["acme-author"], note: nil), bundle: english.bundle, locale: english.locale))
}

@Test func theTypeStartsOnGeneralAndTheDraftIsCompleteOnlyWithNameTypeIdentityAccountAndModel() {
    var draft = NewExtraReviewer()
    #expect(draft.type == "general" && draft.isComplete == false && draft.missing == [.name, .identity, .account, .model] && draft.request == nil)
    draft.name = "  Accesibilidad "
    draft.apply(.bot("acme-author"))
    draft.apply(.effort("low"))
    draft.apply(.model("   "))
    #expect(draft.missing == [.account, .model])
    draft.apply(.provider("codex"))
    #expect(draft.isComplete == false)
    draft.apply(.model(" gpt-5 "))
    // the whole entry goes in one request, as it was chosen (the engine trims)
    #expect(draft.isComplete && draft.request == ExtraReviewerDraft(name: "  Accesibilidad ", type: "general", identity: .bot("acme-author"), provider: "codex", model: " gpt-5 ", effort: "low"))
    draft.type = " "
    #expect(draft.missing == [.type] && draft.request == nil)
}

@Test func theScreenSaysWhatIsMissingAndThatNothingIsWrittenUntilThen() {
    var draft = NewExtraReviewer()
    #expect(draft.hint(bundle: english.bundle, locale: english.locale) == "Not saved yet. It needs a name, an identity, an account and a model; nothing is written until it has them, and leaving this screen drops it.")
    #expect(draft.hint(bundle: spanish.bundle, locale: spanish.locale) == "Sin guardar todavía. Necesita un nombre, una identidad, una cuenta y un modelo; no se escribe nada hasta que los tenga, y al salir de esta pantalla se descarta.")
    draft.name = "Docs"
    draft.apply(.gh)
    draft.apply(.provider("codex"))
    #expect(draft.hint(bundle: english.bundle, locale: english.locale) == "Not saved yet. It needs a model; nothing is written until it has them, and leaving this screen drops it.")
    draft.apply(.model("gpt-5"))
    #expect(draft.hint(bundle: english.bundle, locale: english.locale) == nil)
}

@Test func theDraftIsShownBeforeTheLeadWithTheReviewersStepsAndNoKey() throws {
    var draft = NewExtraReviewer()
    draft.name = "Docs"
    draft.apply(.bot("acme-author"))
    let found = try page()
    let shown = draft.row(in: found, bundle: english.bundle, locale: english.locale)
    #expect(shown.drafting && shown.slot == .draft && shown.title(bundle: english.bundle, locale: english.locale) == "Docs" && shown.type == "general")
    #expect(shown.identity == .forge("acme-author") && shown.fields.profile == "acme-author" && shown.ownSteps == false && shown.steps.map(\.text) == ["claude · opus"])
    #expect(found.adding(shown).rows.map(\.slot) == [.author, .reviewer, .extra(key: "seguridad"), .draft, .lead])
    // a place's name that is the draft's can never be a key
    #expect(RoleSlot(name: RoleSlot.draftPlaceName) == nil)
}

@Test func aNameAnotherReviewerHasIsRefusedBeforeAnythingIsSentWhateverItsCaseAndSaysSo() throws {
    var draft = NewExtraReviewer()
    draft.apply(.gh)
    draft.apply(.provider("codex"))
    draft.apply(.model("gpt-5"))
    let found = try page()
    // the name of the Reviewer or of the Author is not another reviewer's: the engine's rule is among the extra reviewers
    for name in ["Reviewer", "", "Seguridad API"] {
        draft.name = name
        #expect(draft.nameTaken(in: found) == false)
    }
    for name in ["Seguridad", " seguridad ", "SEGURIDAD"] {
        draft.name = name
        #expect(draft.nameTaken(in: found) && draft.isComplete)
        #expect(draft.hint(in: found, bundle: english.bundle, locale: english.locale) == "Another reviewer here is already called \(name.trimmingCharacters(in: .whitespaces)). Pick another name.")
    }
    // the reviewer being added is not a reviewer of the page: the shown draft never collides with itself
    draft.name = "Docs"
    #expect(draft.nameTaken(in: found.adding(draft.row(in: found))) == false && draft.hint(in: found) == nil)
    #expect(draft.hint(in: found, bundle: spanish.bundle, locale: spanish.locale) == nil)
    draft.name = "seguridad"
    #expect(draft.hint(in: found, bundle: spanish.bundle, locale: spanish.locale) == "Otro revisor de aquí ya se llama seguridad. Elige otro nombre.")
}
