import Foundation
import Testing
@testable import CarrierCore

// The two contracts with the engine that fail silently: a capability name the app does not know (the feature never shows)
// and a config default or rule that differs from the engine's. The TypeScript tests write the files
// (src/control/capabilities-contract.test.ts, src/config/engine-config-contract.test.ts); UPDATE_FIXTURES=1 rewrites them.

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

private func golden(_ name: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(name))) as? [String: Any])
}

/// Cases the app knows that no host announces, each on purpose.
private let unannounced: [ControlClient.Capability: String] = [
    .regenerateTitle: "the app's own request for a title again; no host announces it yet (docs/specs/sessions-in-the-app.md)",
]

@Test func everyCapabilityAHostAnnouncesIsACaseTheAppKnows() throws {
    let file = try golden("capabilities.json")
    let announced = (file["engine"] as? [String] ?? []) + (file["chat"] as? [String] ?? [])
    #expect(announced.isEmpty == false)
    #expect(announced.filter { ControlClient.Capability(rawValue: $0) == nil } == [])
    let silent = ControlClient.Capability.allCases.filter { announced.contains($0.rawValue) == false }
    #expect(Set(silent) == Set(unannounced.keys))
}

@Test func theFixtureServerAnnouncesOnlyNamesTheAppKnows() throws {
    let server = try FixtureServer(fixtures: fixtures.path)
    defer { server.stop() }
    for hello in [server.hello, server.chatHello] {
        let names = try #require(JSONSerialization.jsonObject(with: hello) as? [String: Any])["capabilities"] as? [String] ?? []
        #expect(names.isEmpty == false)
        #expect(names.filter { ControlClient.Capability(rawValue: $0) == nil } == [])
    }
}

@Test func theAppHasTheEnginesConfigDefaults() throws {
    let defaults = try JSONSerialization.data(withJSONObject: try #require(try golden("engine-config.json")["defaults"]))
    #expect(EngineConfig(json: defaults) == EngineConfig())
}

@Test func theAppRefusesWhatTheEngineRefuses() throws {
    let cases = try #require(try golden("engine-config.json")["cases"] as? [[String: Any]])
    #expect(cases.isEmpty == false)
    for item in cases {
        let field = try #require(item["field"] as? String), valid = try #require(item["valid"] as? Bool)
        let path = field.split(separator: ".").map(String.init)
        let file: [String: Any] = path.count == 1 ? [path[0]: item["value"]!] : [path[0]: [path[1]: item["value"]!]]
        let config = EngineConfig(json: try JSONSerialization.data(withJSONObject: file))
        #expect((config.problems[path.last!] == nil) == valid, "\(field) = \(item["value"]!)")
    }
}
