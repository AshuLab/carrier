import Foundation
import Testing
@testable import CarrierCore

@Test func theConfigFileIsInCarrierHomeWhenSetElseInTheHomeFolder() {
    #expect(configFilePath(environment: ["CARRIER_HOME": "/tmp/c"], home: "/Users/ana") == "/tmp/c/config.json")
    #expect(configFilePath(environment: [:], home: "/Users/ana") == "/Users/ana/.carrier/config.json")
}

@Test func theSocketIsUnderTheEnginesStateFolderOfTheCarrierFolder() {
    #expect(controlSocketPath(environment: ["CARRIER_HOME": "/tmp/c"], home: "/Users/ana") == "/tmp/c/engine/state/control.sock")
    #expect(controlSocketPath(environment: ["CARRIER_HOME": ""], home: "/Users/ana") == "/Users/ana/.carrier/engine/state/control.sock")
    #expect(controlSocketPath(environment: [:], home: "/Users/ana") == "/Users/ana/.carrier/engine/state/control.sock")
    #expect(engineFolder(environment: ["CARRIER_HOME": "/tmp/c"], home: "/Users/ana") == "/tmp/c/engine")
}

@Test func theSocketNeverReadsAConfigFile() throws {
    let folder = "/tmp/cc-home-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try Data("{\"keep\":\"/data/solve\"}".utf8).write(to: URL(fileURLWithPath: folder + "/config.json"))
    #expect(controlSocketPath(environment: ["CARRIER_HOME": folder], home: "/Users/ana") == folder + "/engine/state/control.sock")
}
