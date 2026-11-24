import Foundation
@testable import CarrierCore

/// The engine's `config` requests in memory: what was sent, in order, and what it answers; `failure` makes it throw instead.
final class FakeEngineConfig {
    private(set) var sent: [EngineConfigChange] = []
    var reply = EngineConfigReply(engine: .applied)
    var failure: Error?

    var send: SendEngineConfig {
        { [self] change in
            sent.append(change)
            if let failure { throw failure }
            return reply
        }
    }
}
