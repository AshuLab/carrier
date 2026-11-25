import Foundation
import Testing
@testable import CarrierCore

// What the Agents page reads of the global roles: the note under Author and Reviewer when they resolve to one identity. The write is the engine's (src/config/role-edit.ts).

private let bots = ["acme-author", "acme-reviewer", "spare"]
private let base = #"""
{"profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "spare": {"kind": "forge", "agent": "spare"}, "again": {"kind": "forge", "agent": "spare"}},
 "agents": {"author": {"profile": "spare", "provider": "claude", "model": "m"},
            "reviewer": {"profile": "spare", "provider": "codex", "model": "g"}},
 "repos": [{"name": "a/b"}]}
"""#

@Test func theSamePersonAsAuthorAndReviewerGetsTheSignatureNote() throws {
    let names = ForgeBots(names: bots, note: nil)
    let shown = try #require(agentsPage(config: Data(base.utf8), providers: nil, bots: names, bundle: english.bundle, locale: english.locale))
    #expect(shown.sharedNote == "Author and Reviewer both work as spare: the signature will show it.")

    // two profile names for the same bot are one account too
    let twoNames = base.replacingOccurrences(of: #""reviewer": {"profile": "spare""#, with: #""reviewer": {"profile": "again""#)
    let page = try #require(agentsPage(config: Data(twoNames.utf8), providers: nil, bots: names, bundle: english.bundle, locale: english.locale))
    #expect(page.sharedNote?.contains("are one account") == true)
}
