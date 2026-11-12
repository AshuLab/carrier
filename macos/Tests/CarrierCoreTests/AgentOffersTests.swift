import Foundation
import Testing
@testable import CarrierCore

@Test func theFingerprintFollowsTheAccountsAndTheChatAgentsFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("chat"), withIntermediateDirectories: true)
    let empty = agentOfferFingerprint(carrierFolder: folder.path)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("providers.json"))
    let withProviders = agentOfferFingerprint(carrierFolder: folder.path)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("chat/chat.json"))
    let withBoth = agentOfferFingerprint(carrierFolder: folder.path)
    #expect(Set([empty, withProviders, withBoth]).count == 3 && withBoth == agentOfferFingerprint(carrierFolder: folder.path))
}
