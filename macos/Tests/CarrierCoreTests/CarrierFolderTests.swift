import Foundation
import Testing
@testable import CarrierCore

@Test func theConfigFileIsInCarrierHomeWhenSetElseInTheHomeFolder() {
    #expect(configFilePath(environment: ["CARRIER_HOME": "/tmp/c"], home: "/Users/ana") == "/tmp/c/engine.json")
    #expect(configFilePath(environment: [:], home: "/Users/ana") == "/Users/ana/.carrier/engine.json")
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
    try Data("{\"keep\":\"/data/solve\"}".utf8).write(to: URL(fileURLWithPath: folder + "/engine.json"))
    #expect(controlSocketPath(environment: ["CARRIER_HOME": folder], home: "/Users/ana") == folder + "/engine/state/control.sock")
}

@Test func theTopHoldsTheEditedFilesAndEachProcessSplitsItsFolderByLifecycle() {
    let places = CarrierPlaces(folder: "/h")
    #expect([places.engineConfig, places.chatConfig, places.providers] == ["/h/engine.json", "/h/chat.json", "/h/providers.json"])
    #expect([places.engineLogs, places.engineStartLog, places.controlSocket] == ["/h/engine/logs", "/h/engine/logs/app-start.log", "/h/engine/state/control.sock"])
    #expect([places.chatSocket, places.chatStartLog, places.chatWorktrees, places.chatProjects, places.chatAttachments] == [
        "/h/chat/state/chat.sock", "/h/chat/logs/app-start.log", "/h/chat/worktrees", "/h/chat/projects", "/h/chat/attachments",
    ])
    #expect([places.terminals, places.dictations, places.dictationStatistics, places.dictationAudio] == [
        "/h/app/state/terminals.json", "/h/app/state/dictations.jsonl", "/h/app/state/dictation-statistics.json", "/h/app/state/audio",
    ])
    #expect([places.dictationLog, places.speechModels, places.zshShim] == ["/h/app/logs/dictation.log", "/h/app/cache/models", "/h/app/cache/zsh-bottom-prompt"])
}
