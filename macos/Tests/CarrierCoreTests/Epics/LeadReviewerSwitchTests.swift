import Foundation
import Testing
@testable import CarrierCore

// The Use a lead reviewer switch of the Agents page: that turning it on sends nothing until identity, provider and model are chosen, and what the page's model says about the dimmed page.
// What turning it off removes is the engine's (src/config/role-edit.ts).

private let bots = ["acme-author", "acme-lead"]
private let withLead = #"""
{"keep": {"deep": [1]}, "orchestratorProfile": "acme-author",
 "profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
 "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m"},
            "leadReviewer": {"profile": "acme-lead", "provider": "claude", "model": "opus", "effort": "high", "extra": true}},
 "failover": {"triggers": ["usage_limit"], "roles": {"author": [{"provider": "codex"}], "leadReviewer": [{"provider": "codex", "model": "gpt-5"}]}},
 "repos": [{"name": "a/b"}]}
"""#
private let withoutLead = #"""
{"keep": 1, "profiles": {"acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
 "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}}}
"""#

private func complete() -> LeadReviewerDraft {
    var draft = LeadReviewerDraft()
    draft.apply(.bot("acme-lead"))
    draft.apply(.provider("codex"))
    draft.apply(.model(" gpt-5 "))
    return draft
}

@Test func turningItOnSendsNothingUntilIdentityProviderAndModelAreChosen() throws {
    var draft = LeadReviewerDraft()
    #expect(draft.isComplete == false && draft.missing == ["an identity", "a provider", "a model"])
    #expect(draft.hint == "Choose an identity, a provider and a model to turn it on. Nothing is written until then.")
    draft.apply(.bot("acme-lead"))
    draft.apply(.effort("max"))
    draft.apply(.model("   "))
    #expect(draft.missing == ["a provider", "a model"])
    // once the three are chosen the whole role is what the draft sends, in one request
    draft.apply(.provider("codex"))
    draft.apply(.model(" gpt-5 "))
    #expect(draft.isComplete && draft.hint == nil && draft.changes == [.bot("acme-lead"), .provider("codex"), .model(" gpt-5 "), .effort("max")])
}

@Test func theDraftIsShownInPlaceOfTheEmptyRoleAndTheSwitchRowTellsWhatOffDoes() throws {
    let off = try #require(agentsPage(config: Data(withoutLead.utf8), providers: nil, bots: ForgeBots(names: bots, note: nil))?.rows.first { $0.role == .leadReviewer })
    #expect(off.off && off.usable(turningOn: false) == false && off.usable(turningOn: true))
    #expect(off.switchDetail == "Off: the file has no lead reviewer")
    let shown = complete().shown(in: off)
    #expect(shown.fields == RoleFields(profile: "acme-lead", provider: "codex", model: " gpt-5 ") && shown.identity == .forge("acme-lead"))

    let on = try #require(agentsPage(config: Data(withLead.utf8), providers: nil, bots: ForgeBots(names: bots, note: nil))?.rows.first { $0.role == .leadReviewer })
    #expect(on.off == false && on.usable(turningOn: false))
    #expect(on.switchDetail.contains("removes the lead reviewer and its failover steps from the file"))
}

// MARK: the engine is asked to reload
