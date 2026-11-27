import Foundation
import Testing
@testable import CarrierCore

// What a role's screen sends as a field changes: the fixed roles keep their requests and an extra reviewer's point at it by its key, which does not change with its name (ADR 0057).
// What the engine writes is the engine's (src/config/role-edit.ts); how each request is encoded is `EngineConfigRequestsTests`.

private let reviewer = RoleSlot.extra(key: "seguridad-api")

@Test func eachEditOfAnExtraReviewerPointsAtItByItsKey() {
    #expect(reviewer.edit([.bot("acme-seguridad"), .provider("codex"), .model("gpt-5"), .effort(nil)]) == .extraReviewerRole(key: "seguridad-api", name: nil, type: nil, [.bot("acme-seguridad"), .provider("codex"), .model("gpt-5"), .effort(nil)]))
    #expect(reviewer.edit([.gh]) == .extraReviewerRole(key: "seguridad-api", name: nil, type: nil, [.gh]))
    #expect(reviewer.persona(name: "Skeptic", prompt: nil) == .extraReviewerPersona(key: "seguridad-api", name: "Skeptic", prompt: nil))
    #expect(reviewer.failover(first: FailoverStep(provider: "codex", model: "gpt-5"), second: nil) == .extraReviewerFailover(key: "seguridad-api", first: FailoverStep(provider: "codex", model: "gpt-5"), second: nil))
    // Same as Reviewer again: both steps nil, which takes the reviewer's own list out
    #expect(reviewer.failover(first: nil, second: nil) == .extraReviewerFailover(key: "seguridad-api", first: nil, second: nil))
}

@Test func theNameAndTheTypeAreChangedAlone_andTheKeyIsTheSameWhateverTheNameSays() {
    #expect(reviewer.renamed("Seguridad del front") == .extraReviewerRole(key: "seguridad-api", name: "Seguridad del front", type: nil, []))
    #expect(reviewer.retyped("security") == .extraReviewerRole(key: "seguridad-api", name: nil, type: "security", []))
    #expect(reviewer.removal == .removeExtraReviewer(key: "seguridad-api"))
    // the fixed roles have none of the three
    #expect(RoleSlot.reviewer.renamed("x") == nil && RoleSlot.lead.retyped("x") == nil && RoleSlot.author.removal == nil)
}

@Test func theFixedRolesKeepTheRequestsTheyUse() {
    #expect(RoleSlot.author.edit([.gh]) == .role(.author, [.gh]))
    #expect(RoleSlot.lead.edit([.model("m")]) == .role(.leadReviewer, [.model("m")]))
    #expect(RoleSlot.reviewer.persona(name: nil, prompt: "p") == .persona(role: .reviewer, name: nil, prompt: "p"))
    #expect(RoleSlot.lead.failover(first: FailoverStep(provider: "codex"), second: nil) == .failover(role: .leadReviewer, first: FailoverStep(provider: "codex"), second: nil))
}

@MainActor @Test func theRequestsGoOutThroughTheQueueInTheOrderTheyWereMade() async throws {
    let sent = Sent()
    let queue = EngineConfigQueue()
    let send: SendEngineConfig = { change in
        await sent.add(change.command)
        return EngineConfigReply(engine: .applied)
    }
    for change in [reviewer.renamed("Docs")!, reviewer.edit([.model("m")]), reviewer.removal!] {
        _ = await queue.save(change, send: send)
    }
    #expect(await sent.commands == ["editRole", "editRole", "removeExtraReviewer"])
}

private actor Sent {
    var commands: [String] = []
    func add(_ command: String) { commands.append(command) }
}

@Test func addAReviewerIsOfferedOnlyToAnEngineThatAnnouncesExtraReviewersAndNotAtThree() {
    #expect(ExtraReviewerOffer(canEdit: false, count: 0).showsAdd == false && ExtraReviewerOffer(canEdit: false, count: 0).canAdd == false)
    let none = ExtraReviewerOffer(canEdit: true, count: 0)
    #expect(none.showsAdd && none.canAdd && none.addDetail(bundle: english.bundle, locale: english.locale) == "3 more reviewers can run")
    #expect(ExtraReviewerOffer(canEdit: true, count: 2).addDetail(bundle: english.bundle, locale: english.locale) == "1 more reviewer can run")
    let full = ExtraReviewerOffer(canEdit: true, count: 3)
    #expect(full.showsAdd && full.canAdd == false && full.addDetail(bundle: english.bundle, locale: english.locale) == "Four reviewers is the most")
    #expect(full.addDetail(bundle: spanish.bundle, locale: spanish.locale) == "Cuatro revisores es el máximo")
}

@Test func theOfferCountsTheExtraReviewersOfThePage() throws {
    let config = #"{"profiles": {}, "agents": {"author": {"profile": "a", "provider": "claude", "model": "m"}, "extraReviewers": {"a": {"type": "ux", "name": "A", "profile": "a", "provider": "claude", "model": "m"}, "b": {"type": "ux", "name": "B", "profile": "a", "provider": "claude", "model": "m"}}}}"#
    let page = try #require(rolesPage(config: Data(config.utf8), providers: nil, bots: ForgeBots(names: [], note: nil)))
    #expect(ExtraReviewerOffer(canEdit: true, page: page) == ExtraReviewerOffer(canEdit: true, count: 2))
}
