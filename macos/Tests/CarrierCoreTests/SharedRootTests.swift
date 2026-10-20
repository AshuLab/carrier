import Foundation
import Testing
@testable import CarrierCore

private func root(_ json: String?) -> String {
    sharedRoot(configJSON: json.map { Data($0.utf8) }, home: "/Users/ana")
}

@Test func theRootKeyIsUsed() { #expect(root("{\"root\":\"/data/solve\",\"logLevel\":\"info\"}") == "/data/solve") }

@Test func aMissingKeyFallsBackToTheDefault() { #expect(root("{\"logLevel\":\"info\"}") == "/Users/ana/.solve") }

@Test func aMissingFileFallsBackToTheDefault() { #expect(root(nil) == "/Users/ana/.solve") }

@Test func tildeIsExpanded() {
    #expect(root("{\"root\":\"~/work/solve\"}") == "/Users/ana/work/solve")
    #expect(root("{\"root\":\"~\"}") == "/Users/ana")
    #expect(root("{\"root\":\"~other/solve\"}") == "~other/solve")
}

@Test func unreadableJsonFallsBackToTheDefault() {
    #expect(root("{\"root\":") == "/Users/ana/.solve")
    #expect(root("[1,2]") == "/Users/ana/.solve")
    #expect(root("{\"root\":42}") == "/Users/ana/.solve")
    #expect(root("{\"root\":\"\"}") == "/Users/ana/.solve")
}

@Test func theConfigFileIsInCarrierHomeWhenSetElseInTheHomeFolder() {
    #expect(configFilePath(environment: ["CARRIER_HOME": "/tmp/c"], home: "/Users/ana") == "/tmp/c/config.json")
    #expect(configFilePath(environment: [:], home: "/Users/ana") == "/Users/ana/.carrier/config.json")
}

@Test func theSocketIsInTheOrchestratorFolderOfTheRoot() throws {
    let folder = "/tmp/cc-home-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try Data("{\"root\":\"/data/solve\"}".utf8).write(to: URL(fileURLWithPath: folder + "/config.json"))

    #expect(controlSocketPath(environment: ["CARRIER_HOME": folder], home: "/Users/ana") == "/data/solve/orchestrator/control.sock")
    #expect(controlSocketPath(environment: ["CARRIER_HOME": folder + "/none"], home: "/Users/ana") == "/Users/ana/.solve/orchestrator/control.sock")
}
