import Foundation
import Testing
@testable import CarrierCore

// What the Agents page reads of a failover step. The write is the engine's (src/config/role-edit.ts).

@Test func aStepKeepsItsOwnEffortAndAReadStepSaysIt() throws {
    let config = #"""
    {"profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}},
     "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m"}},
     "failover": {"roles": {"author": [{"provider": "codex", "model": "g", "effort": "low"}, {"provider": "agy"}]}}}
    """#
    let page = try #require(agentsPage(config: Data(config.utf8), providers: nil, bots: ForgeBots(names: [], note: nil)))
    let steps = try #require(page.rows.first { $0.role == .author }?.steps)
    #expect(steps == [FailoverStep(provider: "codex", model: "g", effort: "low"), FailoverStep(provider: "agy")])
}
