import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: ["Claude", "Codex", "Antigravity"])
func eachProviderWeNameHasItsBundledMark(agent: String) throws {
    let url = try #require(providerIconURL(agent))
    #expect(FileManager.default.fileExists(atPath: url.path), "\(agent): \(url.path)")
}

@Test func aProviderWithoutAMarkGetsNone() {
    #expect(providerIconURL("Someone else") == nil)
}
